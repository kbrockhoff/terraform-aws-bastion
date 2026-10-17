#!/usr/bin/env bash
# Offline verification of a modules/deployer submodule against the deployer contract.
#   - fmt, init, validate, tflint (if installed)
#   - plans the module twice with a stub cicdrole-style role (attached and policy-only),
#     using fake credentials so no AWS account is touched
#   - fails if any policy exceeds the 6,144 character managed policy limit
#
# Usage: check-deployer.sh <path/to/repo/modules/deployer> [name_prefix]
#   DEPLOYER_EXTRA_ARGS='flag = true'  extra HCL arguments for the attached/policy-only calls,
#                                      used to size-check optional statements
set -euo pipefail

DEPLOYER_DIR="$(cd "${1:?usage: check-deployer.sh <deployer dir> [name_prefix]}" && pwd)"
NAME_PREFIX="${2:-prod-usw2}"
EXTRA_ARGS="${DEPLOYER_EXTRA_ARGS:-}"
MAX_CHARS=6144
WORK_DIR="$(mktemp -d "${TMPDIR:-/tmp}/check-deployer.XXXXXX")"
trap 'rm -rf "$WORK_DIR"' EXIT

echo "==> fmt / validate / tflint: $DEPLOYER_DIR"
terraform fmt -check -recursive "$DEPLOYER_DIR"
(cd "$DEPLOYER_DIR" && terraform init -backend=false -input=false >/dev/null && terraform validate)
if command -v tflint >/dev/null 2>&1; then
  tflint --chdir="$DEPLOYER_DIR"
fi

for f in variables.tf outputs.tf; do
  [ -f "$DEPLOYER_DIR/$f" ] || { echo "FAIL: missing $f" >&2; exit 1; }
done
for v in enabled name_prefix iam_role_name tags partition region account_id; do
  grep -q "variable \"$v\"" "$DEPLOYER_DIR/variables.tf" || { echo "FAIL: missing variable $v" >&2; exit 1; }
done
for o in policy_arns policy_names; do
  grep -q "output \"$o\"" "$DEPLOYER_DIR/outputs.tf" || { echo "FAIL: missing output $o" >&2; exit 1; }
done
if grep -rqE 'aws_iam_openid_connect_provider|AssumeRoleWithWebIdentity|resource "aws_iam_role" ' "$DEPLOYER_DIR"/*.tf; then
  echo "FAIL: deployer must not create roles or OIDC trust; that belongs to terraform-aws-cicdrole" >&2
  exit 1
fi

cat > "$WORK_DIR/main.tf" <<EOF
provider "aws" {
  region                      = "us-west-2"
  access_key                  = "AKIAEXAMPLE"
  secret_key                  = "example"
  skip_credentials_validation = true
  skip_requesting_account_id  = true
  skip_metadata_api_check     = true
}

# Stands in for terraform-aws-cicdrole: name known at plan time, ARN unknown
resource "aws_iam_role" "cicd" {
  name               = "${NAME_PREFIX}-cicd-deployer"
  assume_role_policy = "{}"
}

module "attached" {
  source        = "${DEPLOYER_DIR}"
  name_prefix   = "${NAME_PREFIX}"
  iam_role_name = aws_iam_role.cicd.name
  region        = "us-west-2"
  account_id    = "123456789012"
  ${EXTRA_ARGS}
}

module "policy_only" {
  source      = "${DEPLOYER_DIR}"
  name_prefix = "${NAME_PREFIX}"
  region      = "us-west-2"
  account_id  = "123456789012"
  ${EXTRA_ARGS}
}

module "disabled" {
  source      = "${DEPLOYER_DIR}"
  enabled     = false
  name_prefix = "${NAME_PREFIX}"
  region      = "us-west-2"
  account_id  = "123456789012"
}
EOF

echo "==> plan with stub role"
(cd "$WORK_DIR" && terraform init -input=false >/dev/null && terraform plan -input=false -refresh=false -out=plan.out >/dev/null)
(cd "$WORK_DIR" && terraform show -json plan.out) | python3 -c '
import json, sys
max_chars = int(sys.argv[1])
name_prefix = sys.argv[2]
plan = json.load(sys.stdin)
changes = [r for r in plan["resource_changes"] if r["change"]["actions"] == ["create"]]
policies = [r for r in changes if r["type"] == "aws_iam_policy"]
attachments = [r for r in changes if r["type"] == "aws_iam_role_policy_attachment"]
failed = False
by_module = lambda rs, m: [r for r in rs if r["address"].startswith(f"module.{m}.")]
for r in policies:
    doc = json.loads(r["change"]["after"]["policy"])
    size = len(json.dumps(doc, separators=(",", ":")))
    statements = doc["Statement"]
    actions = sum(len(s["Action"]) if isinstance(s["Action"], list) else 1 for s in statements)
    for st in statements:
        res = st.get("Resource", [])
        for arn in [res] if isinstance(res, str) else res:
            # role/PREFIX-* (or role/*) also matches the cicdrole PREFIX-cicd-deployer role
            if ":iam::" in arn and (":role/*" in arn or arn.endswith(f":role/{name_prefix}-*") or arn.endswith(f":role/{name_prefix}*")):
                sid = st.get("Sid", "?")
                print(f"FAIL: {sid} grants on {arn}, which matches the cicdrole role; use exact role names")
                failed = True
    flag = "OK " if size <= max_chars else "TOO LARGE"
    failed |= size > max_chars
    address = r["address"]
    print(f"{flag} {size:5d}/{max_chars} chars {len(statements):3d} statements {actions:4d} actions  {address}")
if not by_module(policies, "attached"):
    print("FAIL: enabled module planned no policies"); failed = True
if len(by_module(attachments, "attached")) != len(by_module(policies, "attached")):
    print("FAIL: expected one attachment per policy when iam_role_name is set"); failed = True
if by_module(attachments, "policy_only"):
    print("FAIL: attachments planned with empty iam_role_name"); failed = True
if by_module(changes, "disabled"):
    print("FAIL: resources planned with enabled = false"); failed = True
policy_count = len(by_module(policies, "attached"))
if policy_count > 3:
    print(f"WARN: {policy_count} policies; a role holds 10 managed policies by default")
sys.exit(1 if failed else 0)
' "$MAX_CHARS" "$NAME_PREFIX"
echo "==> deployer contract checks passed"
