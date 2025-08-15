# ----
# KMS Pricing Data
# ----

# KMS pricing
data "aws_pricing_product" "kms" {
  count = local.pricing_enabled ? 1 : 0

  service_code = "AWSKMS"

  filters {
    field = "productFamily"
    value = "Encryption Key"
  }

  filters {
    field = "usagetype"
    value = "${var.region}-KMS-Keys"
  }
}

# ----
# CloudWatch Pricing Data
# ----

# CloudWatch standard metrics
data "aws_pricing_product" "cloudwatch_metrics" {
  count = local.pricing_enabled ? 1 : 0

  service_code = "AmazonCloudWatch"

  filters {
    field = "productFamily"
    value = "Metric"
  }

  filters {
    field = "usagetype"
    value = "${local.usagetype_region}-CW:MetricsUsage"
  }

  filters {
    field = "location"
    value = local.pricing_location
  }
}

# CloudWatch alarms
data "aws_pricing_product" "cloudwatch_alarms" {
  count = local.pricing_enabled ? 1 : 0

  service_code = "AmazonCloudWatch"

  filters {
    field = "productFamily"
    value = "Alarm"
  }

  filters {
    field = "usagetype"
    value = "CW:AlarmMonitorUsage"
  }

  filters {
    field = "location"
    value = local.pricing_location
  }
}

# ----
# SNS Pricing Data
# ----

# SNS topics pricing
data "aws_pricing_product" "sns_requests" {
  count = local.pricing_enabled ? 1 : 0

  service_code = "AmazonSNS"

  filters {
    field = "productFamily"
    value = "API Request"
  }

  filters {
    field = "location"
    value = local.pricing_location
  }
}

# ----
# EC2 Pricing Data
# ----

# EC2 instance pricing
data "aws_pricing_product" "ec2_instance" {
  count = local.pricing_enabled && var.ec2_instance_count > 0 ? 1 : 0

  service_code = "AmazonEC2"

  filters {
    field = "productFamily"
    value = "Compute Instance"
  }

  filters {
    field = "instanceType"
    value = var.ec2_instance_type
  }

  filters {
    field = "location"
    value = local.pricing_location
  }

  filters {
    field = "tenancy"
    value = "Shared"
  }

  filters {
    field = "operatingSystem"
    value = "Linux"
  }

  filters {
    field = "preInstalledSw"
    value = "NA"
  }

  filters {
    field = "capacitystatus"
    value = "Used"
  }
}

# ----
# EBS Pricing Data
# ----

# EBS volume pricing
data "aws_pricing_product" "ebs_volume" {
  count = local.pricing_enabled && var.ebs_volume_count > 0 ? 1 : 0

  service_code = "AmazonEC2"

  filters {
    field = "productFamily"
    value = "Storage"
  }

  filters {
    field = "usagetype"
    value = "EBS:VolumeUsage.${var.ebs_volume_type}"
  }

  filters {
    field = "location"
    value = local.pricing_location
  }
}
