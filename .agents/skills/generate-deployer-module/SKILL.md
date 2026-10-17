---
name: generate-deployer-module
description: >
  Generates or regenerates the modules/deployer submodule of a kbrockhoff Terraform module built
  from the terraform-module template. The deployer creates least privilege IAM managed policies
  that let the CI/CD role from terraform-aws-cicdrole plan, apply and destroy the parent module.
  Use when creating a new terraform-aws-* module from the template, when the template's
  placeholder deployer still has module_short_name = "xxx", when parent module resources were
  added or changed and the deployer permissions must follow, or when asked to write or review
  CI/CD deploy permissions for one of these modules.
---

# Generate the deployer submodule

The deployer submodule turns "what this module creates" into "what CI/CD may do". It owns
**only** the permissions to manage the parent module's resources. Role, OIDC trust and Terraform
state access belong to `terraform-aws-cicdrole` and must never be duplicated here.

Read `references/contract.md` before writing anything. It fixes the inputs, outputs, file
layout, naming and policy rules every deployer must follow. This file covers the workflow.

## Inputs to confirm

- **Target repo**: a `terraform-aws-<name>` checkout. Work on a feature branch
  (`feature/deployer-module`), never on `main`.
- **Short name**: `<name>` from the repo name, e.g. `terraform-aws-vpc` gives `vpc`. It becomes
  `local.module_short_name`.

## Workflow

### 1. Lay down the skeleton

If `modules/deployer/` is missing, or still the template placeholder, copy every file from
`assets/deployer/` into `<repo>/modules/deployer/`. Then:
- Set `local.module_short_name` in `locals.tf`.
- Copy `required_version` from the parent `versions.tf` into `modules/deployer/versions.tf`.
- In `README.md`, replace `terraform-aws-xxx` with the real repo name.

If a compliant deployer already exists, keep its structure and edit the policy documents only.

### 2. Inventory what the parent module manages

List every resource and data source outside `modules/deployer`, including resources inside
other submodules the root calls:

```bash
grep -rnE --include='*.tf' '^(resource|data) "' . \
  | grep -v -e '^./examples/' -e '^./test/' -e '/\.terraform/' -e '^./modules/deployer/'
```

For each resource, record:
1. How it is **named**: from `name_prefix` (scope ARNs to `${var.name_prefix}-*`), or AWS-generated
   IDs (scope to the account/region wildcard and add tag conditions).
2. Its **lifecycle API calls** in the AWS provider: create, read/describe/list (refresh and plan),
   update (every mutable argument the module sets), tag/untag, delete.
3. **Side permissions**: `iam:PassRole` for roles handed to services, `kms:CreateGrant`/`Decrypt`
   for encrypted resources, `iam:CreateServiceLinkedRole` (scoped by `iam:AWSServiceName`) for
   services that create one on first use, such as Auto Scaling or ElastiCache.

Data sources need their read actions too. `aws_caller_identity` needs `sts:GetCallerIdentity`,
and `aws_ami`, `aws_vpc`, `aws_subnets` and similar need `ec2:Describe*`.

Use the service authorization reference to find which actions support resource-level
permissions and condition keys:
`https://docs.aws.amazon.com/service-authorization/latest/reference/list_<service>.html`.
If the `aws-iam` skill is available, use it for condition-operator and PassRole gotchas.

### 3. Write the policy documents

Edit `data "aws_iam_policy_document" "main"` in `modules/deployer/main.tf`:
- Keep the template statements that still apply: `CallerIdentity`, `PricingRead` (only if the
  parent has the pricing/cost-estimation submodule), KMS, alarms, SNS. Delete the ones for
  services the parent doesn't use, and trim actions inside them too. The template has no KMS
  data-plane actions. Add `kms:Encrypt`, `kms:Decrypt` or `kms:GenerateDataKey` only when the
  pipeline itself encrypts or decrypts with the key while creating a resource.
- Add one statement per service and purpose, following the contract's scoping rules. Sort
  actions alphabetically inside each statement.
- Put actions without resource-level support in a single `<Service>Global` or `<Service>Describe`
  statement on `*`.

Split into a second document only when the size check fails. Add
`data "aws_iam_policy_document" "<concern>"` and a matching entry in `local.policy_documents`.
Prefer concern names such as `network`, `compute` or `iam`.

### 4. Document

`README.md` above `<!-- BEGIN_TF_DOCS -->` holds the purpose, the cicdrole usage example and
any module-specific notes, such as extra inputs or permissions that are wider than usual and why.
Run `terraform-docs .` from the repo root **before** making hand edits to any other README. The
repo config recurses into `modules/`. If the local terraform-docs version reformats unrelated
READMEs, restore them with `git checkout -- <file>` right away, then make your hand edits. A
checkout done afterwards would wipe them.

### 5. Verify

Run the bundled checker. It works offline with fake credentials:

```bash
<this-skill-dir>/scripts/check-deployer.sh <repo>/modules/deployer
```

When the deployer has optional statements behind extra inputs, run it again with those enabled,
so the largest policy variant also gets size-checked:

```bash
DEPLOYER_EXTRA_ARGS='backward_compatibility_enabled = true' <this-skill-dir>/scripts/check-deployer.sh <repo>/modules/deployer
```

It checks fmt, validate and tflint, and checks that the contract's inputs and outputs exist and
that no role or OIDC resources were added. It then plans the module three ways: attached to a
stub cicdrole role, policy-only, and disabled. It fails if any policy exceeds 6,144 characters.

Also run from the repo root: `make check` and `make lint`. If CI runs checkov, run it on the
deployer with CI's exact `--skip-check` list from `.github/workflows/terraform-ci.yml`
(`checkov -d modules/deployer --framework terraform --compact --quiet --skip-check <list>`).
Scan the deployer directory by itself, because a pre-existing repo-wide failure would hide new ones.

Optional live verification (needs credentials and the user's go-ahead, because it creates
real resources): attach the policies to a sandbox cicdrole role, run an example's
`apply` and `destroy` as that role, and add any `AccessDenied` actions you find. Running
`aws accessanalyzer validate-policy --policy-type IDENTITY_POLICY` on each rendered policy also
catches invalid actions and condition keys.

### 6. Report

Summarize the policies created (name, size, statement count), any permissions on `*` or
account-wide wildcards and why, and anything you could not verify offline. Commit with a
Conventional Commit such as `feat(deployer): least privilege CI/CD policies for <name>` only if
the user asks for a commit.

## Common mistakes

- Adding Terraform state S3 or DynamoDB statements. cicdrole already grants them.
- Using `iam_role_arn` and `split("/", arn)[1]`. This breaks on role paths. The contract
  takes `iam_role_name`.
- Using `count` or `for_each` on values that are unknown at plan time. Policy map keys must be
  static strings.
- Covering only create. Plans fail without the Describe/Get/List calls, and destroys fail
  without Delete/Detach/Disassociate.
- Scoping IAM roles or PassRole to `role/${var.name_prefix}-*`. That matches the cicdrole role
  itself and lets the pipeline escalate its own permissions. Use exact role names.
- Scoping to `${var.name_prefix}*` without the hyphen. That lets `prod` match `production-...`.
- Forgetting `kms:CreateGrant` for services that encrypt with the module's CMK (EBS, logs,
  DynamoDB) and `kms:DescribeKey` for resources that validate a key ARN.
