# Cost Estimation Terraform Module

Estimates the monthly cost of resources provisioned by the parent module.

<!-- BEGIN_TF_DOCS -->
## Requirements

| Name | Version |
|------|---------|
| <a name="requirement_terraform"></a> [terraform](#requirement\_terraform) | >= 1.5 |
| <a name="requirement_aws"></a> [aws](#requirement\_aws) | >= 5.0 |

## Providers

| Name | Version |
|------|---------|
| <a name="provider_aws"></a> [aws](#provider\_aws) | 6.8.0 |

## Modules

No modules.

## Resources

| Name | Type |
|------|------|

## Inputs

| Name | Description | Type | Default | Required |
|------|-------------|------|---------|:--------:|
| <a name="input_region"></a> [region](#input\_region) | AWS region | `string` | n/a | yes |
| <a name="input_cloudwatch_alarm_count"></a> [cloudwatch\_alarm\_count](#input\_cloudwatch\_alarm\_count) | Number of CloudWatch alarms to include in cost estimation | `number` | `0` | no |
| <a name="input_cloudwatch_metric_count"></a> [cloudwatch\_metric\_count](#input\_cloudwatch\_metric\_count) | Number of CloudWatch custom metrics to include in cost estimation | `number` | `0` | no |
| <a name="input_ebs_volume_count"></a> [ebs\_volume\_count](#input\_ebs\_volume\_count) | Number of EBS volumes to include in cost estimation | `number` | `0` | no |
| <a name="input_ebs_volume_size_gb"></a> [ebs\_volume\_size\_gb](#input\_ebs\_volume\_size\_gb) | EBS volume size in GB for cost estimation | `number` | `8` | no |
| <a name="input_ebs_volume_type"></a> [ebs\_volume\_type](#input\_ebs\_volume\_type) | EBS volume type for cost estimation | `string` | `"gp3"` | no |
| <a name="input_ec2_instance_count"></a> [ec2\_instance\_count](#input\_ec2\_instance\_count) | Number of EC2 instances to include in cost estimation | `number` | `0` | no |
| <a name="input_ec2_instance_type"></a> [ec2\_instance\_type](#input\_ec2\_instance\_type) | EC2 instance type for cost estimation | `string` | `"t3.nano"` | no |
| <a name="input_ec2_monthly_hours"></a> [ec2\_monthly\_hours](#input\_ec2\_monthly\_hours) | Number of hours per month for EC2 cost calculation (24 * 30.44 = average month) | `number` | `730.56` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources | `bool` | `true` | no |
| <a name="input_kms_key_count"></a> [kms\_key\_count](#input\_kms\_key\_count) | Number of KMS keys to include in cost estimation | `number` | `0` | no |

## Outputs

| Name | Description |
|------|-------------|
| <a name="output_cost_breakdown"></a> [cost\_breakdown](#output\_cost\_breakdown) | Detailed breakdown of monthly costs by service |
| <a name="output_ebs_monthly_cost_per_gb"></a> [ebs\_monthly\_cost\_per\_gb](#output\_ebs\_monthly\_cost\_per\_gb) | Monthly cost per GB for EBS volumes in USD |
| <a name="output_ec2_instance_hourly_cost"></a> [ec2\_instance\_hourly\_cost](#output\_ec2\_instance\_hourly\_cost) | Hourly cost per EC2 instance in USD |
| <a name="output_monthly_cost_estimate"></a> [monthly\_cost\_estimate](#output\_monthly\_cost\_estimate) | Total estimated monthly cost in USD for module resources |
<!-- END_TF_DOCS -->    