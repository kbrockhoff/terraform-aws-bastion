# AWS EC2 Bastion Host Terraform Module

Terraform module which creates a bastion host via autoscaling group on AWS. 
It takes an opinionated approach to resource placement, naming, tagging, and well-architected best 
practices.

## Features

- Autoscaling groug managed SSM session capable bastion hosts
- Scale to zero during off-hours
- Monthly cost estimate submodule
- Deployment pipeline least privilege IAM role submodule

## Usage

### Basic Example

```hcl
module "example" {
  source = "path/to/terraform-module"

  # ... other required arguments ...
}
```

### Complete Example

```hcl
module "example" {
  source = "path/to/terraform-module"

  # ... all available arguments ...
}
```

## Environment Type Configuration

The `environment_type` variable provides a standardized way to configure resource defaults based on environment 
characteristics. This follows cloud well-architected framework recommendations for different deployment stages. 
Resiliency settings comply with the recovery point objective (RPO) and recovery time objective (RTO) values in
the table below. Cost optimization settings focus on shutting down resources during off-hours.

### Available Environment Types

| Type | Use Case | Configuration Focus | RPO | RTO |
|------|----------|---------------------|-----|-----|
| `None` | Custom configuration | No defaults applied, use individual config values | N/A | N/A |
| `Ephemeral` | Temporary environments | Cost-optimized, minimal durability requirements | N/A | 48h |
| `Development` | Developer workspaces | Balanced cost and functionality for active development | 24h | 48h |
| `Testing` | Automated testing | Consistent, repeatable configurations | 24h | 48h |
| `UAT` | User acceptance testing | Production-like settings with some cost optimization | 12h | 24h |
| `Production` | Live systems | High availability, durability, and performance | 1h  | 4h  |
| `MissionCritical` | Critical production | Maximum reliability, redundancy, and monitoring | 5m  | 1h  |

### Usage Examples

#### Development Environment
```hcl
module "dev_resources" {
  source = "path/to/terraform-module"
  
  name_prefix      = "dev-usw2"
  environment_type = "Development"
  
  tags = {
    Environment = "development"
    Team        = "platform"
  }
}
```

#### Production Environment
```hcl
module "prod_resources" {
  source = "path/to/terraform-module"
  
  name_prefix      = "prod-usw2"
  environment_type = "Production"
  
  tags = {
    Environment = "production"
    Team        = "platform"
    Backup      = "required"
  }
}
```

#### Custom Configuration (None)
```hcl
module "custom_resources" {
  source = "path/to/terraform-module"
  
  name_prefix      = "custom-usw2"
  environment_type = "None"
  
  # Specify all individual configuration values
  # when environment_type is "None"
}
```
## Network Tags Configuration

Resources deployed to subnets use lookup by `NetworkTags` values to determine which subnets to deploy to. 
This eliminates the need to manage different subnet IDs variable values for each environment.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | >= 5.0 |

## Modules

