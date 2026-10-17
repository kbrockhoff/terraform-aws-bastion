# Cost Estimation Submodule Contract

Every Terraform module built from the `terraform-module` template ships a `modules/cost-estimation`
submodule. It turns the parent module's configuration into an estimated monthly on-demand cost in
USD, using live prices from the AWS Pricing API. The estimate shows up in `terraform plan` output,
so a mistake in a pricing lookup breaks every plan of the parent module.

## Root wiring

`cost-estimation.tf` in the parent module root:

```hcl
# ----
# Pricing Calculator
# ----

module "pricing" {
  source = "./modules/cost-estimation"

  providers = {
    aws = aws.pricing
  }

  enabled = var.enabled && var.cost_estimation_config.enabled
  region  = local.region

  # One argument per cost driver, derived from the parent's own configuration
  kms_key_count          = var.enabled && var.encryption_config.create_kms_key ? 1 : 0
  cloudwatch_alarm_count = var.enabled && var.alarms_config.enabled ? 3 : 0
}
```

- The module call stays named `pricing`, and the provider alias stays `aws.pricing`. The parent's
  `versions.tf` declares `configuration_aliases = [aws.pricing]`, and every example configures
  that alias with `region = "us-east-1"`, where the Pricing API lives.
- `variable "cost_estimation_config"` is an object with `enabled = bool` (default `true`). Usage
  assumptions that can't be derived from the configuration, such as GB transferred per month,
  are `optional()` attributes of the same object with documented defaults:

  ```hcl
  variable "cost_estimation_config" {
    description = "Configuration object for monthly cost estimation"
    type = object({
      enabled              = bool
      s3_storage_gb        = optional(number, 1)   # state files
      nat_data_gb_monthly  = optional(number, 100)
    })
    default = {
      enabled = true
    }
  }
  ```
- Root `outputs.tf` passes through `monthly_cost_estimate` and `cost_breakdown` unchanged.
- Quantities passed in must be zero for components the configuration doesn't create, so a
  disabled feature costs nothing.

## Submodule files

```
modules/cost-estimation/
  README.md      # header + assumptions, terraform-docs injected between BEGIN/END_TF_DOCS
  main.tf        # one data "aws_pricing_product" per unit price
  locals.tf      # pricing_results, default_unit_prices, paid_price_dimensions, unit_prices, costs, total_monthly_cost
  outputs.tf     # monthly_cost_estimate, cost_breakdown
  variables.tf   # enabled, region, then one input per cost driver
  versions.tf    # same required_version as the parent; aws >= 5.0
```

## Inputs

| Name | Type | Rule |
|------|------|------|
| `enabled` | bool | default `true`; gates every lookup |
| `region` | string | the region the parent deploys to |
| `<thing>_count`, `<thing>_gb`, `<thing>_monthly_hours`, `<thing>_requests_monthly`, ... | number | default `0`, validation `>= 0` |
| product selectors such as `ec2_instance_type`, `ebs_volume_type` | string | only when the price depends on them; validate allowed values |

Every quantity input defaults to `0`, including `<thing>_monthly_hours`. The root passes 730 for
always-on resources, or the scheduled hours when the parent knows a schedule.

Inputs are quantities, not feature flags. Pass `nat_gateway_count = 0`, not
`nat_gateway_enabled = false`. Name each input after the unit it is priced in.

## Outputs (exact names)

| Name | Value |
|------|-------|
| `monthly_cost_estimate` | `local.pricing_enabled ? local.total_monthly_cost : 0` |
| `cost_breakdown` | `local.pricing_enabled ? local.costs : {}`, a `map(number)` of USD per month keyed by component |

No other outputs. Unit prices, resource counts and API status are implementation details.

## Pricing lookups (`main.tf`)

`aws_pricing_product` fails the plan unless its filters match **exactly one** product. Every
lookup must therefore:

- use `count = local.pricing_enabled ? 1 : 0`;
- filter on `regionCode = var.region`, plus attributes whose values are the same in every region
  (`productFamily`, `group`, `alarmType`, `storageClass`, `volumeApiName`, `instanceType`, ...);
