# ----
# Common
# ----

variable "enabled" {
  description = "Set to false to prevent the module from creating any resources"
  type        = bool
  default     = true
}

variable "name_prefix" {
  description = "Organization unique prefix to use for resource names. Recommend including environment and region. e.g. 'prod-usw2'"
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name_prefix))
    error_message = "The name_prefix value must start with a lowercase letter, followed by 0 to 22 alphanumeric or hyphen characters, ending with alphanumeric, for a total length of 2 to 24 characters."
  }
}

variable "tags" {
  description = "Tags/labels to apply to all resources"
  type        = map(string)
  default     = {}
}

variable "data_tags" {
  description = "Additional tags to apply specifically to data storage resources (e.g., S3, RDS, EBS) beyond the common tags."
  type        = map(string)
  default     = {}
}

variable "environment_type" {
  description = "Environment type for resource configuration defaults. Select 'None' to use individual config values."
  type        = string
  default     = "Development"

  validation {
    condition = contains([
      "None", "Ephemeral", "Development", "Testing", "UAT", "Production", "MissionCritical"
    ], var.environment_type)
    error_message = "Environment type must be one of: None, Ephemeral, Development, Testing, UAT, Production, MissionCritical."
  }
}

variable "networktags_name" {
  description = "Name of the network tags key used for subnet classification"
  type        = string
  default     = "NetworkTags"

  validation {
    condition     = var.networktags_name != null && var.networktags_name != ""
    error_message = "Network tags name cannot be null or blank."
  }
}

variable "networktags_value_vpc" {
  description = "Network tag value to use for VPC lookup"
  type        = string
  default     = "standard"

  validation {
    condition     = var.networktags_value_vpc != null && var.networktags_value_vpc != ""
    error_message = "Network tags value for VPC cannot be null or blank."
  }
}

variable "networktags_value_subnets" {
  description = "Network tag values to use in looking up a random subnet to place instance in. Only used if subnet not specified."
  type        = string
  default     = "private"

  validation {
    condition     = contains(["public", "private", "database", "nonroutable"], var.networktags_value_subnets)
    error_message = "Network tags value for subnets must be one of: public, private, database, nonroutable."
  }
}

variable "use_standard_security_group" {
  description = "Set to false to supply own security groups instead of using one provided by standard VPC."
  type        = bool
  default     = true
}

variable "security_group_ids" {
  description = "Security groups to apply to the instance if not using standard."
  type        = list(string)
  default     = []
}

variable "instance_type" {
  description = "Bastion instance type."
  type        = string
  default     = "t3.micro"
}

variable "iam_instance_profile_name" {
  description = "The name of the IAM instance profile to run the instance as or leave null to create a profile."
  type        = string
  default     = null
}

variable "additional_iam_policies" {
  description = "Existing IAM policies (as ARNs) this instance should have in addition to AmazonSSMManagedInstanceCore."
  type        = list(string)
  default     = []
}

variable "ami_filter" {
  description = "List of maps used to create the AMI filter for the bastion host AMI."
  type        = map(list(string))
  default = {
    name = ["amzn2-ami-hvm-2.*-x86_64-ebs"]
  }
}

variable "ami_owners" {
  description = "The list of owners used to select the AMI of bastion host instances."
  type        = list(string)
  default     = ["amazon"]
}

variable "user_data_template" {
  description = "User Data template to use for provisioning EC2 Bastion Host."
  type        = string
  default     = "templates/amazon-linux.sh.tpl"
}

variable "user_data" {
  description = "User data content. Will be ignored if `user_data_base64` is set."
  type        = list(string)
  default     = []
}

variable "user_data_base64" {
  description = "The Base64-encoded user data to provide when launching the instances. If this is set then `user_data` will not be used."
  type        = string
  default     = ""
}

variable "root_block_device_volume_size" {
  description = "The volume size (in GiB) to provision for the root block device. It cannot be smaller than the AMI it refers to."
  type        = number
  default     = 8
}

variable "additional_data_volume_config" {
  description = "Configuration for additional EBS data volume. IMPORTANT: Since the root volume is mounted read-only for security, this additional volume is required for any persistent data storage or write operations"
  type = object({
    enabled     = bool
    type        = string
    size        = number
    iops        = number
    throughput  = number
    mount_point = string
  })
  default = {
    enabled     = false
    type        = "gp3"
    size        = 10
    iops        = 3000
    throughput  = 125
    mount_point = "/data"
  }

  validation {
    condition     = contains(["gp2", "gp3", "io1", "io2", "st1", "sc1"], var.additional_data_volume_config.type)
    error_message = "Volume type must be one of: gp2, gp3, io1, io2, st1, sc1."
  }

  validation {
    condition     = var.additional_data_volume_config.size >= 1 && var.additional_data_volume_config.size <= 16384
    error_message = "Volume size must be between 1 and 16384 GiB."
  }

  validation {
    condition = (
      var.additional_data_volume_config.type != "gp3" ||
      (var.additional_data_volume_config.iops >= 3000 && var.additional_data_volume_config.iops <= 16000)
    )
    error_message = "For gp3 volumes, IOPS must be between 3000 and 16000."
  }

  validation {
    condition = (
      var.additional_data_volume_config.type != "gp3" ||
      (var.additional_data_volume_config.throughput >= 125 && var.additional_data_volume_config.throughput <= 1000)
    )
    error_message = "For gp3 volumes, throughput must be between 125 and 1000 MiB/s."
  }

  validation {
    condition     = can(regex("^/[a-z0-9_-]+$", var.additional_data_volume_config.mount_point))
    error_message = "Mount point must be an absolute path starting with / and containing only lowercase letters, numbers, underscores, and hyphens."
  }
}

