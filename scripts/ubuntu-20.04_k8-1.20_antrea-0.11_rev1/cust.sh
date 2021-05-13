#!/usr/bin/env bash

set -e

# disable ipv6 to avoid possible connection errors
echo 'net.ipv6.conf.all.disable_ipv6 = 1' >> /etc/sysctl.conf
echo 'net.ipv6.conf.default.disable_ipv6 = 1' >> /etc/sysctl.conf
echo 'net.ipv6.conf.lo.disable_ipv6 = 1' >> /etc/sysctl.conf
sudo sysctl -p

# setup resolvconf for ubuntu 20
echo 'nameserver 8.8.4.4' >> /etc/resolv.conf
echo 'nameserver 8.8.8.8' >> /etc/resolv.conf
apt update
apt install resolvconf
systemctl restart resolvconf.service
echo 'nameserver 10.16.188.210' >> /etc/resolvconf/resolv.conf.d/head
echo 'nameserver 10.118.254.1' >> /etc/resolvconf/resolv.conf.d/head
echo 'nameserver 8.8.8.8' >> /etc/resolvconf/resolv.conf.d/head
echo 'nameserver 8.8.4.4' >> /etc/resolvconf/resolv.conf.d/head
resolvconf --enable-updates
resolvconf -u

#systemctl restart networking.service
systemctl restart systemd-networkd.service
while [ `systemctl is-active systemd-networkd` != 'active' ]; do echo 'waiting for network'; sleep 5; done

growpart /dev/sda 1 || :
resize2fs /dev/sda1 || :

# redundancy: https://github.com/vmware/container-service-extension/issues/432
systemctl restart systemd-networkd.service
while [ `systemctl is-active systemd-networkd` != 'active' ]; do echo 'waiting for network'; sleep 5; done

echo 'installing kubernetes'
export DEBIAN_FRONTEND=noninteractive
apt-get -q update -o Acquire::Retries=3 -o Acquire::http::No-Cache=True -o Acquire::http::Timeout=30 -o Acquire::https::No-Cache=True -o Acquire::https::Timeout=30 -o Acquire::ftp::Timeout=30
apt-get -q install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
# 'http://apt.kubernetes.io kubernetes-focal Release' does not have a Release file, so using xenial
echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" >> /etc/apt/sources.list.d/kubernetes.list
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
apt-get -q update -o Acquire::Retries=3 -o Acquire::http::No-Cache=True -o Acquire::http::Timeout=30 -o Acquire::https::No-Cache=True -o Acquire::https::Timeout=30 -o Acquire::ftp::Timeout=30
apt-get -q install -y kubernetes-cni=0.8.7-00
apt-get -q install -y docker-ce=5:19.03.15~3-0~ubuntu-focal docker-ce-cli=5:19.03.15~3-0~ubuntu-focal containerd.io
systemctl restart docker
while [ `systemctl is-active docker` != 'active' ]; do echo 'waiting for docker'; sleep 5; done
wget http://build-squid.eng.vmware.com/build/mts/release/bora-17654488/publish/lin64/kubernetes/debs/kubeadm_1.20.4+vmware.1-1_amd64.deb
wget http://build-squid.eng.vmware.com/build/mts/release/bora-17654488/publish/lin64/kubernetes/debs/kubectl_1.20.4+vmware.1-1_amd64.deb
wget http://build-squid.eng.vmware.com/build/mts/release/bora-17654488/publish/lin64/kubernetes/debs/kubelet_1.20.4+vmware.1-1_amd64.deb
# Installing all three at once since they depend on one another
apt install -y ./kubeadm_1.20.4+vmware.1-1_amd64.deb ./kubectl_1.20.4+vmware.1-1_amd64.deb ./kubelet_1.20.4+vmware.1-1_amd64.deb
systemctl restart kubelet
while [ `systemctl is-active kubelet` != 'active' ]; do echo 'waiting for kubelet'; sleep 5; done



echo 'installing required software for NFS'
apt-get -q install -y nfs-common nfs-kernel-server
systemctl stop nfs-kernel-server.service
systemctl disable nfs-kernel-server.service

# prevent updates to software that CSE depends on
apt-mark hold open-vm-tools
apt-mark hold docker
apt-mark hold docker-ce
apt-mark hold docker-ce-cli
apt-mark hold kubelet
apt-mark hold kubeadm
apt-mark hold kubectl
apt-mark hold kubernetes-cni
apt-mark hold nfs-common
apt-mark hold nfs-kernel-server

echo 'upgrading the system'
apt-get -q update -o Acquire::Retries=3 -o Acquire::http::No-Cache=True -o Acquire::http::Timeout=30 -o Acquire::https::No-Cache=True -o Acquire::https::Timeout=30 -o Acquire::ftp::Timeout=30
apt-get -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade

# Download weave.yml to /root/weave_v2-6-5.yml
export kubever=$(kubectl version --client | base64 | tr -d '\n')
/sbin/modprobe openvswitch
wget --no-verbose -O /root/antrea_0.11.3.yaml https://github.com/vmware-tanzu/antrea/releases/download/v0.11.3/antrea.yml

# /etc/machine-id must be empty so that new machine-id gets assigned on boot (in our case boot is vApp deployment)
# https://jaylacroix.com/fixing-ubuntu-18-04-virtual-machines-that-fight-over-the-same-ip-address/
truncate -s 0 /etc/machine-id
rm /var/lib/dbus/machine-id || :
ln -fs /etc/machine-id /var/lib/dbus/machine-id || : # dbus/machine-id is symlink pointing to /etc/machine-id

sync
sync
echo 'customization completed'
