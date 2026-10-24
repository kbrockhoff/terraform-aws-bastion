locals {
  # Short name of the parent module (repository name without the "terraform-aws-" prefix),
  # used to make deployer policy names unique per module, e.g. "vpc" or "s3backend"
  module_short_name = "xxx"

  policy_name_prefix = "${var.name_prefix}-${local.module_short_name}-deployer"

  # Static keys so for_each is known at plan time; one entry per policy document.
  # Split permissions into additional documents (e.g. network, iam) when one would
  # exceed the 6,144 character managed policy size limit.
  policy_documents = var.enabled ? {
    main = data.aws_iam_policy_document.main[0].json
  } : {}

  attach_to_role = var.enabled && var.iam_role_name != ""
}
