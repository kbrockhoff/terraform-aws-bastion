# Cost Estimation Terraform Module

Estimates the monthly on-demand cost in USD of the resources the parent bastion module provisions,
using live prices from the AWS Pricing API.

The parent passes a provider pinned to `us-east-1`, where the Pricing API is available, and the
`region` it deploys to. Each price is looked up by `regionCode` with filters validated to match
exactly one product in every region.

## Components

| Key | Unit | Quantity passed by the parent |
|-----|------|-------------------------------|
| `kms_keys` | key-month | 1 when the module creates its KMS key |
| `cloudwatch_metrics` | metric-month | 7 detailed monitoring metrics per running instance, prorated by running hours, when `monitoring_config.enabled` |
| `cloudwatch_alarms` | alarm metric-month | alarms created, plus one extra for each second metric of the two metric math alarms |
| `sns_requests` | request | 30 notifications per alarm per month (one per day) when the module creates the SNS topic |
| `ec2_instances` | instance-hour | running instances x `ec2_monthly_hours` |
| `ebs_root_volumes` | GB-month | running instances x root volume size, prorated by running hours |
| `ebs_data_volumes` | GB-month | running instances x data volume size, prorated by running hours, when the data volume is enabled |

## Assumptions

- On-demand prices only; no Savings Plans, Reserved Instances or account free tiers.
- Tiered prices use the lowest paid tier.
- EC2 instances are Linux/UNIX, shared tenancy, with no pre-installed software. An instance type
  that is not offered in the region makes the lookup, and the plan, fail.
- Running instances are the ASG desired capacity clamped to its min and max size. Always-on
  instances run 730 hours a month; with a schedule the parent passes the scheduled hours.
- EBS volumes are deleted with their instances, so their storage is prorated by running hours.
- EBS provisioned IOPS and throughput above the gp3 baseline, io1/io2 IOPS, DLM snapshot storage
  and data transfer are not priced.
- The instance does not get a public IPv4 address (no `associate_public_ip_address`, and the
  standard VPC's subnets do not map public IPs on launch), so no public IPv4 charge is included.
- SNS requests assume one notification per alarm per day (30 per month).
- If a price can't be parsed, a us-east-1 default is used instead.

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

## Inputs

| Name | Description | Type | Default | Required |
| ---- | ----------- | ---- | ------- | :------: |
| <a name="input_region"></a> [region](#input\_region) | AWS region where the parent module deploys its resources, e.g. us-west-2 | `string` | n/a | yes |
| <a name="input_cloudwatch_alarm_count"></a> [cloudwatch\_alarm\_count](#input\_cloudwatch\_alarm\_count) | Number of standard resolution CloudWatch alarm metrics to include in cost estimation (a metric math alarm counts once per metric it queries) | `number` | `0` | no |
| <a name="input_cloudwatch_metric_count"></a> [cloudwatch\_metric\_count](#input\_cloudwatch\_metric\_count) | Number of CloudWatch custom metric-months (e.g. EC2 detailed monitoring metrics) to include in cost estimation | `number` | `0` | no |
| <a name="input_ebs_data_volume_gb"></a> [ebs\_data\_volume\_gb](#input\_ebs\_data\_volume\_gb) | GB-months of additional data volume storage to include in cost estimation (count x size x fraction of the month the volumes exist) | `number` | `0` | no |
| <a name="input_ebs_data_volume_type"></a> [ebs\_data\_volume\_type](#input\_ebs\_data\_volume\_type) | EBS volume type of the additional data volumes | `string` | `"gp3"` | no |
| <a name="input_ebs_root_volume_gb"></a> [ebs\_root\_volume\_gb](#input\_ebs\_root\_volume\_gb) | GB-months of root volume storage to include in cost estimation (count x size x fraction of the month the volumes exist) | `number` | `0` | no |
| <a name="input_ebs_root_volume_type"></a> [ebs\_root\_volume\_type](#input\_ebs\_root\_volume\_type) | EBS volume type of the root volumes | `string` | `"gp3"` | no |
| <a name="input_ec2_instance_count"></a> [ec2\_instance\_count](#input\_ec2\_instance\_count) | Number of EC2 instances to include in cost estimation | `number` | `0` | no |
| <a name="input_ec2_instance_type"></a> [ec2\_instance\_type](#input\_ec2\_instance\_type) | EC2 instance type for cost estimation | `string` | `"t3.micro"` | no |
| <a name="input_ec2_monthly_hours"></a> [ec2\_monthly\_hours](#input\_ec2\_monthly\_hours) | Hours per month each EC2 instance runs; 730 for always-on, less when a schedule scales the group down | `number` | `730` | no |
| <a name="input_enabled"></a> [enabled](#input\_enabled) | Set to false to prevent the module from creating any resources | `bool` | `true` | no |
| <a name="input_kms_key_count"></a> [kms\_key\_count](#input\_kms\_key\_count) | Number of KMS keys to include in cost estimation | `number` | `0` | no |
| <a name="input_sns_requests_monthly"></a> [sns\_requests\_monthly](#input\_sns\_requests\_monthly) | Number of SNS publish requests per month to include in cost estimation | `number` | `0` | no |

## Outputs

| Name | Description |
| ---- | ----------- |
| <a name="output_cost_breakdown"></a> [cost\_breakdown](#output\_cost\_breakdown) | Detailed breakdown of monthly costs by service |
| <a name="output_monthly_cost_estimate"></a> [monthly\_cost\_estimate](#output\_monthly\_cost\_estimate) | Total estimated monthly cost in USD for module resources |
<!-- END_TF_DOCS -->
