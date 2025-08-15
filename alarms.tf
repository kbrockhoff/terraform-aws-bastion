# CloudWatch Alarms for ASG Monitoring
locals {
  create_alarms = var.enabled && local.effective_config.alarms_enabled
  alarm_actions = local.create_alarms ? (
    var.alarms_config.create_sns_topic ? [aws_sns_topic.alarms[0].arn] : [var.alarms_config.sns_topic_arn]
  ) : []
}

# SNS Topic for alarm notifications (only created if no external topic provided)
resource "aws_sns_topic" "alarms" {
  count = local.create_sns_topic ? 1 : 0

  name              = "${var.name_prefix}-alarms"
  kms_master_key_id = local.kms_key_id

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-alarms"
  })
}

# SNS Topic Policy
resource "aws_sns_topic_policy" "alarms" {
  count = local.create_sns_topic ? 1 : 0

  arn = aws_sns_topic.alarms[0].arn

  policy = jsonencode({
    Version = "2012-10-17"
    Id      = "AlarmTopicPolicy"
    Statement = [
      {
        Sid    = "AllowCloudWatchToPublish"
        Effect = "Allow"
        Principal = {
          Service = "cloudwatch.amazonaws.com"
        }
        Action = [
          "SNS:Publish"
        ]
        Resource = aws_sns_topic.alarms[0].arn
      }
    ]
  })
}

# ----
# Instance Health Alarms
# ----

# Alarm for unhealthy instances
resource "aws_cloudwatch_metric_alarm" "unhealthy_instances" {
  count = local.create_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-asg-unhealthy-instances"
  alarm_description   = "Triggers when ASG has unhealthy instances"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GroupUnhealthyInstances"
  namespace           = "AWS/AutoScaling"
  period              = 300
  statistic           = "Average"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.bastion[0].name
  }

  tags = local.common_tags
}

# Alarm for instances failing to launch
resource "aws_cloudwatch_metric_alarm" "failed_launches" {
  count = local.create_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-asg-failed-launches"
  alarm_description   = "Triggers when instances fail to launch"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedInstanceLaunches"
  namespace           = "AWS/AutoScaling"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.bastion[0].name
  }

  tags = local.common_tags
}

# ----
# Capacity Alarms
# ----

# Alarm when desired capacity cannot be met
resource "aws_cloudwatch_metric_alarm" "capacity_not_met" {
  count = local.create_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-asg-capacity-not-met"
  alarm_description   = "Triggers when actual capacity is below desired for extended period"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 3
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions

  metric_query {
    id          = "actual"
    return_data = false

    metric {
      metric_name = "GroupInServiceInstances"
      namespace   = "AWS/AutoScaling"
      period      = 300
      stat        = "Average"

      dimensions = {
        AutoScalingGroupName = aws_autoscaling_group.bastion[0].name
      }
    }
  }

  metric_query {
    id          = "desired"
    return_data = false

    metric {
      metric_name = "GroupDesiredCapacity"
      namespace   = "AWS/AutoScaling"
      period      = 300
      stat        = "Average"

      dimensions = {
        AutoScalingGroupName = aws_autoscaling_group.bastion[0].name
      }
    }
  }

  metric_query {
    id          = "capacity_diff"
    expression  = "IF(desired > 0 AND actual < desired, 1, 0)"
    label       = "Capacity Achievement Percentage"
    return_data = true
  }

  tags = local.common_tags
}

# Alarm for when ASG is at maximum capacity
resource "aws_cloudwatch_metric_alarm" "at_max_capacity" {
  count = local.create_alarms && local.effective_config.asg_max_size > 1 ? 1 : 0

  alarm_name          = "${var.name_prefix}-asg-at-max-capacity"
  alarm_description   = "Triggers when ASG is at maximum capacity for extended period"
  comparison_operator = "GreaterThanOrEqualToThreshold"
  evaluation_periods  = 2
  metric_name         = "GroupInServiceInstances"
  namespace           = "AWS/AutoScaling"
  period              = 300
  statistic           = "Average"
  threshold           = local.effective_config.asg_max_size
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.bastion[0].name
  }

  tags = local.common_tags
}

