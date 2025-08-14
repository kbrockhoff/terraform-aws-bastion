variable "enabled" {
  description = "Set to false to prevent the module from creating any resources"
  type        = bool
  default     = true
}

variable "region" {
  description = "AWS region"
  type        = string
}

variable "kms_key_count" {
  description = "Number of KMS keys to include in cost estimation"
  type        = number
  default     = 0

  validation {
    condition     = var.kms_key_count >= 0
    error_message = "KMS key count must be zero or positive."
  }
}

variable "cloudwatch_metric_count" {
  description = "Number of CloudWatch custom metrics to include in cost estimation"
  type        = number
  default     = 0

  validation {
    condition     = var.cloudwatch_metric_count >= 0
    error_message = "CloudWatch metric count must be zero or positive."
  }
}

variable "cloudwatch_alarm_count" {
  description = "Number of CloudWatch alarms to include in cost estimation"
  type        = number
  default     = 0

  validation {
    condition     = var.cloudwatch_alarm_count >= 0
    error_message = "CloudWatch alarm count must be zero or positive."
  }
}

variable "ec2_instance_type" {
  description = "EC2 instance type for cost estimation"
  type        = string
  default     = "t3.nano"
}

variable "ec2_instance_count" {
  description = "Number of EC2 instances to include in cost estimation"
  type        = number
  default     = 0

  validation {
    condition     = var.ec2_instance_count >= 0
    error_message = "EC2 instance count must be zero or positive."
  }
}

variable "ebs_volume_size_gb" {
  description = "EBS volume size in GB for cost estimation"
  type        = number
  default     = 8

  validation {
    condition     = var.ebs_volume_size_gb > 0
    error_message = "EBS volume size must be positive."
  }
}

variable "ebs_volume_type" {
  description = "EBS volume type for cost estimation"
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "st1", "sc1"], var.ebs_volume_type)
    error_message = "EBS volume type must be one of: gp2, gp3, io1, io2, st1, sc1."
  }
}

variable "ebs_volume_count" {
  description = "Number of EBS volumes to include in cost estimation"
  type        = number
  default     = 0

  validation {
    condition     = var.ebs_volume_count >= 0
    error_message = "EBS volume count must be zero or positive."
  }
}

variable "ec2_monthly_hours" {
  description = "Number of hours per month for EC2 cost calculation (24 * 30.44 = average month)"
  type        = number
  default     = 730.56

  validation {
    condition     = var.ec2_monthly_hours > 0
    error_message = "EC2 monthly hours must be positive."
  }
}
