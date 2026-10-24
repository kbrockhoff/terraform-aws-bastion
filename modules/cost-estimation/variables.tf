variable "enabled" {
  description = "Set to false to prevent the module from creating any resources"
  type        = bool
  default     = true
}

variable "region" {
  description = "AWS region where the parent module deploys its resources, e.g. us-west-2"
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
  description = "Number of CloudWatch custom metric-months (e.g. EC2 detailed monitoring metrics) to include in cost estimation"
  type        = number
  default     = 0

  validation {
    condition     = var.cloudwatch_metric_count >= 0
    error_message = "CloudWatch metric count must be zero or positive."
  }
}

variable "cloudwatch_alarm_count" {
  description = "Number of standard resolution CloudWatch alarm metrics to include in cost estimation (a metric math alarm counts once per metric it queries)"
  type        = number
  default     = 0

  validation {
    condition     = var.cloudwatch_alarm_count >= 0
    error_message = "CloudWatch alarm count must be zero or positive."
  }
}

variable "sns_requests_monthly" {
  description = "Number of SNS publish requests per month to include in cost estimation"
  type        = number
  default     = 0

  validation {
    condition     = var.sns_requests_monthly >= 0
    error_message = "SNS requests per month must be zero or positive."
  }
}

variable "ec2_instance_type" {
  description = "EC2 instance type for cost estimation"
  type        = string
  default     = "t3.micro"

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]*\\.[a-z0-9]+$", var.ec2_instance_type))
    error_message = "EC2 instance type must look like family.size, e.g. t3.micro."
  }
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

variable "ec2_monthly_hours" {
  description = "Hours per month each EC2 instance runs; 730 for always-on, less when a schedule scales the group down"
  type        = number
  default     = 730

  validation {
    condition     = var.ec2_monthly_hours >= 0
    error_message = "EC2 monthly hours must be zero or positive."
  }
}

variable "ebs_root_volume_type" {
  description = "EBS volume type of the root volumes"
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "st1", "sc1"], var.ebs_root_volume_type)
    error_message = "EBS volume type must be one of: gp2, gp3, io1, io2, st1, sc1."
  }
}

variable "ebs_root_volume_gb" {
  description = "GB-months of root volume storage to include in cost estimation (count x size x fraction of the month the volumes exist)"
  type        = number
  default     = 0

  validation {
    condition     = var.ebs_root_volume_gb >= 0
    error_message = "EBS root volume GB-months must be zero or positive."
  }
}

variable "ebs_data_volume_type" {
  description = "EBS volume type of the additional data volumes"
  type        = string
  default     = "gp3"

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "st1", "sc1"], var.ebs_data_volume_type)
    error_message = "EBS volume type must be one of: gp2, gp3, io1, io2, st1, sc1."
  }
}

variable "ebs_data_volume_gb" {
  description = "GB-months of additional data volume storage to include in cost estimation (count x size x fraction of the month the volumes exist)"
  type        = number
  default     = 0

  validation {
    condition     = var.ebs_data_volume_gb >= 0
    error_message = "EBS data volume GB-months must be zero or positive."
  }
}
