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
  source = "github.com/kbrockhoff/terraform-aws-bastion//modules/deployer"

  name_prefix   = "prod-usw2" # same prefix the pipeline uses for the parent module
  iam_role_name = module.cicd_role.role_name
  partition     = data.aws_partition.current.partition
  region        = data.aws_region.current.region
  account_id    = data.aws_caller_identity.current.account_id
}
```

Leave `iam_role_name` empty to only create the policies and attach `policy_arns` elsewhere.

## Bastion-specific notes

- Two policies are created, `main` (EC2, Auto Scaling, DLM, KMS, CloudWatch, SNS) and `iam`
  (instance role, instance profile, DLM role, `iam:PassRole`), because one document exceeds the
  managed policy size limit.
- Set `additional_iam_policies` to the same list passed to the parent module's
  `additional_iam_policies`. `iam:AttachRolePolicy` is limited to those ARNs plus
  `AmazonSSMManagedInstanceCore` and `AmazonSSMPatchAssociation`.
- IAM statements are scoped to the exact names the parent creates (`<name_prefix>-inst` and
  `<name_prefix>-dlm-lifecycle-role`) rather than `<name_prefix>-*`, so the pipeline cannot
  modify its own `<name_prefix>-cicd-deployer` role. If the parent is given an existing
  `iam_instance_profile_name`, grant `iam:PassRole` on that profile's role separately.
- Launch templates, KMS keys and DLM policies have AWS-generated IDs, so create and manage
  actions are gated on a `Name` tag matching `<name_prefix>-*`.
- `ec2:RunInstances` is granted (only via a launch template) because Auto Scaling checks that the
  caller could launch from the template when the group is created or updated.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
| ---- | ------- |
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |

## Providers

| Name | Version |
| ---- | ------- |
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.69.1 |

## Modules

No modules.

## Resources

| Name | Type |
| ---- | ---- |
| [aws_iam_policy.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_policy) | resource |
| [aws_iam_role_policy_attachment.this](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_account_id"></a> [account\_id](#input\_account\_id) | AWS account ID where the parent module is deployed | `string` | n/a | yes |
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Organization unique prefix to use for resource names. Must match the name\_prefix used when deploying the parent module. e.g. 'prod-usw2'. | `string` | n/a | yes |
| <a name="input_region"></a> [region](#input\_region) | AWS region where the parent module is deployed | `string` | n/a | yes |
| <a name="input_additional_iam_policies"></a> [additional\_iam\_policies](#input\_additional\_iam\_policies) | IAM policy ARNs the parent module attaches to the bastion instance role via its additional\_iam\_policies input. The deployer may only attach these plus the AWS managed SSM policies the parent always attaches. | `list(string)` | `[]` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources. | `bool` | `true` | no |
| <a name="input_iam_role_name"></a> [iam\_role\_name](#input\_iam\_role\_name) | Name of an existing IAM role to attach the policies to, typically the role\_name output of terraform-aws-cicdrole. Leave empty to only create the policies. | `string` | `""` | no |
| <a name="input_partition"></a> [partition](#input\_partition) | AWS partition | `string` | `"aws"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags/labels to apply to all resources. | `map(string)` | `{}` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_policy_arns"></a> [policy\_arns](#output\_policy\_arns) | Map of deployer IAM policy ARNs keyed by policy purpose |
| <a name="output_policy_names"></a> [policy\_names](#output\_policy\_names) | Map of deployer IAM policy names keyed by policy purpose |
<!-- END_TF_DOCS -->
