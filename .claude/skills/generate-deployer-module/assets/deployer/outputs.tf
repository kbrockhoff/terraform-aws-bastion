output "policy_arns" {
  description = "Map of deployer IAM policy ARNs keyed by policy purpose"
  value       = { for k, v in aws_iam_policy.this : k => v.arn }
}

output "policy_names" {
  description = "Map of deployer IAM policy names keyed by policy purpose"
  value       = { for k, v in aws_iam_policy.this : k => v.name }
}
