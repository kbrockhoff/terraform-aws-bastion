---
name: generate-cost-estimation-module
description: >
  Generates or regenerates the modules/cost-estimation submodule of a kbrockhoff Terraform module
  built from the terraform-module template. The submodule estimates the parent module's monthly
  AWS cost from live AWS Pricing API prices (aws_pricing_product data sources). Pricing filters
  are discovered and validated in every region through the AWS MCP server. Use when creating a new
  terraform-aws-* module from the template, when billable resources are added to or changed in a
  module, when a plan fails with "Pricing product query not precise enough" or returns no
  product, or when asked to write or review cost estimation for one of these modules.
---

# Generate the cost-estimation submodule

The submodule turns the parent module's configuration into an estimated monthly on-demand cost.
The hard part is the pricing lookups: `aws_pricing_product` fails the plan unless its filters
match exactly one product, and attribute values differ between regions. Each lookup must
therefore be validated against the live Pricing API **in every region** before you write it.

Read `references/contract.md` before writing anything. It fixes the root wiring, inputs, outputs,
lookup rules and calculation pattern. This file covers the workflow.

## Prerequisites

- **AWS MCP server** (`aws-mcp`). Use its `aws___run_script` tool for every Pricing API call;
  it runs Python with `call_boto3` against the API. Load the tool first if it shows up as
  deferred. Don't run the AWS CLI through the shell. If the server isn't connected or has no
  credentials, stop and ask the user to fix it, for example by setting `AWS_PROFILE` in the
  server's environment and reconnecting with `/mcp`. Never write filters you haven't validated.
- `aws___run_script` allows **100 API calls per script**. The bundled scripts batch to stay
  under that.
- AWS credentials for Terraform (for example `AWS_PROFILE=<profile>`) are needed for the live
  plan in step 6. The Pricing API is read-only.

## Workflow

### 1. Lay down the skeleton

If `modules/cost-estimation/` is missing or still the template version, copy `assets/cost-estimation/*`
into `<repo>/modules/cost-estimation/`. Then copy `required_version` from the parent `versions.tf`.
If the root has no `cost-estimation.tf`, add it from the contract's "Root wiring" snippet, along
with `cost_estimation_config`, the `aws.pricing` alias and the two root outputs.

The assets already price KMS keys, CloudWatch custom metrics, standard alarms and SNS requests
with validated filters. Keep the ones the parent uses and delete the rest, with their inputs,
locals entries and README lines.

### 2. List the cost drivers

Go through every resource the parent creates, outside `modules/deployer` and
`modules/cost-estimation`, and keep the ones with a recurring charge (see "What to price" in the
contract). For each one, record:
- the **component key** (`nat_gateway_hours`, `nat_gateway_data_gb`, ...);
- the **quantity**, as an expression over the parent's variables and locals;
- any **usage assumption** that the configuration doesn't determine. These become optional
  attributes of `cost_estimation_config`, with defaults.

### 3. Find exact filters (AWS MCP)

For each component, use `scripts/discover_pricing_attributes.py`:
1. Set `SERVICE_CODE` and a starting `FILTERS` (usually `productFamily`). If you don't know the
   service code or attribute names, call `DescribeServices` or `GetAttributeValues` with
   `call_boto3` first.
2. Paste the script into `aws___run_script`. It lists matching products in three regions with
   their attributes and price tiers.
3. Add region-independent attributes until exactly one product matches. Usually that's `group`,
   plus a subtype such as `alarmType`, `storageClass`, `volumeApiName`, `operation`,
   `endpointType` or `groupDescription`. For NAT gateways, VPC endpoints, public IPv4 and
   transit gateway, `groupDescription` is often the only attribute that tells products apart.
4. Some products have no `productFamily` (public IPv4, transit gateway). To find them, set
   `FILTERS` to the exact us-east-1 `usagetype` (e.g. `{"usagetype": "PublicIPv4:InUseAddress"}`)
   and leave out `REGIONS` other than `us-east-1`, then build region-independent filters from
   the attributes it returns.
