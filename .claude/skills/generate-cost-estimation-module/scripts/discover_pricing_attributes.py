# Paste into the AWS MCP server's aws___run_script tool. Do not run it locally.
#
# Lists the products a filter set matches in a few regions, with their attributes, so you can
# find attributes that pick exactly one product and have the same value in every region
# (group, alarmType, storageClass, volumeApiName, ...). Never filter on location names or
# region-prefixed usagetype values; filter on regionCode instead.
#
# Products without a productFamily (public IPv4, transit gateway): set FILTERS to the exact
# us-east-1 usagetype, e.g. {"usagetype": "PublicIPv4:InUseAddress"}, with REGIONS = ["us-east-1"].
#
# Find a service code first:  call_boto3(service_name="pricing", operation_name="DescribeServices",
#   region_name="us-east-1", params={"ServiceCode": "AmazonEC2"}) returns its attribute names.

SERVICE_CODE = "AmazonCloudWatch"
FILTERS = {"productFamily": "Alarm"}
REGIONS = ["us-east-1", "eu-west-1", "ap-southeast-2"]

# Attributes that vary by region or carry no meaning for filtering
NOISE = {"servicecode", "servicename", "regionCode", "location", "locationType"}


async def products(region):
    response = await call_boto3(
        service_name="pricing", operation_name="GetProducts", region_name="us-east-1",
        params={"ServiceCode": SERVICE_CODE, "MaxResults": 100, "Filters": [
            {"Type": "TERM_MATCH", "Field": k, "Value": v}
            for k, v in {**FILTERS, "regionCode": region}.items()
        ]},
    )
    found = []
    for raw in response.get("PriceList", [])[:40]:
        item = json.loads(raw)
        offers = list(item["terms"].get("OnDemand", {}).values())
        tiers = sorted(
            (float(d["beginRange"]), d["pricePerUnit"].get("USD"), d["unit"])
            for d in (offers[0]["priceDimensions"].values() if offers else [])
        )
        found.append({
            "attributes": {k: v for k, v in item["product"]["attributes"].items() if k not in NOISE},
            "tiers": tiers[:4],
        })
    return found


outcomes = await asyncio.gather(*[products(r) for r in REGIONS], return_exceptions=True)
result = {
    region: (str(o) if isinstance(o, Exception) else {"count": len(o), "products": o})
    for region, o in zip(REGIONS, outcomes)
}
result
