resource "aws_kms_key" "bastion" {
  count = var.enabled && var.encryption_config.create_kms_key ? 1 : 0

  description             = "Customer-managed key for ${var.name_prefix} module encryption"
  deletion_window_in_days = local.effective_config.kms_key_deletion_window_days
  enable_key_rotation     = true

  policy = data.aws_iam_policy_document.kms_key_policy[0].json

  tags = merge(local.common_data_tags, {
    Name = "${var.name_prefix}-cmk"
  })
}

# KMS Key Alias for easier reference
resource "aws_kms_alias" "bastion" {
  count = var.enabled && var.encryption_config.create_kms_key ? 1 : 0

  name          = "alias/${var.name_prefix}-cmk"
  target_key_id = aws_kms_key.bastion[0].key_id
}

# KMS Key Policy - allows account root and SNS service access
data "aws_iam_policy_document" "kms_key_policy" {
  count = var.enabled && var.encryption_config.create_kms_key ? 1 : 0

  # Allow account root full access to the key
  statement {
    sid    = "EnableRootAccess"
    effect = "Allow"
    principals {
      type        = "AWS"
      identifiers = ["arn:${local.partition}:iam::${local.account_id}:root"]
    }
    actions   = ["kms:*"]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "aws:PrincipalAccount"
      values   = [local.account_id]
    }
  }

  # Allow SNS service to use the key
  statement {
    sid    = "AllowSNSAccess"
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["sns.${local.dns_suffix}"]
    }
    actions = [
      "kms:Decrypt",
      "kms:DescribeKey",
      "kms:Encrypt",
      "kms:GenerateDataKey*",
      "kms:ReEncrypt*"
    ]
    resources = ["*"]
    condition {
      test     = "Bool"
      variable = "kms:GrantIsForAWSResource"
      values   = [true]
    }
  }

  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ssm.${local.region}.${local.dns_suffix}"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ssm.${local.region}.${local.dns_suffix}"]
    }
  }

  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["logs.${local.region}.${local.dns_suffix}"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:DescribeKey"
    ]
    resources = ["*"]
    condition {
      test     = "ArnEquals"
      variable = "kms:EncryptionContext:aws:logs:arn"
      values   = ["arn:${local.partition}:logs:${local.region}:${local.account_id}:*"]
    }
  }

  statement {
    effect = "Allow"
    principals {
      type        = "Service"
      identifiers = ["ec2.${local.region}.${local.dns_suffix}"]
    }
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncrypt*",
      "kms:GenerateDataKey*",
      "kms:GenerateDataKeyWithoutPlaintext",
      "kms:DescribeKey",
      "kms:CreateGrant"
    ]
    resources = ["*"]
    condition {
      test     = "StringEquals"
      variable = "kms:ViaService"
      values   = ["ec2.${local.region}.${local.dns_suffix}"]
    }
  }
}
