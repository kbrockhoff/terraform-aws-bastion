# ----
# Least privilege permissions to provision and deprovision the parent module's resources.
# Terraform state backend access is granted by terraform-aws-cicdrole, not here.
# ----

locals {
  ec2_arn_prefix = "arn:${var.partition}:ec2:${var.region}:${var.account_id}"
  asg_arn        = "arn:${var.partition}:autoscaling:${var.region}:${var.account_id}:autoScalingGroup:*:autoScalingGroupName/${var.name_prefix}-*"

  # Exact role names created by the parent (iam.tf, snapshots.tf). Not "${var.name_prefix}-*",
  # which would also match the cicdrole role "<name_prefix>-cicd-deployer" these policies attach to.
  instance_role_arn = "arn:${var.partition}:iam::${var.account_id}:role/${var.name_prefix}-inst"
  dlm_role_arn      = "arn:${var.partition}:iam::${var.account_id}:role/${var.name_prefix}-dlm-lifecycle-role"

  # Managed policies the parent always attaches to the instance role, plus caller-supplied extras
  attachable_policy_arns = concat([
    "arn:${var.partition}:iam::aws:policy/AmazonSSMManagedInstanceCore",
    "arn:${var.partition}:iam::aws:policy/AmazonSSMPatchAssociation",
  ], var.additional_iam_policies)
}

