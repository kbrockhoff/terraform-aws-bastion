# AWS EC2 Bastion Host Terraform Module

Terraform module which creates a bastion host via autoscaling group on AWS. 
It takes an opinionated approach to resource placement, naming, tagging, and well-architected best 
practices.

## Features

- Autoscaling group managed SSM session capable bastion hosts
- Read-only root filesystem for enhanced security
- Optional additional data volume for persistent storage
- Scale to zero during off-hours
- Monthly cost estimate submodule
- Deployment pipeline least privilege IAM role submodule

## Usage

### Basic Example

This example creates a bastion host with default settings:

```hcl
# Main AWS provider - uses the current region
provider "aws" {
  # This is the default provider used for VPC resources
}

# Pricing provider - always uses us-east-1 where the AWS Pricing API is available
provider "aws" {
  alias  = "pricing"
  region = "us-east-1"
}

module "bastion" {
  source = "kbrockhoff/bastion/aws"

  providers = {
    aws         = aws
    aws.pricing = aws.pricing
  }

  name_prefix = "dev-usw2"
  
  tags = {
    Environment = "development"
    ManagedBy   = "terraform"
  }
}
```

### Complete Example with All Options

This example demonstrates all available configuration options:

```hcl
# Main AWS provider - uses the current region
provider "aws" {
  # This is the default provider used for VPC resources
}

# Pricing provider - always uses us-east-1 where the AWS Pricing API is available
provider "aws" {
  alias  = "pricing"
  region = "us-east-1"
}

module "bastion" {
  source = "kbrockhoff/bastion/aws"

  providers = {
    aws         = aws
    aws.pricing = aws.pricing
  }

  # Core settings
  enabled          = true
  name_prefix      = "prod-usw2"
  environment_type = "Production"
  
  # Tags
  tags = {
    Environment = "production"
    Team        = "platform"
    CostCenter  = "engineering"
  }
  
  data_tags = {
    DataClassification = "internal"
  }
  
  # Cost estimation
  cost_estimation_config = {
    enabled = true
  }
  
  # Network configuration
  networktags_name          = "NetworkTags"
  networktags_value_vpc     = "standard"
  networktags_value_subnets = "private"
  use_standard_security_group = true
  security_group_ids        = []
  
  # Instance configuration
  instance_type              = "t3.micro"
  iam_instance_profile_name  = null  # Create new profile
  additional_iam_policies    = []
  
  # AMI configuration
  ami_filter = {
    name = ["amzn2-ami-hvm-2.*-x86_64-ebs"]
  }
  ami_owners = ["amazon"]
  
  # User data
  user_data_template = "templates/amazon-linux.sh.tpl"
  user_data          = []
  user_data_base64   = ""
  ssh_user           = "ec2-user"
  
  # Storage
  root_block_device_volume_size = 8
  
  # Auto Scaling Group configuration
  asg_config = {
    min_size         = 0
    max_size         = 2
    desired_capacity = 1
  }
  
  # Schedule configuration (scale to zero during off-hours)
  schedule_config = {
    enabled             = true
    timezone            = "America/Los_Angeles"
    scale_down_schedule = "0 18 * * MON-FRI"  # 6 PM weekdays
    scale_up_schedule   = "0 8 * * MON-FRI"   # 8 AM weekdays
  }
  
  # Encryption configuration
  encryption_config = {
    create_kms_key               = true
    kms_key_id                   = ""
    kms_key_deletion_window_days = 30
  }
  
  # Monitoring configuration
  monitoring_config = {
    enabled = true
  }
  
  # Alarms configuration
  alarms_config = {
    enabled          = true
    create_sns_topic = true
    sns_topic_arn    = ""
  }
}
```

### Minimal Production Example with Schedules

This example creates a production bastion that scales to zero during off-hours:

