# ----
# Pricing Calculator
# ----

locals {
  # Instances the ASG keeps running: desired capacity clamped to the effective min/max size
  cost_instance_count = var.enabled ? max(
    local.effective_config.asg_min_size,
    min(var.asg_config.desired_capacity, local.effective_config.asg_max_size)
  ) : 0
  # Fraction of the month instances (and their delete-on-termination volumes) exist
  cost_running_fraction = local.monthly_hours / 730
  # EC2 detailed monitoring publishes 7 metrics per instance, billed as custom metrics
  cost_detailed_monitoring_metrics = var.monitoring_config.enabled ? 7 : 0
  # capacity_not_met and excessive_scaling each query two metrics, billed as two alarm metrics
  cost_alarm_metric_count = local.create_alarms ? local.actual_alarm_count + 2 : 0
}

module "pricing" {
  source = "./modules/cost-estimation"

  providers = {
    aws = aws.pricing
  }

  enabled = var.enabled && var.cost_estimation_config.enabled
  region  = local.region

  kms_key_count           = var.enabled && var.encryption_config.create_kms_key ? 1 : 0
  cloudwatch_metric_count = local.cost_instance_count * local.cost_detailed_monitoring_metrics * local.cost_running_fraction
  cloudwatch_alarm_count  = local.cost_alarm_metric_count
  # Assumes each alarm sends one notification per day (30 per month) to the module's topic
  sns_requests_monthly = local.create_sns_topic ? local.actual_alarm_count * 30 : 0

  ec2_instance_type  = var.instance_type
  ec2_instance_count = local.cost_instance_count
  ec2_monthly_hours  = local.monthly_hours

  ebs_root_volume_type = local.ebs_volume_type
  ebs_root_volume_gb   = local.cost_instance_count * var.root_block_device_volume_size * local.cost_running_fraction
  ebs_data_volume_type = var.additional_data_volume_config.type
  ebs_data_volume_gb = var.additional_data_volume_config.enabled ? (
    local.cost_instance_count * var.additional_data_volume_config.size * local.cost_running_fraction
  ) : 0
}
