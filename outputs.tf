# ----
# Primary resources IDs and names
# ----

output "launch_template_id" {
  description = "ID of the launch template."
  value       = var.enabled ? aws_launch_template.bastion[0].id : ""
}

output "launch_template_arn" {
  description = "ARN of the launch template."
  value       = var.enabled ? aws_launch_template.bastion[0].arn : ""
}

output "autoscaling_group_id" {
  description = "ID of the autoscaling group."
  value       = var.enabled ? aws_autoscaling_group.bastion[0].id : ""
}

output "autoscaling_group_arn" {
  description = "ARN of the autoscaling group."
  value       = var.enabled ? aws_autoscaling_group.bastion[0].arn : ""
}

output "autoscaling_group_name" {
  description = "Name of the autoscaling group."
  value       = var.enabled ? aws_autoscaling_group.bastion[0].name : ""
}

output "role" {
  description = "Name of AWS IAM Role created and associated with the instance."
  value       = local.create_iam_resources ? aws_iam_role.bastion[0].name : ""
}

output "role_arn" {
  description = "ARN of AWS IAM Role created and associated with the instance."
  value       = local.create_iam_resources ? aws_iam_role.bastion[0].arn : ""
}

output "iam_instance_profile_name" {
  description = "Name of the IAM instance profile attached to the instance."
  value       = local.iam_instance_profile_name
}

output "autoscaling_schedule_scale_down_arn" {
  description = "ARN of the scale down autoscaling schedule."
  value       = var.enabled && local.effective_config.enable_schedule ? aws_autoscaling_schedule.scale_down[0].arn : ""
}

output "autoscaling_schedule_scale_up_arn" {
  description = "ARN of the scale up autoscaling schedule."
  value       = var.enabled && local.effective_config.enable_schedule ? aws_autoscaling_schedule.scale_up[0].arn : ""
}

# ----
# Encryption
# ----

output "kms_key_id" {
  description = "ID of the KMS key used for encryption"
  value       = var.enabled && var.encryption_config.create_kms_key ? aws_kms_key.bastion[0].key_id : ""
}

output "kms_key_arn" {
  description = "ARN of the KMS key used for encryption"
  value       = local.kms_key_id
}

output "kms_alias_name" {
  description = "Name of the KMS key alias"
  value       = var.enabled && var.encryption_config.create_kms_key ? aws_kms_alias.bastion[0].name : ""
}

# ----
# Monitoring
# ----

output "alarm_sns_topic_arn" {
  description = "ARN of the SNS topic used for alarm notifications"
  value       = local.alarm_sns_topic_arn
}

output "alarm_sns_topic_name" {
  description = "Name of the SNS topic used for alarm notifications"
  value       = var.enabled && local.effective_config.alarms_enabled && var.alarms_config.create_sns_topic ? aws_sns_topic.alarms[0].name : ""
}

# ----
# Pricing
# ----

output "monthly_cost_estimate" {
  description = "Estimated monthly cost in USD for module resources"
  value       = module.pricing.monthly_cost_estimate
}

output "cost_breakdown" {
  description = "Detailed breakdown of monthly costs by service"
  value       = module.pricing.cost_breakdown
}
