locals {
  # Environment type defaults
  environment_defaults = {
    None = {
      rpo_hours                    = null
      rto_hours                    = null
      monitoring_enabled           = var.monitoring_config.enabled
      alarms_enabled               = var.alarms_config.enabled
      kms_key_deletion_window_days = var.encryption_config.kms_key_deletion_window_days
      enable_schedule              = var.schedule_config.enabled
      asg_min_size                 = var.asg_config.min_size
      asg_max_size                 = var.asg_config.max_size
    }
    Ephemeral = {
      rpo_hours                    = null
      rto_hours                    = 48
      monitoring_enabled           = false
      alarms_enabled               = false
      kms_key_deletion_window_days = 7 # Minimal window for ephemeral environments
      enable_schedule              = true
      asg_min_size                 = 0
      asg_max_size                 = 1
    }
    Development = {
      rpo_hours                    = 24
      rto_hours                    = 48
      monitoring_enabled           = false
      alarms_enabled               = false
      kms_key_deletion_window_days = 7 # Short window for development
      enable_schedule              = true
      asg_min_size                 = 0
      asg_max_size                 = 1
    }
    Testing = {
      rpo_hours                    = 24
      rto_hours                    = 48
      monitoring_enabled           = false
      alarms_enabled               = false
      kms_key_deletion_window_days = 14 # Medium window for testing
      enable_schedule              = true
      asg_min_size                 = 0
      asg_max_size                 = 1
    }
    UAT = {
      rpo_hours                    = 12
      rto_hours                    = 24
      monitoring_enabled           = false
      alarms_enabled               = false
      kms_key_deletion_window_days = 14 # Medium window for UAT
      enable_schedule              = true
      asg_min_size                 = 0
      asg_max_size                 = 2
    }
    Production = {
      rpo_hours                    = 1
      rto_hours                    = 4
      monitoring_enabled           = true
      alarms_enabled               = true
      kms_key_deletion_window_days = 30 # Maximum window for production
      enable_schedule              = false
      asg_min_size                 = 1
      asg_max_size                 = 3
    }
    MissionCritical = {
      rpo_hours                    = 0.083 # 5 minutes
      rto_hours                    = 1
      monitoring_enabled           = true
      alarms_enabled               = true
      kms_key_deletion_window_days = 30 # Maximum window for mission critical
      enable_schedule              = false
      asg_min_size                 = 2
      asg_max_size                 = 5
    }
  }

  # Apply environment defaults when environment_type is not "None"
  effective_config = var.environment_type == "None" ? (
    local.environment_defaults.None
    ) : (
    local.environment_defaults[var.environment_type]
  )

  # AWS account, partition, and region info
  account_id = data.aws_caller_identity.current.account_id
  partition  = data.aws_partition.current.partition
  region     = data.aws_region.current.region
  dns_suffix = data.aws_partition.current.dns_suffix

  # Common tags for all resources including module metadata
  common_tags = merge(var.tags, {
    ModuleName    = "kbrockhoff/bastion/aws"
    ModuleVersion = local.module_version
    ModuleEnvType = var.environment_type
  })
  # Data tags take precedence over common tags
  common_data_tags = merge(local.common_tags, var.data_tags)

  instance_name       = var.name_prefix
  role_name           = "${var.name_prefix}-inst"
  ebs_name            = "${var.name_prefix}-ebs"
  kms_iam_policy_name = "${var.name_prefix}-kmsusage"
  ebs_volume_type     = "gp3"

  lookup_subnet = var.enabled
  subnet_ids    = local.lookup_subnet ? data.aws_subnets.bastion[0].ids : []

  security_group_ids = var.enabled ? (
    var.use_standard_security_group ? [data.aws_security_group.bastion[0].id] : var.security_group_ids
  ) : []

  create_iam_resources = var.enabled && var.iam_instance_profile_name == null
  iam_policies = local.create_iam_resources ? concat([
    "arn:aws:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:aws:iam::aws:policy/AmazonSSMPatchAssociation",
  ], var.additional_iam_policies) : []
  iam_instance_profile_name = local.create_iam_resources ? (
    aws_iam_instance_profile.bastion[0].name
  ) : var.iam_instance_profile_name

  userdata_b64 = base64encode(templatefile("${path.module}/${var.user_data_template}", {
    user_data = join("\n", var.user_data)
  }))

  # KMS key logic - use provided key ID or create new one
  kms_key_id = var.enabled ? (
    var.encryption_config.create_kms_key ? aws_kms_key.bastion[0].arn : var.encryption_config.kms_key_id
  ) : ""

  # SNS topic logic - use provided topic ARN or create new one
  create_sns_topic = var.enabled && local.effective_config.alarms_enabled && var.alarms_config.create_sns_topic
  alarm_sns_topic_arn = var.enabled && local.effective_config.alarms_enabled ? (
    var.alarms_config.create_sns_topic ? aws_sns_topic.alarms[0].arn : var.alarms_config.sns_topic_arn
  ) : ""

  # CloudWatch alarm counts for pricing calculations
  # Total alarms: 10 (but some are conditional based on ASG configuration)
  # - 8 alarms always created when alarms enabled
  # - 1 alarm only if asg_max_size > 1 (at_max_capacity)
  # - 1 alarm only if asg_min_size > 0 (no_instances_running)
  actual_alarm_count = local.create_alarms ? (
    8 +
    (local.effective_config.asg_max_size > 1 ? 1 : 0) +
    (local.effective_config.asg_min_size > 0 ? 1 : 0)
  ) : 0

  # Parse cron schedules to extract hour values
  # Format: "minute hour * * day-of-week"
  # Example: "0 8 * * MON-FRI" = 8 AM, "0 18 * * MON-FRI" = 6 PM
  scale_up_hour = local.effective_config.enable_schedule ? (
    tonumber(split(" ", var.schedule_config.scale_up_schedule)[1])
  ) : 0

  scale_down_hour = local.effective_config.enable_schedule ? (
    tonumber(split(" ", var.schedule_config.scale_down_schedule)[1])
  ) : 24

  # Calculate daily hours of operation
  daily_hours = local.effective_config.enable_schedule ? (
    local.scale_down_hour - local.scale_up_hour
  ) : 24

  # Parse day-of-week from cron schedule to determine weekly days
  # "MON-FRI" = 5 days, "MON-SUN" or "*" = 7 days
  schedule_days = local.effective_config.enable_schedule ? (
    contains(["MON-FRI", "1-5"], try(split(" ", var.schedule_config.scale_up_schedule)[4], "*")) ? 5 : 7
  ) : 7

  # Calculate monthly hours based on actual schedule configuration
  # hours_per_week = daily_hours * schedule_days
  # weeks_per_month = 365.25 days/year / 12 months / 7 days/week = 4.345
  # monthly_hours = hours_per_week * weeks_per_month
  monthly_hours = local.daily_hours * local.schedule_days * (365.25 / 12 / 7)

}
