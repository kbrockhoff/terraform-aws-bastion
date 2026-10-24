# Cost Estimation Terraform Module

Estimates the monthly on-demand cost in USD of the resources the parent module provisions, using
live prices from the AWS Pricing API.

The parent passes a provider pinned to `us-east-1`, where the Pricing API is available, and the
`region` it deploys to. Each price is looked up by `regionCode` with filters validated to match
exactly one product in every region.

## Assumptions

- On-demand prices only; no Savings Plans, Reserved capacity or account free tiers.
- Tiered prices use the lowest paid tier.
- SNS requests assume one notification per alarm per day (30 per month).
- If a price can't be parsed, a us-east-1 default is used instead.

<!-- BEGIN_TF_DOCS -->
<!-- END_TF_DOCS -->