5. Check you picked the right product. The `usagetype` suffix and `groupDescription` tell you
   what is billed. For example, `CW:MetricMonitorUsage` (custom metrics) is a different product
   from `CW:MetricsUsage` (Container Insights).

The script always adds `regionCode` itself, so don't put it in `FILTERS`. Never use `location`
or a region-prefixed `usagetype` as a filter.

### 4. Validate every lookup in every region (AWS MCP)

Put every lookup into `LOOKUPS` in `scripts/validate_pricing_filters.py`, including the ones
kept from the assets. Paste the script into `aws___run_script` with `OFFSET = 0`. Re-run with
`OFFSET = next_offset` until `done` is `True`. The batches are independent, so you can send
them as parallel `aws___run_script` calls, one per offset (`0, BATCH, 2*BATCH, ...`, where
`BATCH = 95 // len(LOOKUPS)`).

- `failures` must be empty in every batch. A region with 0 or more than 1 match means the filter
  is wrong, so go back to step 3. If a service really doesn't exist in a region, tell the user
  instead of hiding it.
- If a lookup depends on a product-selector input such as instance type, validate each allowed
  value, or at least the default and the common ones. Zero matches for a type that isn't sold
  in a region is expected, since the plan would fail on the resource anyway. List those regions
  in the report. More than one match is always a filter bug.
- Copy each component's us-east-1 price and unit from `prices` into `default_unit_prices`.

### 5. Write the module

- `main.tf`: one `data "aws_pricing_product"` per component, named after its key and using the
  validated filters plus `regionCode = var.region`.
- `locals.tf`: add each key to `pricing_results`, `default_unit_prices` and `costs`. Keep the
  `paid_price_dimensions` and `unit_prices` blocks as they are. Convert quantities to the unit
  the validator reported, with 730 hours per month for always-on resources.
- `variables.tf`: one numeric input per quantity (default `0`, validation `>= 0`), plus
  selectors as needed.
- `README.md`: purpose, every assumption (usage defaults, 730 hours, first paid tier, on-demand
  only, free tiers excluded), then terraform-docs markers.
- Root: pass each quantity from `cost-estimation.tf`, and make sure it is `0` when the
  matching resource isn't created.

### 6. Verify

```bash
AWS_PROFILE=<profile> COST_ARGS='nat_gateway_count = 2
  data_processed_gb = 100' \
  <this-skill-dir>/scripts/check-cost-estimation.sh <repo>/modules/cost-estimation
```

Set `COST_ARGS` to arguments that make every component non-zero.

The script runs fmt, validate and tflint, and checks the contract: required inputs, outputs and
locals, no region maps or `location` filters, and a `regionCode` filter on every lookup. It then
plans the module live in five regions, and once with `enabled = false`. It fails if a lookup
doesn't match exactly one product, or if any unit price fell back to its default, which means
the result JSON wasn't parsed. Add regions as arguments to cover more. Use `SKIP_LIVE=1` only
when no credentials are available, and say so in the report.

Then, from the repo root:
- run `make check` and `make lint`;
- run `terraform-docs .` before hand-editing any README, then restore unrelated reformatting
  with `git checkout -- <file>`;
- if CI uses checkov, run `checkov -d modules/cost-estimation` with CI's skip list. A module
  made only of data sources may report nothing to scan, which is fine.

### 7. Report

List each component (key, unit price in us-east-1, quantity expression), the assumptions and
their defaults, the regions validated, and the live plan output. Commit only if the user asks.

## Common mistakes

- Filtering on `location` or a region-prefixed `usagetype` because it works in us-east-1. It
  breaks or misprices in other regions.
- Picking a product from its name alone. Check `group`, `groupDescription` and the `usagetype`
  suffix against what the resource actually bills.
- Using `values(priceDimensions)[0]`. Map order isn't the tier order, and the first tier is
  often a $0 free tier.
- Confusing units: a price per GB-Mo vs per GB-hour, or per request vs per million requests.
- Leaving a quantity non-zero when the parent doesn't create the resource.
- Running more than 100 API calls in one `aws___run_script` call. Batch by region with the
  provided scripts.
