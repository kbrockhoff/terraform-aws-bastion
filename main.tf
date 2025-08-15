resource "aws_launch_template" "bastion" {
  count = var.enabled ? 1 : 0

  name_prefix   = "${var.name_prefix}-"
  image_id      = data.aws_ami.default.id
  instance_type = var.instance_type
  user_data     = length(var.user_data_base64) > 0 ? var.user_data_base64 : local.userdata_b64

  vpc_security_group_ids = local.security_group_ids

  iam_instance_profile {
    name = local.iam_instance_profile_name
  }

  block_device_mappings {
    device_name = "/dev/xvda"
    ebs {
      volume_size = var.root_block_device_volume_size
      volume_type = local.ebs_volume_type
      encrypted   = true
      kms_key_id  = local.kms_key_id
    }
  }

  dynamic "block_device_mappings" {
    for_each = var.additional_data_volume_config.enabled ? [1] : []
    content {
      device_name = "/dev/xvdf"
      ebs {
        volume_size           = var.additional_data_volume_config.size
        volume_type           = var.additional_data_volume_config.type
        iops                  = var.additional_data_volume_config.type == "gp3" || var.additional_data_volume_config.type == "io1" || var.additional_data_volume_config.type == "io2" ? var.additional_data_volume_config.iops : null
        throughput            = var.additional_data_volume_config.type == "gp3" ? var.additional_data_volume_config.throughput : null
        encrypted             = true
        kms_key_id            = local.kms_key_id
        delete_on_termination = true
      }
    }
  }

  metadata_options {
    http_endpoint               = "enabled"
    http_tokens                 = "required"
    http_put_response_hop_limit = 1
  }

  monitoring {
    enabled = var.monitoring_config.enabled
  }

  tag_specifications {
    resource_type = "instance"
    tags = merge(local.common_tags, {
      Name = local.instance_name
    })
  }

  tag_specifications {
    resource_type = "volume"
    tags = merge(local.common_data_tags, {
      Name = local.ebs_name
    })
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-launch-template"
  })
}

resource "aws_autoscaling_group" "bastion" {
  count = var.enabled ? 1 : 0

  name                      = "${var.name_prefix}-asg"
  vpc_zone_identifier       = local.subnet_ids
  target_group_arns         = []
  health_check_type         = "EC2"
  health_check_grace_period = 300

  min_size         = local.effective_config.asg_min_size
  max_size         = local.effective_config.asg_max_size
  desired_capacity = var.asg_config.desired_capacity

  launch_template {
    id      = aws_launch_template.bastion[0].id
    version = "$Latest"
  }

  instance_refresh {
    strategy = "Rolling"
    preferences {
      min_healthy_percentage = 50
    }
  }

  tag {
    key                 = "Name"
    value               = local.instance_name
    propagate_at_launch = true
  }

  dynamic "tag" {
    for_each = local.common_tags
    content {
      key                 = tag.key
      value               = tag.value
      propagate_at_launch = true
    }
  }
}

resource "aws_autoscaling_schedule" "scale_down" {
  count = var.enabled && local.effective_config.enable_schedule ? 1 : 0

  scheduled_action_name  = "${var.name_prefix}-scale-down"
  min_size               = 0
  max_size               = local.effective_config.asg_max_size
  desired_capacity       = 0
  recurrence             = var.schedule_config.scale_down_schedule
  time_zone              = var.schedule_config.timezone
  autoscaling_group_name = aws_autoscaling_group.bastion[0].name
}

resource "aws_autoscaling_schedule" "scale_up" {
  count = var.enabled && local.effective_config.enable_schedule ? 1 : 0

  scheduled_action_name  = "${var.name_prefix}-scale-up"
  min_size               = local.effective_config.asg_min_size
  max_size               = local.effective_config.asg_max_size
  desired_capacity       = var.asg_config.desired_capacity
  recurrence             = var.schedule_config.scale_up_schedule
  time_zone              = var.schedule_config.timezone
  autoscaling_group_name = aws_autoscaling_group.bastion[0].name
}