- **never** filter on `location` names or on region-prefixed `usagetype` values, and never keep
  region-code or location maps. Those values differ per region and per service (`EU` vs `EUW1`,
  `EU (Ireland)` vs `Europe (Ireland)`), and they drift;
- be validated with `scripts/validate_pricing_filters.py` in **every** region of its `REGIONS`
  list, and for every allowed value of any product-selector input it depends on.

Name each data source after its `costs` key. Keys are `<service>_<thing>`, using the full
service name (`dynamodb_read_requests`, not `dynamo_reads`): `kms_keys`, `nat_gateway_hours`,
`s3_put_requests`. `cost_breakdown` keys are part of the module's public interface, so when you
regenerate an existing module, keep them unless they are wrong, and call out any rename as a
breaking change.

Check product variants: filters that match only on family or group often also match
Infrequent Access, Standard-IA or other variants (DynamoDB `tableclass`, S3 `storageClass`,
EBS `volumeApiName`). Pin the variant the resource actually uses.

## Cost calculation (`locals.tf`)

Follow the asset pattern exactly:

- `pricing_results`: a map from component key to `data.aws_pricing_product.<key>[0].result`,
  or `{}` when disabled.
- `default_unit_prices`: the us-east-1 unit price per component, with a comment naming the unit.
  These are used only if a result can't be parsed, and `check-cost-estimation.sh` fails the
  check if any of them is used.
- `paid_price_dimensions` / `unit_prices`: the **lowest tier with a non-zero price**. $0 tiers are
  account-wide free tiers, so they aren't credited to one module. If a module's expected usage
  spans tiers, document it in the README; the estimate stays on-demand and first-paid-tier.
- `costs`: one entry per component, as quantity × unit price.
- `total_monthly_cost = sum(values(local.costs))`.

Unit conventions:
- 730 hours per month for always-on resources, unless the parent knows a schedule (pass
  `<thing>_monthly_hours`).
- Check the `unit` that the validator reports (`Hrs`, `GB-Mo`, `GB`, `Requests`, `Keys`, ...)
  and convert the quantity to match. For example, request prices are per request, not per
  million.

## What to price

Price resources with a recurring on-demand charge: KMS keys, CloudWatch metrics, alarms, log
ingestion and storage, SNS, NAT gateway hours and data processed, public IPv4 addresses, VPC
endpoint hours and data, EC2 instances, EBS volumes, S3 storage and requests, DynamoDB capacity
and storage, and similar.

Counting rules:
- **Alarms** are billed per metric they evaluate. A metric-math alarm over N metrics counts as N
  standard alarms. Alarms on AWS-provided metrics cost nothing extra for the metric itself.
- **Custom metrics** count only metrics the module publishes or enables, such as EC2 detailed
  monitoring at 7 metrics per instance. Built-in AWS metrics are free.
- **SNS notifications:** if the parent's alarm count isn't the number of notifying alarms, pass
  an explicit `sns_requests_monthly` instead of deriving it from `cloudwatch_alarm_count`.
- **Scheduled capacity:** resources that exist only while instances run (instance-store, EBS
  volumes deleted on termination, detailed-monitoring metrics) are prorated by
  `scheduled hours / 730`. Resources that persist are billed for the full 730.
- **Instance counts** use desired capacity clamped to min/max, not max size.

Usage-based components:
- **Retention-based storage** (logs, snapshots): price the steady state, which is monthly volume
  × retention in months, or monthly volume × 12 when retention is unlimited. Say so in the README.
- **Traffic shared between components** (NAT gateway vs. VPC endpoint data): use one assumption
  in `cost_estimation_config`, and document whether each component gets all of it or a split.
- **Don't reuse one assumption for a different quantity**, such as traffic volume as flow log
  volume. Add a separate setting instead.

Skip free resources (VPC, subnets, route tables, security groups, IAM) and charges that depend on
traffic the module can't know about, unless `cost_estimation_config` carries an explicit
assumption for them.
