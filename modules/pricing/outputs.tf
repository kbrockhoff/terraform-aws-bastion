output "monthly_cost_estimate" {
  description = "Total estimated monthly cost in USD for module resources"
  value       = local.pricing_enabled ? local.total_monthly_cost : 0
}

output "cost_breakdown" {
  description = "Detailed breakdown of monthly costs by service"
  value       = local.pricing_enabled ? local.costs : {}
}

output "ec2_instance_hourly_cost" {
  description = "Hourly cost per EC2 instance in USD"
  value       = local.pricing_enabled && var.ec2_instance_count > 0 ? tonumber(local.ec2_instance_hourly) : 0
}

output "ebs_monthly_cost_per_gb" {
  description = "Monthly cost per GB for EBS volumes in USD"
  value       = local.pricing_enabled && var.ebs_volume_count > 0 ? tonumber(local.ebs_volume_monthly_per_gb) : 0
}
