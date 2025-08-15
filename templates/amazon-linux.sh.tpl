#!/usr/bin/env bash
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

##
## Enable SSM
##
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
systemctl status amazon-ssm-agent

${user_data}
