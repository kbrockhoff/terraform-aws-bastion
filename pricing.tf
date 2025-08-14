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
  cloudwatch_metric_count = var.enabled && var.alarms_config.enabled ? 10 : 0 # ASG and EC2 metrics monitored by alarms
  cloudwatch_alarm_count  = var.enabled && var.alarms_config.enabled ? 10 : 0 # 10 CloudWatch alarms for comprehensive ASG monitoring
}
