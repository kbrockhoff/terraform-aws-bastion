# AWS Bastion Host Terraform Module Guide for AI Agents

Provisions an AWS autoscaling groups and associated launch template which manages SSM session capable bastion hosts.
No other types of connections are allowed. Provides the ability to scale down to zero instances during off-hours.

## Components

### Launch Template
- Configures it's instances to support SSM sessions
- Installs commonly used network troubleshooting tools

### Autoscaling Group
- Supports scheduled scaling to zero during off-hours
- Uses network tags to determine which subnets to deploy to

