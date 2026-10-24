package test

import (
	"path/filepath"
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	test_structure "github.com/gruntwork-io/terratest/modules/test-structure"
	"github.com/stretchr/testify/assert"
	"github.com/stretchr/testify/require"
)

// getCostEstimationTerraformOptions returns plan options for the cost-estimation submodule
func getCostEstimationTerraformOptions(t *testing.T, vars map[string]interface{}) *terraform.Options {
	// Copy to a temp dir so parallel tests do not share one .terraform directory
	terraformOptions := getBaseTerraformOptions(test_structure.CopyTerraformFolderToTemp(t, "..", "modules/cost-estimation"))
	terraformOptions.PlanFilePath = filepath.Join(t.TempDir(), "plan.out")
	// The Pricing API is only served from us-east-1; the region input selects the priced region
	terraformOptions.EnvVars = map[string]string{
		"AWS_REGION":         "us-east-1",
		"AWS_DEFAULT_REGION": "us-east-1",
	}
	terraformOptions.Vars = vars
	return terraformOptions
}

func TestCostEstimationPricesEveryComponent(t *testing.T) {
	t.Parallel()
	terraformOptions := getCostEstimationTerraformOptions(t, map[string]interface{}{
		"region":                  "us-west-2",
		"kms_key_count":           1,
		"cloudwatch_metric_count": 7,
		"cloudwatch_alarm_count":  5,
		"sns_requests_monthly":    90,
		"ec2_instance_type":       "t3.micro",
		"ec2_instance_count":      1,
		"ec2_monthly_hours":       730,
		"ebs_root_volume_type":    "gp3",
		"ebs_root_volume_gb":      8,
		"ebs_data_volume_type":    "gp3",
		"ebs_data_volume_gb":      10,
	})

	plan := terraform.InitAndPlanAndShowWithStruct(t, terraformOptions)

	outputs := plan.RawPlan.PlannedValues.Outputs
	require.Contains(t, outputs, "cost_breakdown")
	breakdown, ok := outputs["cost_breakdown"].Value.(map[string]interface{})
	require.True(t, ok, "cost_breakdown should be a map known at plan time")
	for _, component := range []string{
		"kms_keys", "cloudwatch_metrics", "cloudwatch_alarms", "sns_requests",
		"ec2_instances", "ebs_root_volumes", "ebs_data_volumes",
	} {
		cost, ok := breakdown[component].(float64)
		require.True(t, ok, "cost_breakdown should include a numeric %q", component)
		assert.Greater(t, cost, 0.0, "%q should have a positive cost for a non-zero quantity", component)
	}

	total, ok := outputs["monthly_cost_estimate"].Value.(float64)
	require.True(t, ok, "monthly_cost_estimate should be a number known at plan time")
	assert.Greater(t, total, 0.0, "monthly_cost_estimate should be positive")
}

func TestCostEstimationDisabledReturnsZero(t *testing.T) {
	t.Parallel()
	terraformOptions := getCostEstimationTerraformOptions(t, map[string]interface{}{
		"enabled":            false,
		"region":             "us-west-2",
		"ec2_instance_count": 1,
	})

	plan := terraform.InitAndPlanAndShowWithStruct(t, terraformOptions)

	outputs := plan.RawPlan.PlannedValues.Outputs
	require.Contains(t, outputs, "monthly_cost_estimate")
	assert.Equal(t, 0.0, outputs["monthly_cost_estimate"].Value, "monthly_cost_estimate should be 0 when disabled")
	assert.Empty(t, outputs["cost_breakdown"].Value, "cost_breakdown should be empty when disabled")
}