variable "data_volume_snapshot_config" {
  description = "Configuration for automated EBS snapshots of the additional data volume using AWS Data Lifecycle Manager (DLM)"
  type = object({
    enabled           = bool
    schedule_name     = string
    schedule_interval = number
    schedule_times    = list(string)
    retention_count   = number
    copy_tags         = bool
  })
  default = {
    enabled           = false
    schedule_name     = "daily-snapshots"
    schedule_interval = 24
    schedule_times    = ["03:00"]
    retention_count   = 7
    copy_tags         = true
  }

  validation {
    condition     = var.data_volume_snapshot_config.schedule_interval >= 1 && var.data_volume_snapshot_config.schedule_interval <= 24
    error_message = "Schedule interval must be between 1 and 24 hours."
  }

  validation {
    condition     = var.data_volume_snapshot_config.retention_count >= 1 && var.data_volume_snapshot_config.retention_count <= 1000
    error_message = "Retention count must be between 1 and 1000 snapshots."
  }

  validation {
    condition = alltrue([
      for time in var.data_volume_snapshot_config.schedule_times :
      can(regex("^([01][0-9]|2[0-3]):[0-5][0-9]$", time))
    ])
    error_message = "Schedule times must be in HH:MM format (24-hour), e.g., ['03:00', '15:30']."
  }

  validation {
    condition     = length(var.data_volume_snapshot_config.schedule_times) >= 1 && length(var.data_volume_snapshot_config.schedule_times) <= 3
    error_message = "Must specify between 1 and 3 schedule times per day."
  }
}

variable "asg_config" {
  description = "Configuration object for autoscaling group settings"
  type = object({
    min_size         = number
    max_size         = number
    desired_capacity = number
  })
  default = {
    min_size         = 0
    max_size         = 1
    desired_capacity = 1
  }

  validation {
    condition     = var.asg_config.min_size >= 0
    error_message = "ASG minimum size must be 0 or greater."
  }

  validation {
    condition     = var.asg_config.max_size >= var.asg_config.min_size
    error_message = "ASG maximum size must be greater than or equal to minimum size."
  }

  validation {
    condition     = var.asg_config.desired_capacity >= var.asg_config.min_size && var.asg_config.desired_capacity <= var.asg_config.max_size
    error_message = "ASG desired capacity must be between minimum and maximum size."
  }
}

variable "schedule_config" {
  description = "Configuration object for autoscaling schedules"
  type = object({
    enabled             = bool
    timezone            = string
    scale_down_schedule = string
    scale_up_schedule   = string
  })
  default = {
    enabled             = false
    timezone            = "UTC"
    scale_down_schedule = "0 18 * * MON-FRI"
    scale_up_schedule   = "0 8 * * MON-FRI"
  }
}

# ----
# Encryption
# ----

variable "encryption_config" {
  description = "Configuration object for encryption settings and KMS key management"
  type = object({
    create_kms_key               = bool
    kms_key_id                   = string
    kms_key_deletion_window_days = number
  })
  default = {
    create_kms_key               = true
    kms_key_id                   = ""
    kms_key_deletion_window_days = 14
  }

  validation {
    condition = (
      (var.encryption_config.create_kms_key && var.encryption_config.kms_key_id == "") ||
      (!var.encryption_config.create_kms_key && var.encryption_config.kms_key_id != "")
    )
    error_message = "kms_key_id must be empty when create_kms_key is true, or provided when create_kms_key is false."
  }

  validation {
    condition     = var.encryption_config.kms_key_deletion_window_days >= 7 && var.encryption_config.kms_key_deletion_window_days <= 30
    error_message = "KMS key deletion window must be between 7 and 30 days when specified."
  }
}

# ----
# Monitoring
# ----

variable "monitoring_config" {
  description = "Configuration object for optional monitoring"
  type = object({
    enabled = bool
  })
  default = {
    enabled = false
  }
}

variable "alarms_config" {
  description = "Configuration object for metric alarms and notifications"
  type = object({
    enabled          = bool
    create_sns_topic = bool
    sns_topic_arn    = string
  })
  default = {
    enabled          = false
    create_sns_topic = true
    sns_topic_arn    = ""
  }

  validation {
    condition = (
      (var.alarms_config.create_sns_topic && var.alarms_config.sns_topic_arn == "") ||
      (!var.alarms_config.create_sns_topic && var.alarms_config.sns_topic_arn != "")
    )
    error_message = "sns_topic_arn must be empty when create_sns_topic is true, or provided when create_sns_topic is false."
  }
}

# ----
# Cost Estimation
# ----

variable "cost_estimation_config" {
  description = "Configuration object for monthly cost estimation"
  type = object({
    enabled = bool
  })
  default = {
    enabled = true
  }
}