| Name | Source | Version |
|------|--------|---------|
| <a name="module_pricing"></a> [pricing](#module\_pricing) | ./modules/pricing | n/a |

## Resources

| Name | Type |
|------|------|
| [aws_autoscaling_group.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_group) | resource |
| [aws_autoscaling_schedule.scale_down](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_schedule) | resource |
| [aws_autoscaling_schedule.scale_up](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/autoscaling_schedule) | resource |
| [aws_iam_instance_profile.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.kms_usage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.additional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_launch_template.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_sns_topic.alarms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Organization unique prefix to use for resource names. Recommend including environment and region. e.g. 'prod-usw2' | `string` | n/a | yes |
| <a name="input_additional_iam_policies"></a> [additional\_iam\_policies](#input\_additional\_iam\_policies) | Existing IAM policies (as ARNs) this instance should have in addition to AmazonSSMManagedInstanceCore. | `list(string)` | `[]` | no |
| <a name="input_alarms_config"></a> [alarms\_config](#input\_alarms\_config) | Configuration object for metric alarms and notifications | <pre>object({<br/>    enabled          = bool<br/>    create_sns_topic = bool<br/>    sns_topic_arn    = string<br/>  })</pre> | <pre>{<br/>  "create_sns_topic": true,<br/>  "enabled": false,<br/>  "sns_topic_arn": ""<br/>}</pre> | no |
| <a name="input_ami_filter"></a> [ami\_filter](#input\_ami\_filter) | List of maps used to create the AMI filter for the action runner AMI. | `map(list(string))` | <pre>{<br/>  "name": [<br/>    "amzn2-ami-hvm-2.*-x86_64-ebs"<br/>  ]<br/>}</pre> | no |
| <a name="input_ami_owners"></a> [ami\_owners](#input\_ami\_owners) | The list of owners used to select the AMI of action runner instances. | `list(string)` | <pre>[<br/>  "amazon"<br/>]</pre> | no |
| <a name="input_asg_config"></a> [asg\_config](#input\_asg\_config) | Configuration object for autoscaling group settings | <pre>object({<br/>    min_size         = number<br/>    max_size         = number<br/>    desired_capacity = number<br/>  })</pre> | <pre>{<br/>  "desired_capacity": 1,<br/>  "max_size": 1,<br/>  "min_size": 0<br/>}</pre> | no |
| <a name="input_cost_estimation_config"></a> [cost\_estimation\_config](#input\_cost\_estimation\_config) | Configuration object for monthly cost estimation | <pre>object({<br/>    enabled = bool<br/>  })</pre> | <pre>{<br/>  "enabled": true<br/>}</pre> | no |
| <a name="input_data_tags"></a> [data\_tags](#input\_data\_tags) | Additional tags to apply specifically to data storage resources (e.g., S3, RDS, EBS) beyond the common tags. | `map(string)` | `{}` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources | `bool` | `true` | no |
| <a name="input_encryption_config"></a> [encryption\_config](#input\_encryption\_config) | Configuration object for encryption settings and KMS key management | <pre>object({<br/>    create_kms_key               = bool<br/>    kms_key_id                   = string<br/>    kms_key_deletion_window_days = number<br/>  })</pre> | <pre>{<br/>  "create_kms_key": true,<br/>  "kms_key_deletion_window_days": 14,<br/>  "kms_key_id": ""<br/>}</pre> | no |
| <a name="input_environment_type"></a> [environment\_type](#input\_environment\_type) | Environment type for resource configuration defaults. Select 'None' to use individual config values. | `string` | `"Development"` | no |
| <a name="input_iam_instance_profile_name"></a> [iam\_instance\_profile\_name](#input\_iam\_instance\_profile\_name) | The name of the IAM instance profile to run the instance as or leave null to create a profile. | `string` | `null` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | Bastion instance type. | `string` | `"t2.micro"` | no |
| <a name="input_monitoring_config"></a> [monitoring\_config](#input\_monitoring\_config) | Configuration object for optional monitoring | <pre>object({<br/>    enabled = bool<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_networktags_name"></a> [networktags\_name](#input\_networktags\_name) | Name of the network tags key used for subnet classification | `string` | `"NetworkTags"` | no |
| <a name="input_networktags_value_subnets"></a> [networktags\_value\_subnets](#input\_networktags\_value\_subnets) | Network tag values to use in looking up a random subnet to place instance in. Only used if subnet not specified. | `string` | `"private"` | no |
| <a name="input_networktags_value_vpc"></a> [networktags\_value\_vpc](#input\_networktags\_value\_vpc) | Network tag value to use for VPC lookup | `string` | `"standard"` | no |
| <a name="input_root_block_device_volume_size"></a> [root\_block\_device\_volume\_size](#input\_root\_block\_device\_volume\_size) | The volume size (in GiB) to provision for the root block device. It cannot be smaller than the AMI it refers to. | `number` | `8` | no |
| <a name="input_schedule_config"></a> [schedule\_config](#input\_schedule\_config) | Configuration object for autoscaling schedules | <pre>object({<br/>    enabled             = bool<br/>    timezone            = string<br/>    scale_down_schedule = string<br/>    scale_up_schedule   = string<br/>  })</pre> | <pre>{<br/>  "enabled": false,<br/>  "scale_down_schedule": "0 18 * * MON-FRI",<br/>  "scale_up_schedule": "0 8 * * MON-FRI",<br/>  "timezone": "UTC"<br/>}</pre> | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Security groups to apply to the instance if not using standard. | `list(string)` | `[]` | no |
| <a name="input_ssh_user"></a> [ssh\_user](#input\_ssh\_user) | Default SSH user for this AMI. e.g. `ec2-user` for Amazon Linux and `ubuntu` for Ubuntu systems. | `string` | `"ec2-user"` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags/labels to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_use_standard_security_group"></a> [use\_standard\_security\_group](#input\_use\_standard\_security\_group) | Set to false to supply own security groups instead of using one provided by standard VPC. | `bool` | `true` | no |
| <a name="input_user_data"></a> [user\_data](#input\_user\_data) | User data content. Will be ignored if `user_data_base64` is set. | `list(string)` | `[]` | no |
| <a name="input_user_data_base64"></a> [user\_data\_base64](#input\_user\_data\_base64) | The Base64-encoded user data to provide when launching the instances. If this is set then `user_data` will not be used. | `string` | `""` | no |
| <a name="input_user_data_template"></a> [user\_data\_template](#input\_user\_data\_template) | User Data template to use for provisioning EC2 Bastion Host. | `string` | `"templates/amazon-linux.sh.tpl"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alarm_sns_topic_arn"></a> [alarm\_sns\_topic\_arn](#output\_alarm\_sns\_topic\_arn) | ARN of the SNS topic used for alarm notifications |
| <a name="output_alarm_sns_topic_name"></a> [alarm\_sns\_topic\_name](#output\_alarm\_sns\_topic\_name) | Name of the SNS topic used for alarm notifications |
| <a name="output_autoscaling_group_arn"></a> [autoscaling\_group\_arn](#output\_autoscaling\_group\_arn) | ARN of the autoscaling group. |
| <a name="output_autoscaling_group_id"></a> [autoscaling\_group\_id](#output\_autoscaling\_group\_id) | ID of the autoscaling group. |
| <a name="output_autoscaling_group_name"></a> [autoscaling\_group\_name](#output\_autoscaling\_group\_name) | Name of the autoscaling group. |
| <a name="output_autoscaling_schedule_scale_down_arn"></a> [autoscaling\_schedule\_scale\_down\_arn](#output\_autoscaling\_schedule\_scale\_down\_arn) | ARN of the scale down autoscaling schedule. |
| <a name="output_autoscaling_schedule_scale_up_arn"></a> [autoscaling\_schedule\_scale\_up\_arn](#output\_autoscaling\_schedule\_scale\_up\_arn) | ARN of the scale up autoscaling schedule. |
| <a name="output_cost_breakdown"></a> [cost\_breakdown](#output\_cost\_breakdown) | Detailed breakdown of monthly costs by service |
| <a name="output_iam_instance_profile_name"></a> [iam\_instance\_profile\_name](#output\_iam\_instance\_profile\_name) | Name of the IAM instance profile attached to the instance. |
| <a name="output_kms_alias_name"></a> [kms\_alias\_name](#output\_kms\_alias\_name) | Name of the KMS key alias |
| <a name="output_kms_key_arn"></a> [kms\_key\_arn](#output\_kms\_key\_arn) | ARN of the KMS key used for encryption |
| <a name="output_kms_key_id"></a> [kms\_key\_id](#output\_kms\_key\_id) | ID of the KMS key used for encryption |
| <a name="output_launch_template_arn"></a> [launch\_template\_arn](#output\_launch\_template\_arn) | ARN of the launch template. |
| <a name="output_launch_template_id"></a> [launch\_template\_id](#output\_launch\_template\_id) | ID of the launch template. |
| <a name="output_monthly_cost_estimate"></a> [monthly\_cost\_estimate](#output\_monthly\_cost\_estimate) | Estimated monthly cost in USD for module resources |
| <a name="output_role"></a> [role](#output\_role) | Name of AWS IAM Role created and associated with the instance. |
| <a name="output_role_arn"></a> [role\_arn](#output\_role\_arn) | ARN of AWS IAM Role created and associated with the instance. |
<!-- END_TF_DOCS -->    

## License

This project is licensed under the Apache License, Version 2.0 - see the [LICENSE](LICENSE) file for details.
