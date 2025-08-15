# Main AWS provider - uses the current region
provider "aws" {
  # This is the default provider used for VPC resources
}

# Pricing provider - always uses us-east-1 where the AWS Pricing API is available
provider "aws" {
  alias  = "pricing"
  region = "us-east-1"
}

module "main" {
  source = "../../"

  providers = {
    aws         = aws
    aws.pricing = aws.pricing
  }

  enabled                       = var.enabled
  name_prefix                   = var.name_prefix
  tags                          = var.tags
  data_tags                     = var.data_tags
  environment_type              = var.environment_type
  cost_estimation_config        = var.cost_estimation_config
  networktags_name              = var.networktags_name
  networktags_value_vpc         = var.networktags_value_vpc
  networktags_value_subnets     = var.networktags_value_subnets
  use_standard_security_group   = var.use_standard_security_group
  security_group_ids            = var.security_group_ids
  instance_type                 = var.instance_type
  iam_instance_profile_name     = var.iam_instance_profile_name
  additional_iam_policies       = var.additional_iam_policies
  ami_filter                    = var.ami_filter
  ami_owners                    = var.ami_owners
  user_data_template            = var.user_data_template
  user_data                     = var.user_data
  user_data_base64              = var.user_data_base64
  ssh_user                      = var.ssh_user
  root_block_device_volume_size = var.root_block_device_volume_size
  asg_config                    = var.asg_config
  schedule_config               = var.schedule_config
  encryption_config             = var.encryption_config
  monitoring_config             = var.monitoring_config
  alarms_config                 = var.alarms_config
}
