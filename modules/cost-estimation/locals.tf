# ----
# Cost calculation
# ----

locals {
  # The parent passes a provider pinned to us-east-1, where the Pricing API is available
  pricing_enabled = var.enabled

  # Raw Pricing API results keyed by cost component
  pricing_results = local.pricing_enabled ? {
    kms_keys           = data.aws_pricing_product.kms_keys[0].result
    cloudwatch_metrics = data.aws_pricing_product.cloudwatch_metrics[0].result
    cloudwatch_alarms  = data.aws_pricing_product.cloudwatch_alarms[0].result
    sns_requests       = data.aws_pricing_product.sns_requests[0].result
    ec2_instances      = data.aws_pricing_product.ec2_instances[0].result
    ebs_root_volumes   = data.aws_pricing_product.ebs_root_volumes[0].result
    ebs_data_volumes   = data.aws_pricing_product.ebs_data_volumes[0].result
  } : {}

  # us-east-1 on-demand prices in USD, used only when a result cannot be parsed
  default_unit_prices = {
    kms_keys           = 1.00      # per key-month
    cloudwatch_metrics = 0.30      # per metric-month, first tier
    cloudwatch_alarms  = 0.10      # per standard alarm metric-month
    sns_requests       = 0.0000005 # per request beyond the free tier
    ec2_instances      = 0.0104    # per instance-hour, t3.micro Linux
    ebs_root_volumes   = 0.08      # per GB-month, gp3
    ebs_data_volumes   = 0.08      # per GB-month, gp3
  }

  # Paid price tiers of each product's on-demand offer. $0 free tiers are account-wide,
  # so they are not credited to a single module.
  paid_price_dimensions = {
    for k, r in local.pricing_results : k => try([
      for d in values(values(jsondecode(r).terms.OnDemand)[0].priceDimensions) : d
      if tonumber(d.pricePerUnit.USD) > 0
    ], [])
  }

  # Unit price of the lowest paid tier per component
  unit_prices = {
    for k, default in local.default_unit_prices : k => try([
      for d in local.paid_price_dimensions[k] : tonumber(d.pricePerUnit.USD)
      if tonumber(d.beginRange) == min([for t in local.paid_price_dimensions[k] : tonumber(t.beginRange)]...)
    ][0], default)
  }

  costs = {
    kms_keys           = var.kms_key_count * local.unit_prices.kms_keys
    cloudwatch_metrics = var.cloudwatch_metric_count * local.unit_prices.cloudwatch_metrics
    cloudwatch_alarms  = var.cloudwatch_alarm_count * local.unit_prices.cloudwatch_alarms
    sns_requests       = var.sns_requests_monthly * local.unit_prices.sns_requests
    ec2_instances      = var.ec2_instance_count * var.ec2_monthly_hours * local.unit_prices.ec2_instances
    ebs_root_volumes   = var.ebs_root_volume_gb * local.unit_prices.ebs_root_volumes
    ebs_data_volumes   = var.ebs_data_volume_gb * local.unit_prices.ebs_data_volumes
  }

  total_monthly_cost = sum(values(local.costs))
}
