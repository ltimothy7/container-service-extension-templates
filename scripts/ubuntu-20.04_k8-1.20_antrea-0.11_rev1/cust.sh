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
#systemctl restart networking.service
#while [ `systemctl is-active networking` != 'active' ]; do echo 'waiting for network'; sleep 5; done
systemctl restart systemd-networkd.service
while [ `systemctl is-active systemd-networkd` != 'active' ]; do echo 'waiting for network'; sleep 5; done

echo 'installing kubernetes'
export DEBIAN_FRONTEND=noninteractive
apt-get -q update -o Acquire::Retries=3 -o Acquire::http::No-Cache=True -o Acquire::http::Timeout=30 -o Acquire::https::No-Cache=True -o Acquire::https::Timeout=30 -o Acquire::ftp::Timeout=30
apt-get -q install -y apt-transport-https ca-certificates curl software-properties-common
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo apt-key add -
curl -s https://packages.cloud.google.com/apt/doc/apt-key.gpg | apt-key add -
#cat <<EOF > /etc/apt/sources.list.d/kubernetes.list
#deb http://apt.kubernetes.io/ kubernetes-xenial main
#EOF
#add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu $(lsb_release -cs) stable"
#apt-get -q update -o Acquire::Retries=3 -o Acquire::http::No-Cache=True -o Acquire::http::Timeout=30 -o Acquire::https::No-Cache=True -o Acquire::https::Timeout=30 -o Acquire::ftp::Timeout=30
wget http://build-squid.eng.vmware.com/build/mts/release/bora-17654488/publish/lin64/kubernetes/executables/kubeadm-linux-v1.20.4+vmware.1.gz
wget http://build-squid.eng.vmware.com/build/mts/release/bora-17654488/publish/lin64/kubernetes/executables/kubectl-linux-v1.20.4+vmware.1.gz
wget http://build-squid.eng.vmware.com/build/mts/release/bora-17654488/publish/lin64/kubernetes/executables/kubelet-linux-v1.20.4+vmware.1.gz
gzip -d kubeadm-linux-v1.20.4+vmware.1.gz kubectl-linux-v1.20.4+vmware.1.gz kubelet-linux-v1.20.4+vmware.1.gz
chmod +x kubeadm-linux-v1.20.4+vmware.1.gz
chmod +x kubectl-linux-v1.20.4+vmware.1.gz
chmod +x kubelet-linux-v1.20.4+vmware.1.gz
cp kubeadm-linux-v1.20.4+vmware.1.gz /usr/local/bin/kubeadm
cp kubectl-linux-v1.20.4+vmware.1.gz /usr/local/bin/kubectl
cp kubelet-linux-v1.20.4+vmware.1.gz /usr/local/bin/kubelet

apt-get -q install -y docker-ce=5:19.03.15~3-0~ubuntu-focal
#apt-get -q install -y kubelet=1.20.6-00 kubeadm=1.20.6-00 kubectl=1.20.6-00 kubernetes-cni=0.8.7-00
systemctl restart docker
while [ `systemctl is-active docker` != 'active' ]; do echo 'waiting for docker'; sleep 5; done

echo 'installing required software for NFS'
apt-get -q install -y nfs-common nfs-kernel-server
systemctl stop nfs-kernel-server.service
systemctl disable nfs-kernel-server.service

# prevent updates to software that CSE depends on
apt-mark hold open-vm-tools
apt-mark hold docker-ce
apt-mark hold kubelet
apt-mark hold kubeadm
apt-mark hold kubectl
#apt-mark hold kubernetes-cni
apt-mark hold nfs-common
apt-mark hold nfs-kernel-server

echo 'upgrading the system'
apt-get -q update -o Acquire::Retries=3 -o Acquire::http::No-Cache=True -o Acquire::http::Timeout=30 -o Acquire::https::No-Cache=True -o Acquire::https::Timeout=30 -o Acquire::ftp::Timeout=30
apt-get -y -q -o Dpkg::Options::="--force-confdef" -o Dpkg::Options::="--force-confold" dist-upgrade

# Download weave.yml to /root/weave_v2-6-5.yml
export kubever=$(kubectl version --client | base64 | tr -d '\n')
/sbin/modprobe openvswitch
/sbin/lsmod | grep openvswitch
wget --no-verbose -O /root/antrea_0.11.3.yaml https://github.com/vmware-tanzu/antrea/releases/download/v0.11.3/antrea.yml
#wget --no-verbose -O /root/weave_v2-6-5.yml "https://cloud.weave.works/k8s/net?k8s-version=$kubever&v=2.6.5"

# /etc/machine-id must be empty so that new machine-id gets assigned on boot (in our case boot is vApp deployment)
# https://jaylacroix.com/fixing-ubuntu-18-04-virtual-machines-that-fight-over-the-same-ip-address/
truncate -s 0 /etc/machine-id
rm /var/lib/dbus/machine-id || :
ln -fs /etc/machine-id /var/lib/dbus/machine-id || : # dbus/machine-id is symlink pointing to /etc/machine-id

sync
sync
echo 'customization completed'
