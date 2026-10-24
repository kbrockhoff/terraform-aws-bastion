package test

import (
	"bytes"
	"encoding/json"
	"path/filepath"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// AWS rejects customer managed policies larger than this, not counting whitespace
const ManagedPolicyMaxChars = 6144

// getDeployerTerraformOptions returns plan options for the deployer submodule with the given role name
func getDeployerTerraformOptions(t *testing.T, iamRoleName string) *terraform.Options {
	// Copy to a temp dir so parallel tests do not share one .terraform directory
	terraformOptions := getBaseTerraformOptions(test_structure.CopyTerraformFolderToTemp(t, "..", "modules/deployer"))
	terraformOptions.PlanFilePath = filepath.Join(t.TempDir(), "plan.out")
	terraformOptions.Vars = map[string]interface{}{
		"name_prefix":   generateTestNamePrefix("dep"),
		"iam_role_name": iamRoleName,
		"region":        "us-west-2",
		"account_id":    "123456789012",
	}
	return terraformOptions
}

func TestDeployerAttachesPoliciesToRole(t *testing.T) {
	t.Parallel()
	terraformOptions := getDeployerTerraformOptions(t, "test-cicd-deployer")

	plan := terraform.InitAndPlanAndShowWithStruct(t, terraformOptions)

	for _, key := range []string{"main", "iam"} {
		terraform.RequirePlannedValuesMapKeyExists(t, plan, `aws_iam_policy.this["`+key+`"]`)
		terraform.RequirePlannedValuesMapKeyExists(t, plan, `aws_iam_role_policy_attachment.this["`+key+`"]`)
		attachment := plan.ResourcePlannedValuesMap[`aws_iam_role_policy_attachment.this["`+key+`"]`]
		assert.Equal(t, "test-cicd-deployer", attachment.AttributeValues["role"],
			"policy %q should attach to the role named by iam_role_name", key)
	}
}

func TestDeployerWithoutRoleOnlyCreatesPolicies(t *testing.T) {
	t.Parallel()
	terraformOptions := getDeployerTerraformOptions(t, "")

	plan := terraform.InitAndPlanAndShowWithStruct(t, terraformOptions)

	terraform.RequirePlannedValuesMapKeyExists(t, plan, `aws_iam_policy.this["main"]`)
	terraform.RequirePlannedValuesMapKeyExists(t, plan, `aws_iam_policy.this["iam"]`)
	for address := range plan.ResourcePlannedValuesMap {
		assert.NotContains(t, address, "aws_iam_role_policy_attachment",
			"no policy attachment should be planned when iam_role_name is empty")
	}
}

func TestDeployerPoliciesFitManagedPolicySizeLimit(t *testing.T) {
	t.Parallel()
	terraformOptions := getDeployerTerraformOptions(t, "")

	plan := terraform.InitAndPlanAndShowWithStruct(t, terraformOptions)

	for _, key := range []string{"main", "iam"} {
		address := `aws_iam_policy.this["` + key + `"]`
		terraform.RequirePlannedValuesMapKeyExists(t, plan, address)
		policy, ok := plan.ResourcePlannedValuesMap[address].AttributeValues["policy"].(string)
		require.True(t, ok, "%s policy document should be known at plan time", address)

		var compact bytes.Buffer
		require.NoError(t, json.Compact(&compact, []byte(policy)), "%s policy should be valid JSON", address)
		assert.LessOrEqual(t, compact.Len(), ManagedPolicyMaxChars,
			"%s policy is %d chars without whitespace; split it into another policy document", address, compact.Len())
	}
}
