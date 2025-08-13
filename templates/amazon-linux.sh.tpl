#!/usr/bin/env bash
exec > >(tee /var/log/user-data.log | logger -t user-data -s 2>/dev/console) 2>&1

##
## Setup SSH Config
##
cat <<"__EOF__" > /home/${ssh_user}/.ssh/config
Host *
    UserKnownHostsFile /home/${ssh_user}/.ssh/known_hosts
__EOF__
chmod 600 /home/${ssh_user}/.ssh/config
chown ${ssh_user}:${ssh_user} /home/${ssh_user}/.ssh/config
ssh-keyscan -H trusted-server.com >> /home/${ssh_user}/.ssh/known_hosts
chmod 600 /home/${ssh_user}/.ssh/known_hosts
chown ${ssh_user}:${ssh_user} /home/${ssh_user}/.ssh/known_hosts

##
## Enable SSM
##
systemctl enable amazon-ssm-agent
systemctl start amazon-ssm-agent
systemctl status amazon-ssm-agent

${user_data}
