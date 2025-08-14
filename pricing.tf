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
  ebs_volume_count        = local.effective_config.asg_max_size
  ebs_volume_size_gb      = var.root_block_device_volume_size
  ebs_volume_type         = "gp3" # Default EBS volume type since not configurable in launch template
  ec2_monthly_hours       = local.monthly_hours
}