data "aws_iam_policy_document" "main" {
  count = var.enabled ? 1 : 0

  # Caller identity lookups used by the parent module's data sources
  statement {
    sid    = "CallerIdentity"
    effect = "Allow"
    actions = [
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }

  # Pricing API access (required for cost estimation)
  statement {
    sid    = "PricingRead"
    effect = "Allow"
    actions = [
      "freetier:GetAccountPlanState",
      "pricing:GetAttributeValues",
      "pricing:GetProducts",
    ]
    resources = ["*"]
  }

  # Data sources (AMI, VPC, subnets, security group) and launch template refresh;
  # none of these support resource-level permissions
  statement {
    sid    = "Ec2Describe"
    effect = "Allow"
    actions = [
      "ec2:DescribeImages",
      "ec2:DescribeLaunchTemplateVersions",
      "ec2:DescribeLaunchTemplates",
      "ec2:DescribeRouteTables",
      "ec2:DescribeSecurityGroups",
      "ec2:DescribeSubnets",
      "ec2:DescribeVpcs",
    ]
    resources = ["*"]
  }

  # aws_vpc data source reads DNS and NAU metric attributes
  statement {
    sid       = "Ec2VpcAttributeRead"
    effect    = "Allow"
    actions   = ["ec2:DescribeVpcAttribute"]
    resources = ["${local.ec2_arn_prefix}:vpc/*"]
  }

  # Launch template IDs are AWS-generated, so creation is gated on the Name tag
  statement {
    sid       = "Ec2LaunchTemplateCreate"
    effect    = "Allow"
    actions   = ["ec2:CreateLaunchTemplate"]
    resources = ["${local.ec2_arn_prefix}:launch-template/*"]

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/Name"
      values   = ["${var.name_prefix}-*"]
    }
  }

  statement {
    sid    = "Ec2LaunchTemplateManagement"
    effect = "Allow"
    actions = [
      "ec2:CreateLaunchTemplateVersion",
      "ec2:CreateTags",
      "ec2:DeleteLaunchTemplate",
      "ec2:DeleteLaunchTemplateVersions",
      "ec2:DeleteTags",
      "ec2:ModifyLaunchTemplate",
    ]
    resources = ["${local.ec2_arn_prefix}:launch-template/*"]

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/Name"
      values   = ["${var.name_prefix}-*"]
    }
  }

  # Auto Scaling validates that the caller could launch from the launch template
  statement {
    sid     = "Ec2RunInstancesFromLaunchTemplate"
    effect  = "Allow"
    actions = ["ec2:RunInstances"]
    resources = [
      "arn:${var.partition}:ec2:${var.region}::image/*",
      "${local.ec2_arn_prefix}:instance/*",
      "${local.ec2_arn_prefix}:launch-template/*",
      "${local.ec2_arn_prefix}:network-interface/*",
      "${local.ec2_arn_prefix}:security-group/*",
      "${local.ec2_arn_prefix}:subnet/*",
      "${local.ec2_arn_prefix}:volume/*",
    ]

    condition {
      test     = "ArnLike"
      variable = "ec2:LaunchTemplate"
      values   = ["${local.ec2_arn_prefix}:launch-template/*"]
    }
  }

  statement {
    sid     = "Ec2TagOnCreate"
    effect  = "Allow"
    actions = ["ec2:CreateTags"]
    resources = [
      "${local.ec2_arn_prefix}:instance/*",
      "${local.ec2_arn_prefix}:launch-template/*",
      "${local.ec2_arn_prefix}:volume/*",
    ]

    condition {
      test     = "StringEquals"
      variable = "ec2:CreateAction"
      values   = ["CreateLaunchTemplate", "RunInstances"]
    }
  }

  statement {
    sid    = "AutoScalingDescribe"
    effect = "Allow"
    actions = [
      "autoscaling:DescribeAutoScalingGroups",
      "autoscaling:DescribeInstanceRefreshes",
      "autoscaling:DescribeScalingActivities",
      "autoscaling:DescribeScheduledActions",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "AutoScalingGroupManagement"
    effect = "Allow"
    actions = [
      "autoscaling:CancelInstanceRefresh",
      "autoscaling:CreateAutoScalingGroup",
      "autoscaling:CreateOrUpdateTags",
      "autoscaling:DeleteAutoScalingGroup",
      "autoscaling:DeleteScheduledAction",
      "autoscaling:DeleteTags",
      "autoscaling:PutScheduledUpdateGroupAction",
      "autoscaling:StartInstanceRefresh",
      "autoscaling:UpdateAutoScalingGroup",
    ]
    resources = [local.asg_arn]
  }

  # Auto Scaling creates its service-linked role on first use in an account
  statement {
    sid       = "AutoScalingServiceLinkedRole"
    effect    = "Allow"
    actions   = ["iam:CreateServiceLinkedRole"]
    resources = ["arn:${var.partition}:iam::${var.account_id}:role/aws-service-role/autoscaling.amazonaws.com/AWSServiceRoleForAutoScaling*"]

    condition {
      test     = "StringEquals"
      variable = "iam:AWSServiceName"
      values   = ["autoscaling.amazonaws.com"]
    }
  }

  # DLM policy IDs are AWS-generated, so creation is gated on the Name tag
  statement {
    sid       = "DlmPolicyCreate"
    effect    = "Allow"
    actions   = ["dlm:CreateLifecyclePolicy"]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/Name"
      values   = ["${var.name_prefix}-*"]
    }
  }

  statement {
    sid    = "DlmPolicyManagement"
    effect = "Allow"
    actions = [
      "dlm:DeleteLifecyclePolicy",
      "dlm:GetLifecyclePolicy",
      "dlm:ListTagsForResource",
      "dlm:TagResource",
      "dlm:UntagResource",
      "dlm:UpdateLifecyclePolicy",
    ]
    resources = ["arn:${var.partition}:dlm:${var.region}:${var.account_id}:policy/*"]

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/Name"
      values   = ["${var.name_prefix}-*"]
    }
  }

  # KMS actions which do not support resource-level permissions
  statement {
    sid    = "KmsGlobal"
    effect = "Allow"
    actions = [
      "kms:ListAliases",
      "kms:ListKeys",
    ]
    resources = ["*"]
  }

  # Key IDs are AWS-generated, so creation and management are gated on the Name tag
  statement {
    sid       = "KmsKeyCreate"
    effect    = "Allow"
    actions   = ["kms:CreateKey"]
    resources = ["*"]

    condition {
      test     = "StringLike"
      variable = "aws:RequestTag/Name"
      values   = ["${var.name_prefix}-*"]
    }
  }

  statement {
    sid    = "KmsKeyManagement"
    effect = "Allow"
    actions = [
      "kms:CancelKeyDeletion",
      "kms:CreateGrant",
      "kms:DescribeKey",
      "kms:DisableKey",
      "kms:DisableKeyRotation",
      "kms:EnableKey",
      "kms:EnableKeyRotation",
      "kms:GetKeyPolicy",
      "kms:GetKeyRotationStatus",
      "kms:ListResourceTags",
      "kms:PutKeyPolicy",
      "kms:ScheduleKeyDeletion",
      "kms:TagResource",
      "kms:UntagResource",
    ]
    resources = [
      "arn:${var.partition}:kms:${var.region}:${var.account_id}:key/*",
    ]

    condition {
      test     = "StringLike"
      variable = "aws:ResourceTag/Name"
      values   = ["${var.name_prefix}-*"]
    }
  }

  # Alias management requires permission on both the alias and the target key
  statement {
    sid    = "KmsAliasManagement"
    effect = "Allow"
    actions = [
      "kms:CreateAlias",
      "kms:DeleteAlias",
      "kms:UpdateAlias",
    ]
    resources = [
      "arn:${var.partition}:kms:${var.region}:${var.account_id}:alias/${var.name_prefix}-*",
      "arn:${var.partition}:kms:${var.region}:${var.account_id}:key/*",
    ]
  }

  statement {
    sid    = "AlarmManagement"
    effect = "Allow"
    actions = [
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:ListTagsForResource",
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
    ]
    resources = [
      "arn:${var.partition}:cloudwatch:${var.region}:${var.account_id}:alarm:${var.name_prefix}-*",
    ]
  }

  # Alarm topic and its topic policy (SetTopicAttributes)
  statement {
    sid    = "TopicManagement"
    effect = "Allow"
    actions = [
      "sns:CreateTopic",
      "sns:DeleteTopic",
      "sns:GetTopicAttributes",
      "sns:ListTagsForResource",
      "sns:SetTopicAttributes",
      "sns:TagResource",
      "sns:UntagResource",
    ]
    resources = [
      "arn:${var.partition}:sns:${var.region}:${var.account_id}:${var.name_prefix}-*",
    ]
  }
}

