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

# Custom metrics (CW:MetricMonitorUsage), which is how EC2 detailed monitoring is billed;
# not Container Insights metric storage (CW:MetricsUsage)
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

# Standard resolution metric alarms, priced per alarm metric
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

# On-demand Linux/UNIX instance hours (BoxUsage), shared tenancy, no pre-installed software
data "aws_pricing_product" "ec2_instances" {
  count = local.pricing_enabled ? 1 : 0

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

  filters {
    field = "operation"
    value = "RunInstances"
  }

  filters {
    field = "regionCode"
    value = var.region
  }
}

# EBS storage of the root volumes (EBS:VolumeUsage.<type>, per GB-month)
data "aws_pricing_product" "ebs_root_volumes" {
  count = local.pricing_enabled ? 1 : 0

  service_code = "AmazonEC2"

  filters {
    field = "productFamily"
    value = "Storage"
  }

  filters {
    field = "volumeApiName"
    value = var.ebs_root_volume_type
  }

  filters {
    field = "regionCode"
    value = var.region
  }
}

# EBS storage of the additional data volumes (EBS:VolumeUsage.<type>, per GB-month)
data "aws_pricing_product" "ebs_data_volumes" {
  count = local.pricing_enabled ? 1 : 0

  service_code = "AmazonEC2"

  filters {
    field = "productFamily"
    value = "Storage"
  }

  filters {
    field = "volumeApiName"
    value = var.ebs_data_volume_type
  }

  filters {
    field = "regionCode"
    value = var.region
  }
}
