# Changelog

## 0.1.0 (2025-08-15)


### Features

* add automated EBS snapshot configuration for data volumes ([0f9622f](https://github.com/kbrockhoff/terraform-aws-bastion/commit/0f9622f20c36fa22288583be93bc2fb1545637e6))
* add read-only root filesystem and optional additional data volume ([34a6ec9](https://github.com/kbrockhoff/terraform-aws-bastion/commit/34a6ec947bb7dac9b7c53e9e88c3f8814ba1dc4b))
* **alarms:** add comprehensive CloudWatch alarms for ASG monitoring ([6b518df](https://github.com/kbrockhoff/terraform-aws-bastion/commit/6b518df814622a4d5e0de0cebb7f5f40b12bf701))
* **core:** replace template placeholders with bastion module name ([c7cd7ea](https://github.com/kbrockhoff/terraform-aws-bastion/commit/c7cd7ea6d51861c133a608c8205b6f34efcd0b73))
* improve module configuration and documentation ([cf6bc73](https://github.com/kbrockhoff/terraform-aws-bastion/commit/cf6bc7302d18792d8bb4079f4ea7542594ad096b))
* **mvp:** implement initial bastion host module ([3483d2c](https://github.com/kbrockhoff/terraform-aws-bastion/commit/3483d2ca3785ae57a960c4ac07f8fce53f65a291))
* **pricing:** add EC2 instance and EBS cost calculations with schedule-based hours ([26dfb8b](https://github.com/kbrockhoff/terraform-aws-bastion/commit/26dfb8b0d1c18d112b32634e0198203b3ce293c4))
* **pricing:** enhance cost estimation with ASG hours calculation ([fa2eabc](https://github.com/kbrockhoff/terraform-aws-bastion/commit/fa2eabcb63dd9b0e39f00bae7ef66d45c38152c8))
* refactor DLM IAM policies and add security constraints ([4159c4f](https://github.com/kbrockhoff/terraform-aws-bastion/commit/4159c4ff1926b9036e5647fa8de1ffc5bf105e7a))
* update default instance type to t3.micro ([1fcac40](https://github.com/kbrockhoff/terraform-aws-bastion/commit/1fcac40ef94bc7832fe6a6839a77303889fd601a))


### Bug Fixes

* correct copilot commit ([36e68ad](https://github.com/kbrockhoff/terraform-aws-bastion/commit/36e68ad002c399a2a1726a3f579c8844bda80d96))
* improve validation ([1f661cb](https://github.com/kbrockhoff/terraform-aws-bastion/commit/1f661cb1b06075a11f0e6e922005e7327fb709b0))
* **lint:** remove unused locals and update tflint config ([e30b949](https://github.com/kbrockhoff/terraform-aws-bastion/commit/e30b949ab10bc148bc9688e2e66c5adeaa2ceff9))
* update template name ([d4a0610](https://github.com/kbrockhoff/terraform-aws-bastion/commit/d4a06101c0be0371f3635216de3d2359013a6ca9))
* user_data more robust ([fff065a](https://github.com/kbrockhoff/terraform-aws-bastion/commit/fff065ade5b00c03afa763cae7864c8c42923635))

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).
