# Deployer Submodule Contract

Every Terraform module built from the `terraform-module` template ships a `modules/deployer`
submodule. It creates the least privilege IAM **managed policies** a CI/CD pipeline needs to
`plan`, `apply` and `destroy` the parent module. The policies are attached to the role created by
`terraform-aws-cicdrole`.

## Division of responsibility

| Concern | Owner |
|---------|-------|
| OIDC provider and role trust policy | terraform-aws-cicdrole |
| IAM role (`<name_prefix>-cicd-deployer`) | terraform-aws-cicdrole |
| Terraform S3 backend / lock table access | terraform-aws-cicdrole (`s3_backend_config`) |
| Permissions to manage the parent module's resources | **modules/deployer** |
| Attaching those permissions to the role | modules/deployer (`iam_role_name`), or the caller |

The deployer is applied by a privileged platform configuration alongside cicdrole,
never by the pipeline whose permissions it defines.

## Files

```
modules/deployer/
  README.md      # header + usage, terraform-docs injected between BEGIN/END_TF_DOCS
  locals.tf      # module_short_name, policy_name_prefix, policy_documents, attach_to_role,
                 # plus helper locals (ARN prefixes, exact resource names) as needed
  main.tf        # aws_iam_policy_document(s), aws_iam_policy.this, aws_iam_role_policy_attachment.this
  outputs.tf     # policy_arns, policy_names
  variables.tf   # exactly the inputs below
  versions.tf    # same required_version as the parent; aws >= 5.0
```

## Inputs (exact names, no extras unless the parent module genuinely needs them)

| Name | Type | Default | Notes |
|------|------|---------|-------|
| `enabled` | bool | `true` | Gates every resource |
| `name_prefix` | string | required | Same validation regex as the parent; must equal the prefix the pipeline deploys with |
| `iam_role_name` | string | `""` | Role to attach to, normally `module.<cicdrole>.role_name`. Empty = create policies only |
| `tags` | map(string) | `{}` | |
| `partition` | string | `"aws"` | |
| `region` | string | required | |
| `account_id` | string | required | 12-digit validation |

Use the role **name**, not the ARN: the name is known at plan time even when cicdrole creates the
role in the same apply, so `for_each` stays resolvable. Never derive the name by splitting an ARN.

A module-specific input is acceptable in two cases:
- The parent creates optional resources behind a feature flag. Mirror that flag with the
  parent's variable name and default, and gate the matching statements with `dynamic`, for
  example s3backend's `backward_compatibility_enabled` for the legacy DynamoDB lock table.
- A resource name can't be derived from `name_prefix` and the account ID.

Default every extra input so the policy-only path still works. Prefer computing exact names,
such as `${var.name_prefix}-tfstate-${var.account_id}`, over passing them in.

## Outputs (exact names)

| Name | Value |
|------|-------|
| `policy_arns` | `{ for k, v in aws_iam_policy.this : k => v.arn }` |
| `policy_names` | `{ for k, v in aws_iam_policy.this : k => v.name }` |

Maps with static keys let callers attach with `for_each` without unknown-key errors.

## Required implementation shape

```hcl
# locals.tf
locals {
  module_short_name  = "vpc" # repo name without "terraform-aws-"
  policy_name_prefix = "${var.name_prefix}-${local.module_short_name}-deployer"

  policy_documents = var.enabled ? {
    main    = data.aws_iam_policy_document.main[0].json
    network = data.aws_iam_policy_document.network[0].json # only when splitting is required
  } : {}

  attach_to_role = var.enabled && var.iam_role_name != ""
}

# main.tf
resource "aws_iam_policy" "this" {
  for_each    = local.policy_documents
  name        = "${local.policy_name_prefix}-${each.key}"
  description = "Least privilege permissions for CI/CD to deploy the ${local.module_short_name} module (${each.key})"
  policy      = each.value
  tags        = merge(var.tags, { Name = "${local.policy_name_prefix}-${each.key}" })
}

resource "aws_iam_role_policy_attachment" "this" {
  for_each   = local.attach_to_role ? aws_iam_policy.this : {}
  role       = var.iam_role_name
  policy_arn = each.value.arn
}
```

Each `data "aws_iam_policy_document"` uses `count = var.enabled ? 1 : 0`.

## Policy content rules

