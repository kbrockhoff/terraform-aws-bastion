variable "enabled" {
  description = "Set to false to prevent the module from creating any resources."
  type        = bool
  default     = true
}

variable "name_prefix" {
  description = "Organization unique prefix to use for resource names. Must match the name_prefix used when deploying the parent module. e.g. 'prod-usw2'."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{0,22}[a-z0-9]$", var.name_prefix))
    error_message = "The name_prefix value must be between 2 and 24 characters."
  }
}

variable "iam_role_name" {
  description = "Name of an existing IAM role to attach the policies to, typically the role_name output of terraform-aws-cicdrole. Leave empty to only create the policies."
  type        = string
  default     = ""
}

variable "tags" {
  description = "Tags/labels to apply to all resources."
  type        = map(string)
  default     = {}
}

variable "partition" {
  description = "AWS partition"
  type        = string
  default     = "aws"
}

variable "region" {
  description = "AWS region where the parent module is deployed"
  type        = string
}

variable "account_id" {
  description = "AWS account ID where the parent module is deployed"
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.account_id))
    error_message = "The account_id value must be a 12 digit AWS account ID."
  }
}
