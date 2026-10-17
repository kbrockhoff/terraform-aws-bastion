# Paste into the AWS MCP server's aws___run_script tool. Do not run it locally.
#
# Checks that every aws_pricing_product lookup in a cost-estimation submodule matches exactly
# one product in each region, and reports the lowest paid tier the module's locals will pick.
#
# 1. Fill LOOKUPS with one entry per data source: name -> (service_code, filters without regionCode).
# 2. Run with OFFSET = 0, then OFFSET += BATCH until the result says "done": True.
#    aws___run_script allows 100 API calls per script, so each run covers BATCH regions.

LOOKUPS = {
    "kms_keys": ("AWSKMS", {"productFamily": "Encryption Key"}),
}
OFFSET = 0

REGIONS = [
    "af-south-1", "ap-east-1", "ap-east-2", "ap-northeast-1", "ap-northeast-2", "ap-northeast-3",
    "ap-south-1", "ap-south-2", "ap-southeast-1", "ap-southeast-2", "ap-southeast-3", "ap-southeast-4",
    "ap-southeast-5", "ap-southeast-7", "ca-central-1", "ca-west-1", "eu-central-1", "eu-central-2",
    "eu-north-1", "eu-south-1", "eu-south-2", "eu-west-1", "eu-west-2", "eu-west-3", "il-central-1",
    "me-central-1", "me-south-1", "mx-central-1", "sa-east-1", "us-east-1", "us-east-2", "us-west-1",
    "us-west-2", "us-gov-east-1", "us-gov-west-1",
]
BATCH = max(1, 95 // len(LOOKUPS))


async def lookup(service_code, filters, region):
    response = await call_boto3(
        service_name="pricing", operation_name="GetProducts", region_name="us-east-1",
        params={"ServiceCode": service_code, "Filters": [
            {"Type": "TERM_MATCH", "Field": k, "Value": v}
            for k, v in {**filters, "regionCode": region}.items()
        ]},
    )
    products = [json.loads(p) for p in response.get("PriceList", [])]
    if len(products) != 1:
        return {"matches": len(products), "usagetypes": sorted({p["product"]["attributes"].get("usagetype", "") for p in products})[:10]}
    offers = list(products[0]["terms"].get("OnDemand", {}).values())
    paid = sorted(
        (float(d["beginRange"]), float(d["pricePerUnit"].get("USD", "0")), d["unit"])
        for d in (offers[0]["priceDimensions"].values() if offers else [])
        if float(d["pricePerUnit"].get("USD", "0")) > 0
    )
    return {"matches": 1, "unit_price": paid[0][1] if paid else None, "unit": paid[0][2] if paid else None, "paid_tiers": len(paid)}


regions = REGIONS[OFFSET:OFFSET + BATCH]
jobs = [(name, region, svc, f) for region in regions for name, (svc, f) in LOOKUPS.items()]
outcomes = await asyncio.gather(*[lookup(svc, f, region) for _, region, svc, f in jobs], return_exceptions=True)

failures, prices = {}, collections.defaultdict(dict)
for (name, region, _, _), outcome in zip(jobs, outcomes):
    if isinstance(outcome, Exception):
        failures[f"{name} {region}"] = str(outcome)
    elif outcome["matches"] != 1 or outcome["unit_price"] is None:
        failures[f"{name} {region}"] = outcome
    else:
        prices[name][region] = f'{outcome["unit_price"]} per {outcome["unit"]} ({outcome["paid_tiers"]} paid tiers)'

result = {
    "regions_checked": regions,
    "failures": failures,
    "prices": dict(prices),
    "next_offset": OFFSET + BATCH,
    "done": OFFSET + BATCH >= len(REGIONS),
}
result
