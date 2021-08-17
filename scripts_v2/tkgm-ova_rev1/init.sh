#!/usr/bin/env bash
set -e

mv /etc/netplan/01-netcfg.yaml /etc/netplan/01-netcfg.yaml.bak
mv /etc/netplan/01-netcfg.yaml.BeforeVMwareCustomization /etc/netplan/01-netcfg.yaml.BeforeVMwareCustomization.bak
mv /etc/netplan/50-cloud-init.yaml /etc/netplan/50-cloud-init.yaml.bak
mv /etc/netplan/50-cloud-init.yaml.BeforeVMwareCustomization /etc/netplan/50-cloud-init.yaml.BeforeVMwareCustomization.bak

sed -i -e 's/^PasswordAuthentication yes/PasswordAuthentication no/' -e 's/^PermitRootLogin yes/PermitRootLogin prohibit-password/' /etc/ssh/sshd_config

apt remove -y cloud-init
dpkg-reconfigure openssh-server
sync
sync