Always include:
- `sts:GetCallerIdentity` on `*` (the parent's `aws_caller_identity` data source).
- The pricing statement (`freetier:GetAccountPlanState`, `pricing:GetAttributeValues`,
  `pricing:GetProducts` on `*`) when the parent has the cost-estimation/pricing submodule.

Never include:
- `s3:*`/`dynamodb:*` on the Terraform **state** bucket or lock table (cicdrole grants it).
  Statements for buckets/tables the parent module itself *manages* are fine.
- `sts:AssumeRoleWithWebIdentity`, OIDC provider lookups, or creating the CI role itself.
- `Action: "*"`, `iam:*`, `kms:*`, or `Resource: "*"` on actions that support resource-level
  permissions.

Scoping:
- Scope ARNs to `${var.name_prefix}-*` wherever the resource name is set from `name_prefix`.
- Resource ARNs always use `arn:${var.partition}:<service>:${var.region}:${var.account_id}:...`
  (IAM and S3 omit region; S3 omits account).
- Actions with no resource-level support (e.g. `ec2:Describe*`, `kms:ListAliases`) go in a
  dedicated read-only statement on `*`. Create actions that only accept `*`, such as
  `kms:CreateKey` or `dlm:CreateLifecyclePolicy`, go in their own statement, gated on
  `aws:RequestTag/Name` wherever the service supports it.
- Service-to-service calls are authorized against the caller. An Auto Scaling group with a
  launch template needs `ec2:RunInstances`, `ec2:CreateTags` and `iam:PassRole` for the
  instance role; services that make a service-linked role on first use need
  `iam:CreateServiceLinkedRole` gated on `iam:AWSServiceName`.
- Resources whose ARN contains an AWS-generated ID (EC2, VPC, KMS keys) are scoped to the
  account/region wildcard, and tightened with `aws:RequestTag/Name` / `aws:ResourceTag/Name`
  conditions on create/delete actions where the service supports them.
- **IAM roles, instance profiles and PassRole use exact names** (`role/${var.name_prefix}-inst`),
  never `role/${var.name_prefix}-*`. That wildcard also matches cicdrole's own
  `${var.name_prefix}-cicd-deployer` role, which would let the pipeline rewrite its own
  permissions. `iam:PassRole` also gets an `iam:PassedToService` condition.
- `iam:AttachRolePolicy` / `DetachRolePolicy` are restricted with an `iam:PolicyARN` condition
  listing the managed policies the parent attaches. If the parent accepts extra policy ARNs,
  mirror that input.
- Tag-on-create: `ec2:CreateTags` needs an `ec2:CreateAction` condition listing the create calls.

Coverage: for every resource and data source in the parent module (root plus non-deployer
submodules), grant the Create, Read/Describe/List (refresh), Update, Tag/Untag and Delete calls
the AWS provider makes. Plan needs reads, apply needs writes, destroy needs deletes.

Special cases:
- **Adopted default resources** (`aws_default_security_group`, `aws_default_route_table`,
  `aws_default_network_acl`) exist before the module tags them, so `ec2:CreateAction` doesn't
  apply. Grant `ec2:CreateTags` gated on `aws:RequestTag/Name`, and note in the README that
  this lets the pipeline "claim" an untagged resource of that type by tagging it.
- **Resources shared through RAM** (transit gateways, IPAM pools) may live in another account.
  Use `*` for the account segment only on those resource types, and say why in a comment.
- **Account-wide settings** (e.g. `ec2:ModifyVpcBlockPublicAccessOptions`) can't be scoped.
  Call them out in the deployer README.

Size and count limits:
- Managed policy max is 6,144 characters excluding whitespace. Split by concern into extra
  `policy_documents` entries only when needed; keep each under roughly 5,500 for headroom.
- A role holds 10 managed policies by default (quota up to 20), and one cicdrole role may deploy
  several modules, so use as few policies as possible (target 1, max 3).

Trim to need: the template's KMS, alarm and SNS statements are a starting point. Drop actions
the parent's resources never call. KMS data-plane actions (`Encrypt`, `Decrypt`,
`GenerateDataKey`) are left out of the template, so add them only when the pipeline itself
encrypts or decrypts with the key. Prefer exact names (`alias/${var.name_prefix}-cmk`) over `-*` wildcards when the
parent uses a fixed suffix.

Sid naming: PascalCase, `<Service><Purpose>`, e.g. `KmsKeyManagement`, `Ec2Describe`.