```hcl
provider "aws" {}

provider "aws" {
  alias  = "pricing"
  region = "us-east-1"
}

module "bastion" {
  source = "kbrockhoff/bastion/aws"

  providers = {
    aws         = aws
    aws.pricing = aws.pricing
  }

  name_prefix      = "prod-usw2"
  environment_type = "Production"
  
  # Enable scheduled scaling to save costs
  schedule_config = {
    enabled             = true
    timezone            = "America/Los_Angeles"
    scale_down_schedule = "0 19 * * MON-FRI"  # Scale down at 7 PM
    scale_up_schedule   = "0 7 * * MON-FRI"   # Scale up at 7 AM
  }
  
  # Enable monitoring and alarms
  monitoring_config = {
    enabled = true
  }
  
  alarms_config = {
    enabled          = true
    create_sns_topic = true
    sns_topic_arn    = ""
  }
  
  tags = {
    Environment = "production"
    Team        = "infrastructure"
  }
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
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.9.0 |

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
| [aws_cloudwatch_metric_alarm.at_max_capacity](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.capacity_not_met](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.excessive_scaling](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.failed_launches](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.high_cpu](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.no_instances_running](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.pending_termination_too_long](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.status_check_failed](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.termination_failures](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_cloudwatch_metric_alarm.unhealthy_instances](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/cloudwatch_metric_alarm) | resource |
| [aws_dlm_lifecycle_policy.data_volume_snapshots](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/dlm_lifecycle_policy) | resource |
| [aws_iam_instance_profile.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_instance_profile) | resource |
| [aws_iam_role.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role.dlm_lifecycle_role](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role) | resource |
| [aws_iam_role_policy.dlm_lifecycle_policy](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy.kms_usage](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy) | resource |
| [aws_iam_role_policy_attachment.additional](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/iam_role_policy_attachment) | resource |
| [aws_kms_alias.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_alias) | resource |
| [aws_kms_key.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/kms_key) | resource |
| [aws_launch_template.bastion](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/launch_template) | resource |
| [aws_sns_topic.alarms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic) | resource |
| [aws_sns_topic_policy.alarms](https://registry.terraform.io/providers/hashicorp/aws/latest/docs/resources/sns_topic_policy) | resource |

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_name_prefix"></a> [name\_prefix](#input\_name\_prefix) | Organization unique prefix to use for resource names. Recommend including environment and region. e.g. 'prod-usw2' | `string` | n/a | yes |
| <a name="input_additional_data_volume_config"></a> [additional\_data\_volume\_config](#input\_additional\_data\_volume\_config) | Configuration for additional EBS data volume. IMPORTANT: Since the root volume is mounted read-only for security, this additional volume is required for any persistent data storage or write operations | <pre>object({<br/>    enabled     = bool<br/>    type        = string<br/>    size        = number<br/>    iops        = number<br/>    throughput  = number<br/>    mount_point = string<br/>  })</pre> | <pre>{<br/>  "enabled": false,<br/>  "iops": 3000,<br/>  "mount_point": "/data",<br/>  "size": 10,<br/>  "throughput": 125,<br/>  "type": "gp3"<br/>}</pre> | no |
| <a name="input_additional_iam_policies"></a> [additional\_iam\_policies](#input\_additional\_iam\_policies) | Existing IAM policies (as ARNs) this instance should have in addition to AmazonSSMManagedInstanceCore. | `list(string)` | `[]` | no |
| <a name="input_alarms_config"></a> [alarms\_config](#input\_alarms\_config) | Configuration object for metric alarms and notifications | <pre>object({<br/>    enabled          = bool<br/>    create_sns_topic = bool<br/>    sns_topic_arn    = string<br/>  })</pre> | <pre>{<br/>  "create_sns_topic": true,<br/>  "enabled": false,<br/>  "sns_topic_arn": ""<br/>}</pre> | no |
| <a name="input_ami_filter"></a> [ami\_filter](#input\_ami\_filter) | List of maps used to create the AMI filter for the bastion host AMI. | `map(list(string))` | <pre>{<br/>  "name": [<br/>    "amzn2-ami-hvm-2.*-x86_64-ebs"<br/>  ]<br/>}</pre> | no |
| <a name="input_ami_owners"></a> [ami\_owners](#input\_ami\_owners) | The list of owners used to select the AMI of bastion host instances. | `list(string)` | <pre>[<br/>  "amazon"<br/>]</pre> | no |
| <a name="input_asg_config"></a> [asg\_config](#input\_asg\_config) | Configuration object for autoscaling group settings | <pre>object({<br/>    min_size         = number<br/>    max_size         = number<br/>    desired_capacity = number<br/>  })</pre> | <pre>{<br/>  "desired_capacity": 1,<br/>  "max_size": 1,<br/>  "min_size": 0<br/>}</pre> | no |
| <a name="input_cost_estimation_config"></a> [cost\_estimation\_config](#input\_cost\_estimation\_config) | Configuration object for monthly cost estimation | <pre>object({<br/>    enabled = bool<br/>  })</pre> | <pre>{<br/>  "enabled": true<br/>}</pre> | no |
| <a name="input_data_tags"></a> [data\_tags](#input\_data\_tags) | Additional tags to apply specifically to data storage resources (e.g., S3, RDS, EBS) beyond the common tags. | `map(string)` | `{}` | no |
| <a name="input_data_volume_snapshot_config"></a> [data\_volume\_snapshot\_config](#input\_data\_volume\_snapshot\_config) | Configuration for automated EBS snapshots of the additional data volume using AWS Data Lifecycle Manager (DLM) | <pre>object({<br/>    enabled           = bool<br/>    schedule_name     = string<br/>    schedule_interval = number<br/>    schedule_times    = list(string)<br/>    retention_count   = number<br/>    copy_tags         = bool<br/>  })</pre> | <pre>{<br/>  "copy_tags": true,<br/>  "enabled": false,<br/>  "retention_count": 7,<br/>  "schedule_interval": 24,<br/>  "schedule_name": "daily-snapshots",<br/>  "schedule_times": [<br/>    "03:00"<br/>  ]<br/>}</pre> | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources | `bool` | `true` | no |
| <a name="input_encryption_config"></a> [encryption\_config](#input\_encryption\_config) | Configuration object for encryption settings and KMS key management | <pre>object({<br/>    create_kms_key               = bool<br/>    kms_key_id                   = string<br/>    kms_key_deletion_window_days = number<br/>  })</pre> | <pre>{<br/>  "create_kms_key": true,<br/>  "kms_key_deletion_window_days": 14,<br/>  "kms_key_id": ""<br/>}</pre> | no |
| <a name="input_environment_type"></a> [environment\_type](#input\_environment\_type) | Environment type for resource configuration defaults. Select 'None' to use individual config values. | `string` | `"Development"` | no |
| <a name="input_iam_instance_profile_name"></a> [iam\_instance\_profile\_name](#input\_iam\_instance\_profile\_name) | The name of the IAM instance profile to run the instance as or leave null to create a profile. | `string` | `null` | no |
| <a name="input_instance_type"></a> [instance\_type](#input\_instance\_type) | Bastion instance type. | `string` | `"t3.micro"` | no |
| <a name="input_monitoring_config"></a> [monitoring\_config](#input\_monitoring\_config) | Configuration object for optional monitoring | <pre>object({<br/>    enabled = bool<br/>  })</pre> | <pre>{<br/>  "enabled": false<br/>}</pre> | no |
| <a name="input_networktags_name"></a> [networktags\_name](#input\_networktags\_name) | Name of the network tags key used for subnet classification | `string` | `"NetworkTags"` | no |
| <a name="input_networktags_value_subnets"></a> [networktags\_value\_subnets](#input\_networktags\_value\_subnets) | Network tag values to use in looking up a random subnet to place instance in. Only used if subnet not specified. | `string` | `"private"` | no |
| <a name="input_networktags_value_vpc"></a> [networktags\_value\_vpc](#input\_networktags\_value\_vpc) | Network tag value to use for VPC lookup | `string` | `"standard"` | no |
| <a name="input_root_block_device_volume_size"></a> [root\_block\_device\_volume\_size](#input\_root\_block\_device\_volume\_size) | The volume size (in GiB) to provision for the root block device. It cannot be smaller than the AMI it refers to. | `number` | `8` | no |
| <a name="input_schedule_config"></a> [schedule\_config](#input\_schedule\_config) | Configuration object for autoscaling schedules | <pre>object({<br/>    enabled             = bool<br/>    timezone            = string<br/>    scale_down_schedule = string<br/>    scale_up_schedule   = string<br/>  })</pre> | <pre>{<br/>  "enabled": false,<br/>  "scale_down_schedule": "0 18 * * MON-FRI",<br/>  "scale_up_schedule": "0 8 * * MON-FRI",<br/>  "timezone": "UTC"<br/>}</pre> | no |
| <a name="input_security_group_ids"></a> [security\_group\_ids](#input\_security\_group\_ids) | Security groups to apply to the instance if not using standard. | `list(string)` | `[]` | no |
| <a name="input_tags"></a> [tags](#input\_tags) | Tags/labels to apply to all resources | `map(string)` | `{}` | no |
| <a name="input_use_standard_security_group"></a> [use\_standard\_security\_group](#input\_use\_standard\_security\_group) | Set to false to supply own security groups instead of using one provided by standard VPC. | `bool` | `true` | no |
| <a name="input_user_data"></a> [user\_data](#input\_user\_data) | User data content. Will be ignored if `user_data_base64` is set. | `list(string)` | `[]` | no |
| <a name="input_user_data_base64"></a> [user\_data\_base64](#input\_user\_data\_base64) | The Base64-encoded user data to provide when launching the instances. If this is set then `user_data` will not be used. | `string` | `""` | no |
| <a name="input_user_data_template"></a> [user\_data\_template](#input\_user\_data\_template) | User Data template to use for provisioning EC2 Bastion Host. | `string` | `"templates/amazon-linux.sh.tpl"` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_alarm_at_max_capacity_arn"></a> [alarm\_at\_max\_capacity\_arn](#output\_alarm\_at\_max\_capacity\_arn) | ARN of the at max capacity alarm |
| <a name="output_alarm_capacity_not_met_arn"></a> [alarm\_capacity\_not\_met\_arn](#output\_alarm\_capacity\_not\_met\_arn) | ARN of the capacity not met alarm |
| <a name="output_alarm_excessive_scaling_arn"></a> [alarm\_excessive\_scaling\_arn](#output\_alarm\_excessive\_scaling\_arn) | ARN of the excessive scaling alarm |
| <a name="output_alarm_failed_launches_arn"></a> [alarm\_failed\_launches\_arn](#output\_alarm\_failed\_launches\_arn) | ARN of the failed launches alarm |
| <a name="output_alarm_high_cpu_arn"></a> [alarm\_high\_cpu\_arn](#output\_alarm\_high\_cpu\_arn) | ARN of the high CPU alarm |
| <a name="output_alarm_no_instances_running_arn"></a> [alarm\_no\_instances\_running\_arn](#output\_alarm\_no\_instances\_running\_arn) | ARN of the no instances running alarm |
| <a name="output_alarm_pending_termination_too_long_arn"></a> [alarm\_pending\_termination\_too\_long\_arn](#output\_alarm\_pending\_termination\_too\_long\_arn) | ARN of the pending termination too long alarm |
| <a name="output_alarm_sns_topic_arn"></a> [alarm\_sns\_topic\_arn](#output\_alarm\_sns\_topic\_arn) | ARN of the SNS topic used for alarm notifications |
| <a name="output_alarm_sns_topic_name"></a> [alarm\_sns\_topic\_name](#output\_alarm\_sns\_topic\_name) | Name of the SNS topic used for alarm notifications |
| <a name="output_alarm_status_check_failed_arn"></a> [alarm\_status\_check\_failed\_arn](#output\_alarm\_status\_check\_failed\_arn) | ARN of the status check failed alarm |
| <a name="output_alarm_termination_failures_arn"></a> [alarm\_termination\_failures\_arn](#output\_alarm\_termination\_failures\_arn) | ARN of the termination failures alarm |
| <a name="output_alarm_unhealthy_instances_arn"></a> [alarm\_unhealthy\_instances\_arn](#output\_alarm\_unhealthy\_instances\_arn) | ARN of the unhealthy instances alarm |
| <a name="output_autoscaling_group_arn"></a> [autoscaling\_group\_arn](#output\_autoscaling\_group\_arn) | ARN of the autoscaling group. |
| <a name="output_autoscaling_group_id"></a> [autoscaling\_group\_id](#output\_autoscaling\_group\_id) | ID of the autoscaling group. |
| <a name="output_autoscaling_group_name"></a> [autoscaling\_group\_name](#output\_autoscaling\_group\_name) | Name of the autoscaling group. |
| <a name="output_autoscaling_schedule_scale_down_arn"></a> [autoscaling\_schedule\_scale\_down\_arn](#output\_autoscaling\_schedule\_scale\_down\_arn) | ARN of the scale down autoscaling schedule. |
| <a name="output_autoscaling_schedule_scale_up_arn"></a> [autoscaling\_schedule\_scale\_up\_arn](#output\_autoscaling\_schedule\_scale\_up\_arn) | ARN of the scale up autoscaling schedule. |
| <a name="output_cost_breakdown"></a> [cost\_breakdown](#output\_cost\_breakdown) | Detailed breakdown of monthly costs by service |
| <a name="output_dlm_iam_role_arn"></a> [dlm\_iam\_role\_arn](#output\_dlm\_iam\_role\_arn) | ARN of the IAM role used by DLM for snapshot management |
| <a name="output_dlm_lifecycle_policy_arn"></a> [dlm\_lifecycle\_policy\_arn](#output\_dlm\_lifecycle\_policy\_arn) | ARN of the DLM lifecycle policy for data volume snapshots |
| <a name="output_dlm_lifecycle_policy_id"></a> [dlm\_lifecycle\_policy\_id](#output\_dlm\_lifecycle\_policy\_id) | ID of the DLM lifecycle policy for data volume snapshots |
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
