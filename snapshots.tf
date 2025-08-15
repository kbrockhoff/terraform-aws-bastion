# ----
# Data Lifecycle Manager for EBS Snapshots
# ----

# IAM role for DLM service
resource "aws_iam_role" "dlm_lifecycle_role" {
  count = var.enabled && var.additional_data_volume_config.enabled && var.data_volume_snapshot_config.enabled ? 1 : 0

  name = "${var.name_prefix}-dlm-lifecycle-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Action = "sts:AssumeRole"
        Effect = "Allow"
        Principal = {
          Service = "dlm.amazonaws.com"
        }
      }
    ]
  })

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-dlm-lifecycle-role"
  })
}

# IAM policy for DLM service
resource "aws_iam_role_policy" "dlm_lifecycle_policy" {
  count = var.enabled && var.additional_data_volume_config.enabled && var.data_volume_snapshot_config.enabled ? 1 : 0

  name = "${var.name_prefix}-dlm-lifecycle-policy"
  role = aws_iam_role.dlm_lifecycle_role[0].id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:CreateSnapshot",
          "ec2:CreateTags",
          "ec2:DeleteSnapshot",
          "ec2:DescribeInstances",
          "ec2:DescribeSnapshots",
          "ec2:DescribeVolumes",
          "ec2:ModifySnapshotAttribute"
        ]
        Resource = "*"
      }
    ]
  })
}

# DLM lifecycle policy for data volume snapshots
resource "aws_dlm_lifecycle_policy" "data_volume_snapshots" {
  count = var.enabled && var.additional_data_volume_config.enabled && var.data_volume_snapshot_config.enabled ? 1 : 0

  description        = "DLM lifecycle policy for ${var.name_prefix} bastion data volume snapshots"
  execution_role_arn = aws_iam_role.dlm_lifecycle_role[0].arn
  state              = "ENABLED"

  policy_details {
    resource_types = ["VOLUME"]
    target_tags = {
      "DLMSnapshot" = "true"
      "Module"      = "kbrockhoff/bastion/aws"
      "Name"        = "${var.name_prefix}-data-volume"
    }

    schedule {
      name      = var.data_volume_snapshot_config.schedule_name
      copy_tags = var.data_volume_snapshot_config.copy_tags
      tags_to_add = merge(local.common_data_tags, {
        SnapshotType = "automated"
        Schedule     = var.data_volume_snapshot_config.schedule_name
      })

      create_rule {
        interval      = var.data_volume_snapshot_config.schedule_interval
        interval_unit = "HOURS"
        times         = var.data_volume_snapshot_config.schedule_times
      }

      retain_rule {
        count = var.data_volume_snapshot_config.retention_count
      }
    }
  }

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-dlm-lifecycle-policy"
  })
}