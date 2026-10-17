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
  } : {}

  # us-east-1 on-demand prices in USD, used only when a result cannot be parsed
  default_unit_prices = {
    kms_keys           = 1.00      # per key-month
    cloudwatch_metrics = 0.30      # per metric-month, first tier
    cloudwatch_alarms  = 0.10      # per standard alarm-month
    sns_requests       = 0.0000005 # per request beyond the free tier
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

  # Assumes each alarm sends one notification per day (30 per month)
  sns_requests_per_month = var.cloudwatch_alarm_count * 30

  costs = {
    kms_keys           = var.kms_key_count * local.unit_prices.kms_keys
    cloudwatch_metrics = var.cloudwatch_metric_count * local.unit_prices.cloudwatch_metrics
    cloudwatch_alarms  = var.cloudwatch_alarm_count * local.unit_prices.cloudwatch_alarms
    sns_requests       = local.sns_requests_per_month * local.unit_prices.sns_requests
  }

  total_monthly_cost = sum(values(local.costs))
}