data "aws_iam_policy_document" "iam" {
  count = var.enabled ? 1 : 0

  # Instance role and DLM execution role, with their inline policies
  statement {
    sid    = "IamRoleManagement"
    effect = "Allow"
    actions = [
      "iam:CreateRole",
      "iam:DeleteRole",
      "iam:DeleteRolePolicy",
      "iam:DetachRolePolicy",
      "iam:GetRole",
      "iam:GetRolePolicy",
      "iam:ListAttachedRolePolicies",
      "iam:ListInstanceProfilesForRole",
      "iam:ListRolePolicies",
      "iam:PutRolePolicy",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateAssumeRolePolicy",
    ]
    resources = [
      local.dlm_role_arn,
      local.instance_role_arn,
    ]
  }

  # Only the managed policies the parent module attaches to the instance role
  statement {
    sid       = "IamRolePolicyAttach"
    effect    = "Allow"
    actions   = ["iam:AttachRolePolicy"]
    resources = [local.instance_role_arn]

    condition {
      test     = "ArnEquals"
      variable = "iam:PolicyARN"
      values   = local.attachable_policy_arns
    }
  }

  statement {
    sid    = "IamInstanceProfileManagement"
    effect = "Allow"
    actions = [
      "iam:AddRoleToInstanceProfile",
      "iam:CreateInstanceProfile",
      "iam:DeleteInstanceProfile",
      "iam:GetInstanceProfile",
      "iam:RemoveRoleFromInstanceProfile",
      "iam:TagInstanceProfile",
      "iam:UntagInstanceProfile",
    ]
    resources = ["arn:${var.partition}:iam::${var.account_id}:instance-profile/${var.name_prefix}-inst"]
  }

  # Instance role via the launch template's instance profile, DLM role via execution_role_arn
  statement {
    sid    = "IamPassRole"
    effect = "Allow"
    actions = [
      "iam:PassRole",
    ]
    resources = [
      local.dlm_role_arn,
      local.instance_role_arn,
    ]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      values   = ["dlm.amazonaws.com", "ec2.amazonaws.com"]
    }
  }
}

resource "aws_iam_policy" "this" {
  for_each = local.policy_documents

  name        = "${local.policy_name_prefix}-${each.key}"
  description = "Least privilege permissions for CI/CD to deploy the ${local.module_short_name} module (${each.key})"
  policy      = each.value

  tags = merge(var.tags, {
    Name = "${local.policy_name_prefix}-${each.key}"
  })
}

# Optional attachment, e.g. to the role created by terraform-aws-cicdrole
resource "aws_iam_role_policy_attachment" "this" {
  for_each = local.attach_to_role ? aws_iam_policy.this : {}

  role       = var.iam_role_name
  policy_arn = each.value.arn
}
