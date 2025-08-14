package test

import (
	"testing"

	"github.com/gruntwork-io/terratest/modules/terraform"
	"github.com/stretchr/testify/assert"
)

const RandomIDLength = 10

func TestTerraformDefaultsExample(t *testing.T) {
	t.Parallel()
	expectedName := generateTestNamePrefix("def")

	terraformOptions := &terraform.Options{
		// The path to where our Terraform code is located
		TerraformDir: "../examples/defaults",

		// Variables to pass to our Terraform code using -var options
		Vars: map[string]interface{}{
			"name_prefix": expectedName,
		},

		// Environment variables to set when running Terraform
		EnvVars: map[string]string{},
	}

	// At the end of the test, run `terraform destroy` to clean up any resources that were created
	defer terraform.Destroy(t, terraformOptions)

	// This will run `terraform init` and `terraform plan` to validate configuration without creating resources
	terraform.Init(t, terraformOptions)
	planOutput := terraform.Plan(t, terraformOptions)

	// Verify the plan completed without errors and shows expected resource creation
	assert.NotEmpty(t, planOutput)
	
	// Verify core resources are planned for creation
	assert.Contains(t, planOutput, "module.main.aws_launch_template.bastion[0]")
	assert.Contains(t, planOutput, "module.main.aws_autoscaling_group.bastion[0]")
	assert.Contains(t, planOutput, "module.main.aws_iam_role.bastion[0]")
	assert.Contains(t, planOutput, "module.main.aws_kms_key.bastion[0]")
	assert.Contains(t, planOutput, "will be created")
	
	// Verify SNS topic is NOT created by default (alarms_enabled=false)
	assert.NotContains(t, planOutput, "module.main.aws_sns_topic.alarms")
	
	// Verify schedules ARE created for Development environment
	assert.Contains(t, planOutput, "module.main.aws_autoscaling_schedule.scale_down[0]")
	assert.Contains(t, planOutput, "module.main.aws_autoscaling_schedule.scale_up[0]")

}
