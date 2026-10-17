#!/usr/bin/env bash
# Verifies a modules/cost-estimation submodule against the cost estimation contract.
#   offline: fmt, init, validate, tflint, contract checks (inputs, outputs, no region maps)
#   live (when AWS credentials are available): plans the module in several regions and fails
#     if any unit price fell back to its default, i.e. the Pricing API result was not parsed
#
# Usage: check-cost-estimation.sh <path/to/repo/modules/cost-estimation> [region ...]
#   COST_ARGS='instance_count = 2'  extra HCL arguments for the module calls (required inputs)
#   SKIP_LIVE=1                     run only the offline checks
# The live plan uses the default AWS credential chain, e.g. AWS_PROFILE=dev-green.
set -euo pipefail

MODULE_DIR="$(cd "${1:?usage: check-cost-estimation.sh <cost-estimation dir> [region ...]}" && pwd)"
shift
REGIONS=("$@")
[ ${#REGIONS[@]} -gt 0 ] || REGIONS=(us-east-1 us-west-2 eu-west-1 ap-southeast-2 sa-east-1)
EXTRA_ARGS="${COST_ARGS:-}"
SENTINEL=987654.321
WORK_DIR="$(mktemp -d "${TMPDIR%/}/check-cost-estimation.XXXXXX" 2>/dev/null || mktemp -d /tmp/check-cost-estimation.XXXXXX)"
trap 'rm -rf "$WORK_DIR"' EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

echo "==> fmt / validate / tflint: $MODULE_DIR"
terraform fmt -check -recursive "$MODULE_DIR"
(cd "$MODULE_DIR" && terraform init -backend=false -input=false >/dev/null && terraform validate)
if command -v tflint >/dev/null 2>&1; then
  tflint --chdir="$MODULE_DIR"
fi

echo "==> contract checks"
for v in enabled region; do
  grep -q "variable \"$v\"" "$MODULE_DIR/variables.tf" || fail "missing variable $v"
done
for o in monthly_cost_estimate cost_breakdown; do
  grep -q "output \"$o\"" "$MODULE_DIR/outputs.tf" || fail "missing output $o"
done
for l in pricing_results default_unit_prices unit_prices costs total_monthly_cost; do
  grep -qE "^\s+$l\s+=" "$MODULE_DIR/locals.tf" || fail "missing local $l"
done
if grep -nE 'usagetype_region|region_location_map|pricing_location' "$MODULE_DIR"/*.tf; then
  fail "hand-maintained region maps found; filter on regionCode instead"
fi
if grep -nE -A1 'field\s*=\s*"location"' "$MODULE_DIR"/*.tf; then
  fail "location filters found; filter on regionCode instead"
fi
grep -q 'aws_pricing_product' "$MODULE_DIR/main.tf" || fail "no aws_pricing_product lookups in main.tf"
lookups=$(grep -c '^data "aws_pricing_product"' "$MODULE_DIR/main.tf")
region_filters=$(grep -cE 'field\s*=\s*"regionCode"' "$MODULE_DIR/main.tf")
[ "$lookups" -eq "$region_filters" ] || fail "$lookups pricing lookups but $region_filters regionCode filters"

if [ "${SKIP_LIVE:-}" = "1" ]; then
  echo "==> live plan skipped (SKIP_LIVE=1)"
  echo "==> offline cost estimation checks passed"
  exit 0
fi

echo "==> live plan in: ${REGIONS[*]}"
# Copy the module, replace every fallback price with a sentinel and expose the parsed prices
cp -R "$MODULE_DIR" "$WORK_DIR/module"
rm -rf "$WORK_DIR/module/.terraform" "$WORK_DIR/module/.terraform.lock.hcl"
awk -v s="$SENTINEL" '
  /default_unit_prices[[:space:]]*=[[:space:]]*\{/ { inblock = 1; print; next }
  inblock && /^[[:space:]]*\}/ { inblock = 0 }
  inblock && /=/ { sub(/=[[:space:]]*[0-9.eE+-]+/, "= " s) }
  { print }
' "$MODULE_DIR/locals.tf" > "$WORK_DIR/module/locals.tf"
cat > "$WORK_DIR/module/zz_check_outputs.tf" <<'EOF'
output "zz_unit_prices" { value = local.unit_prices }
output "zz_priced_components" { value = keys(local.pricing_results) }
output "zz_default_components" { value = keys(local.default_unit_prices) }
EOF

mkdir "$WORK_DIR/root"
echo 'provider "aws" { region = "us-east-1" }' > "$WORK_DIR/root/main.tf"
for region in "${REGIONS[@]}"; do
  name="r_${region//-/_}"
  cat >> "$WORK_DIR/root/main.tf" <<EOF
module "$name" {
  source = "../module"
  region = "$region"
  $EXTRA_ARGS
}
output "$name" {
  value = {
    total      = module.$name.monthly_cost_estimate
    breakdown  = module.$name.cost_breakdown
    prices     = module.$name.zz_unit_prices
    priced     = module.$name.zz_priced_components
    defaulted  = module.$name.zz_default_components
  }
}
EOF
done
cat >> "$WORK_DIR/root/main.tf" <<EOF
module "disabled" {
  source  = "../module"
  enabled = false
  region  = "us-west-2"
  $EXTRA_ARGS
}
output "disabled" { value = [module.disabled.monthly_cost_estimate, module.disabled.cost_breakdown] }
EOF

(cd "$WORK_DIR/root" && terraform init -input=false >/dev/null \
  && terraform plan -input=false -out=plan.out >/dev/null \
  && terraform show -json plan.out) | python3 -c '
import json, sys
sentinel = float(sys.argv[1])
outputs = json.load(sys.stdin)["planned_values"]["outputs"]
failed = False
disabled = outputs.pop("disabled")["value"]
if disabled != [0, {}]:
    print(f"FAIL: enabled = false returned {disabled}, expected [0, {{}}]"); failed = True
for name, out in sorted(outputs.items()):
    v = out["value"]
    region = name[2:].replace("_", "-")
    missing = sorted(set(v["defaulted"]) - set(v["priced"]))
    if missing:
        print(f"FAIL {region}: no pricing lookup for {missing}"); failed = True
    fallback = sorted(k for k, p in v["prices"].items() if abs(p - sentinel) < 1e-6)
    if fallback:
        print(f"FAIL {region}: fell back to default price for {fallback}"); failed = True
    prices = ", ".join(f"{k}={p:g}" for k, p in sorted(v["prices"].items()))
    total = v["total"]
    print(f"{region:15s} total=${total:.4f}  {prices}")
sys.exit(1 if failed else 0)
' "$SENTINEL"
echo "==> cost estimation checks passed"
