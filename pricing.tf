# ----
# Pricing Calculator
# ----

module "pricing" {
  source = "./modules/pricing"

  providers = {
    aws = aws.pricing
  }

  enabled                 = var.enabled && var.cost_estimation_config.enabled
  region                  = local.region
  kms_key_count           = var.enabled && var.encryption_config.create_kms_key ? 1 : 0
  cloudwatch_metric_count = local.actual_alarm_count
  cloudwatch_alarm_count  = local.actual_alarm_count
  ec2_instance_count      = local.effective_config.asg_max_size
  ec2_instance_type       = var.instance_type
  # Account for both root and additional data volumes
  ebs_volume_count = local.effective_config.asg_max_size * (var.additional_data_volume_config.enabled ? 2 : 1)
  # Use weighted average for volume size when additional volume is enabled
  ebs_volume_size_gb = var.additional_data_volume_config.enabled ? (
    (var.root_block_device_volume_size + var.additional_data_volume_config.size) / 2
  ) : var.root_block_device_volume_size
  ebs_volume_type   = local.ebs_volume_type
  ec2_monthly_hours = local.monthly_hours
}