# Alarm for when ASG has no running instances (unexpected)
resource "aws_cloudwatch_metric_alarm" "no_instances_running" {
  count = local.create_alarms && local.effective_config.asg_min_size > 0 ? 1 : 0

  alarm_name          = "${var.name_prefix}-asg-no-instances"
  alarm_description   = "Triggers when no instances are running when they should be"
  comparison_operator = "LessThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GroupInServiceInstances"
  namespace           = "AWS/AutoScaling"
  period              = 300
  statistic           = "Average"
  threshold           = 1
  treat_missing_data  = "breaching"
  alarm_actions       = local.alarm_actions

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.bastion[0].name
  }

  tags = local.common_tags
}

# ----
# Termination Alarms
# ----

# Alarm for instance termination failures
resource "aws_cloudwatch_metric_alarm" "termination_failures" {
  count = local.create_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-asg-termination-failures"
  alarm_description   = "Triggers when instances fail to terminate properly"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  metric_name         = "FailedInstanceTerminations"
  namespace           = "AWS/AutoScaling"
  period              = 300
  statistic           = "Sum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.bastion[0].name
  }

  tags = local.common_tags
}

# Alarm for instances pending termination too long
resource "aws_cloudwatch_metric_alarm" "pending_termination_too_long" {
  count = local.create_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-asg-stuck-terminating"
  alarm_description   = "Triggers when instances are stuck in terminating state"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "GroupTerminatingInstances"
  namespace           = "AWS/AutoScaling"
  period              = 600
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.bastion[0].name
  }

  tags = local.common_tags
}

# ----
# Scaling Activity Alarms
# ----

# Alarm for excessive scaling activities
resource "aws_cloudwatch_metric_alarm" "excessive_scaling" {
  count = local.create_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-asg-excessive-scaling"
  alarm_description   = "Triggers when there are too many scaling activities (possible flapping)"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 1
  threshold           = 10
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions

  metric_query {
    id = "launches"

    metric {
      metric_name = "SuccessfulInstanceLaunches"
      namespace   = "AWS/AutoScaling"
      period      = 900
      stat        = "Sum"

      dimensions = {
        AutoScalingGroupName = aws_autoscaling_group.bastion[0].name
      }
    }
  }

  metric_query {
    id = "terminations"

    metric {
      metric_name = "SuccessfulInstanceTerminations"
      namespace   = "AWS/AutoScaling"
      period      = 900
      stat        = "Sum"

      dimensions = {
        AutoScalingGroupName = aws_autoscaling_group.bastion[0].name
      }
    }
  }

  metric_query {
    id          = "total_activities"
    expression  = "SUM([launches, terminations])"
    label       = "Total Scaling Activities"
    return_data = true
  }

  tags = local.common_tags
}

# ----
# Instance Performance Alarms
# ----

# Alarm for high CPU utilization across the ASG
resource "aws_cloudwatch_metric_alarm" "high_cpu" {
  count = local.create_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-asg-high-cpu"
  alarm_description   = "Triggers when average CPU utilization is too high across ASG"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "CPUUtilization"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Average"
  threshold           = 80
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.bastion[0].name
  }

  tags = local.common_tags
}

# Alarm for status check failures
resource "aws_cloudwatch_metric_alarm" "status_check_failed" {
  count = local.create_alarms ? 1 : 0

  alarm_name          = "${var.name_prefix}-asg-status-check-failed"
  alarm_description   = "Triggers when EC2 status checks fail"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = 2
  metric_name         = "StatusCheckFailed"
  namespace           = "AWS/EC2"
  period              = 300
  statistic           = "Maximum"
  threshold           = 0
  treat_missing_data  = "notBreaching"
  alarm_actions       = local.alarm_actions

  dimensions = {
    AutoScalingGroupName = aws_autoscaling_group.bastion[0].name
  }

  tags = local.common_tags
}

