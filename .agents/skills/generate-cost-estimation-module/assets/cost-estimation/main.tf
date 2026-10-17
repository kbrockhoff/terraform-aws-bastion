# ----
# AWS Pricing API lookups
#
# aws_pricing_product fails the plan unless its filters match exactly one product, so each
# lookup filters on regionCode plus attributes that are identical in every region. Validate
# new filters against the Pricing API in every supported region before adding them.
# ----

data "aws_pricing_product" "kms_keys" {
  count = local.pricing_enabled ? 1 : 0

  service_code = "AWSKMS"

  filters {
    field = "productFamily"
    value = "Encryption Key"
  }

  filters {
    field = "regionCode"
    value = var.region
  }
}

# Custom metrics (CW:MetricMonitorUsage), not Container Insights metric storage
data "aws_pricing_product" "cloudwatch_metrics" {
  count = local.pricing_enabled ? 1 : 0

  service_code = "AmazonCloudWatch"

  filters {
    field = "productFamily"
    value = "Metric"
  }

  filters {
    field = "group"
    value = "Metric"
  }

  filters {
    field = "regionCode"
    value = var.region
  }
}

# Standard resolution metric alarms
data "aws_pricing_product" "cloudwatch_alarms" {
  count = local.pricing_enabled ? 1 : 0

  service_code = "AmazonCloudWatch"

  filters {
    field = "productFamily"
    value = "Alarm"
  }

  filters {
    field = "group"
    value = "Alarm"
  }

  filters {
    field = "alarmType"
    value = "Standard"
  }

  filters {
    field = "regionCode"
    value = var.region
  }
}

data "aws_pricing_product" "sns_requests" {
  count = local.pricing_enabled ? 1 : 0

  service_code = "AmazonSNS"

  filters {
    field = "productFamily"
    value = "API Request"
  }

  filters {
    field = "group"
    value = "SNS-Requests-Tier1"
  }

  filters {
    field = "regionCode"
    value = var.region
  }
}
