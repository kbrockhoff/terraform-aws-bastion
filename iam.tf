data "aws_iam_policy_document" "bastion" {
  count = local.create_iam_resources ? 1 : 0

  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRole"]
    principals {
      type        = "Service"
      identifiers = ["ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "bastion" {
  count = local.create_iam_resources ? 1 : 0

  name               = local.role_name
  assume_role_policy = data.aws_iam_policy_document.bastion[0].json

  tags = merge(local.common_tags, {
    Name = local.role_name
  })
}

resource "aws_iam_instance_profile" "bastion" {
  count = local.create_iam_resources ? 1 : 0

  name = local.role_name
  role = aws_iam_role.bastion[0].name

  tags = merge(local.common_tags, {
    Name = local.role_name
  })
}

data "aws_iam_policy_document" "kms_usage" {
  count = local.create_iam_resources ? 1 : 0

  statement {
    effect = "Allow"
    actions = [
      "kms:Encrypt",
      "kms:Decrypt",
      "kms:ReEncryptFrom",
      "kms:ReEncryptTo",
      "kms:GenerateDataKey*",
      "kms:DescribeKey",
    ]
    resources = [local.kms_key_id]
  }
}

resource "aws_iam_role_policy" "kms_usage" {
  count = local.create_iam_resources ? 1 : 0

  name_prefix = local.kms_iam_policy_name
  role        = aws_iam_role.bastion[0].name
  policy      = data.aws_iam_policy_document.kms_usage[0].json
}

resource "aws_iam_role_policy_attachment" "additional" {
  for_each = toset(local.iam_policies)

  role       = aws_iam_role.bastion[0].name
  policy_arn = each.value
}
