# Deployer IAM Terraform Module

Creates the least privilege IAM managed policies a CI/CD pipeline needs to provision and
deprovision the parent module's resources. The policies are designed to be attached to the
role created by [terraform-aws-cicdrole](https://github.com/kbrockhoff/terraform-aws-cicdrole),
which already grants Terraform S3 backend access and the OIDC trust, so neither is included here.

Apply this module from a privileged platform configuration, not from the pipeline itself.

## Usage

```hcl
module "cicd_role" {
  source = "github.com/kbrockhoff/terraform-aws-cicdrole"

  name_prefix   = "prod-usw2"
  cicd_provider = "github-actions"
  git_repos     = ["my-infra-repo"]
  # ...
}

module "deployer" {
  source = "github.com/kbrockhoff/terraform-aws-xxx//modules/deployer"

  name_prefix   = "prod-usw2" # same prefix the pipeline uses for the parent module
  iam_role_name = module.cicd_role.role_name
  partition     = data.aws_partition.current.partition
  region        = data.aws_region.current.region
  account_id    = data.aws_caller_identity.current.account_id
}
```

Leave `iam_role_name` empty to only create the policies and attach `policy_arns` elsewhere.

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
