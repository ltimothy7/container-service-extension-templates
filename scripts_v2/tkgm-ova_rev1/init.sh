#!/usr/bin/env bash
set -e

netcfg1_path=/etc/netplan/01-netcfg.yaml
netcfg1_before_path=/etc/netplan/01-netcfg.yaml.BeforeVMwareCustomization
netcfg50_path=/etc/netplan/50-cloud-init.yaml
netcfg50_before_path=/etc/netplan/50-cloud-init.yaml.BeforeVMwareCustomization

[ -f $netcfg1_path ] && mv $netcfg1_path /etc/netplan/01-netcfg.yaml.bak
[ -f $netcfg1_before_path ] && mv $netcfg1_before_path /etc/netplan/01-netcfg.yaml.BeforeVMwareCustomization.bak
[ -f $netcfg50_path ] && mv $netcfg50_path /etc/netplan/50-cloud-init.yaml.bak
[ -f $netcfg50_before_path ] && mv $netcfg50_before_path /etc/netplan/50-cloud-init.yaml.BeforeVMwareCustomization.bak

sed -i -e 's/^PasswordAuthentication yes/PasswordAuthentication no/' -e 's/^PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

apt remove -y cloud-init
dpkg-reconfigure openssh-server
sync
sync

exit 0
