# AWS account, partition, and region data sources
data "aws_caller_identity" "current" {}
data "aws_partition" "current" {}
data "aws_region" "current" {}

data "aws_vpc" "standard" {
  count = local.lookup_subnet ? 1 : 0

  tags = {
    "${var.networktags_name}" = var.networktags_value_vpc
  }
}

data "aws_subnets" "bastion" {
  count = local.lookup_subnet ? 1 : 0

  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.standard[0].id]
  }
  tags = {
    "${var.networktags_name}" = var.networktags_value_subnets
  }
}

data "aws_security_group" "bastion" {
  count = var.enabled && var.use_standard_security_group ? 1 : 0

  vpc_id = data.aws_vpc.standard[0].id
  tags = {
    "${var.networktags_name}" = "private"
  }
}

data "aws_ami" "default" {
  most_recent = "true"
  dynamic "filter" {
    for_each = var.ami_filter
    content {
      name   = filter.key
      values = filter.value
    }
  }
  owners = var.ami_owners
}
