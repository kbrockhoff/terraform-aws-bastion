# ----
# Data Lifecycle Manager for EBS Snapshots
# ----

# IAM assume role policy document for DLM service
data "aws_iam_policy_document" "dlm_assume_role_policy" {
  count = var.enabled && var.additional_data_volume_config.enabled && var.data_volume_snapshot_config.enabled ? 1 : 0

  statement {
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["dlm.${local.dns_suffix}"]
    }

    actions = ["sts:AssumeRole"]
  }
}

# IAM policy document for DLM service permissions
data "aws_iam_policy_document" "dlm_lifecycle_policy" {
  count = var.enabled && var.additional_data_volume_config.enabled && var.data_volume_snapshot_config.enabled ? 1 : 0

  # Allow snapshot creation and tagging on volumes
  statement {
    effect = "Allow"

    actions = [
      "ec2:CreateSnapshot",
      "ec2:CreateTags"
    ]

    resources = [
      "arn:${local.partition}:ec2:${local.region}:${local.account_id}:volume/*",
      "arn:${local.partition}:ec2:${local.region}:${local.account_id}:snapshot/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/DLMSnapshot"
      values   = ["true"]
    }
  }

  # Allow snapshot deletion and modification
  statement {
    effect = "Allow"

    actions = [
      "ec2:DeleteSnapshot",
      "ec2:ModifySnapshotAttribute"
    ]

    resources = [
      "arn:${local.partition}:ec2:${local.region}:${local.account_id}:snapshot/*"
    ]

    condition {
      test     = "StringEquals"
      variable = "ec2:ResourceTag/SnapshotType"
      values   = ["automated"]
    }
  }

  # Allow describe operations (read-only)
  statement {
    effect = "Allow"

    actions = [
      "ec2:DescribeInstances",
      "ec2:DescribeSnapshots",
      "ec2:DescribeVolumes"
    ]

    resources = ["*"]
  }
}

# IAM role for DLM service
resource "aws_iam_role" "dlm_lifecycle_role" {
  count = var.enabled && var.additional_data_volume_config.enabled && var.data_volume_snapshot_config.enabled ? 1 : 0

  name               = "${var.name_prefix}-dlm-lifecycle-role"
  assume_role_policy = data.aws_iam_policy_document.dlm_assume_role_policy[0].json

  tags = merge(local.common_tags, {
    Name = "${var.name_prefix}-dlm-lifecycle-role"
  })
}

# IAM policy for DLM service
resource "aws_iam_role_policy" "dlm_lifecycle_policy" {
  count = var.enabled && var.additional_data_volume_config.enabled && var.data_volume_snapshot_config.enabled ? 1 : 0

  name   = "${var.name_prefix}-dlm-lifecycle-policy"
  role   = aws_iam_role.dlm_lifecycle_role[0].id
  policy = data.aws_iam_policy_document.dlm_lifecycle_policy[0].json
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