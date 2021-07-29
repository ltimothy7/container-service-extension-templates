#!/usr/bin/env bash

set -e

kubernetes_version=v1.20.4-vmware.1
etcd_image_version=v3.4.13-vmware.7
coredns_image_version=v1.7.0-vmware.8

# disable ipv6 to avoid possible connection errors
echo 'net.ipv6.conf.all.disable_ipv6 = 1' >> /etc/sysctl.conf
echo 'net.ipv6.conf.default.disable_ipv6 = 1' >> /etc/sysctl.conf
echo 'net.ipv6.conf.lo.disable_ipv6 = 1' >> /etc/sysctl.conf
sudo sysctl -p

# setup resolvconf for ubuntu 20 to access eng.vmware.com -- needed for vm to talk with vcd
echo 'nameserver 8.8.4.4' >> /etc/resolv.conf
echo 'nameserver 8.8.8.8' >> /etc/resolv.conf
apt update
apt install resolvconf
systemctl restart resolvconf.service
while [ `systemctl is-active resolvconf` != 'active' ]; do echo 'waiting for resolvconf'; sleep 5; done
echo 'nameserver 10.16.188.210' >> /etc/resolvconf/resolv.conf.d/head
echo 'nameserver 10.118.254.1' >> /etc/resolvconf/resolv.conf.d/head
echo 'nameserver 8.8.8.8' >> /etc/resolvconf/resolv.conf.d/head
echo 'nameserver 8.8.4.4' >> /etc/resolvconf/resolv.conf.d/head
resolvconf --enable-updates
resolvconf -u

# TODO: uncomment out once eng.vmware.com access no longer needed
## setup resolvconf for ubuntu 20
#echo 'nameserver 8.8.8.8' >> /etc/resolv.conf
#apt update
#apt install resolvconf
#systemctl restart resolvconf.service
#while [ `systemctl is-active resolvconf` != 'active' ]; do echo 'waiting for resolvconf'; sleep 5; done
#echo 'nameserver 8.8.8.8' >> /etc/resolvconf/resolv.conf.d/head
#resolvconf -u

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
# http://apt.kubernetes.io kubernetes-focal and bionic release do not have a Release file, so using xenial
# Kubernetes documentation also shows to use xenial for kubeadm: https://kubernetes.io/docs/setup/production-environment/tools/kubeadm/install-kubeadm/
echo "deb http://apt.kubernetes.io/ kubernetes-xenial main" >> /etc/apt/sources.list.d/kubernetes.list
add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/ubuntu focal stable"
apt-get -q update -o Acquire::Retries=3 -o Acquire::http::No-Cache=True -o Acquire::http::Timeout=30 -o Acquire::https::No-Cache=True -o Acquire::https::Timeout=30 -o Acquire::ftp::Timeout=30
apt-get -q install -y kubernetes-cni=0.8.7-00 # kubernetes-cni is needed for kubelet
apt-get -q install -y docker-ce=5:19.03.15~3-0~ubuntu-focal docker-ce-cli=5:19.03.15~3-0~ubuntu-focal containerd.io
systemctl restart docker
while [ `systemctl is-active docker` != 'active' ]; do echo 'waiting for docker'; sleep 5; done
wget https://github.com/vmware/container-service-extension-templates/raw/tkgm/tkgm_build_artifacts/1_3_0/kubeadm_1.20.4%2Bvmware.1-1_amd64.deb
wget https://github.com/vmware/container-service-extension-templates/raw/tkgm/tkgm_build_artifacts/1_3_0/kubectl_1.20.4%2Bvmware.1-1_amd64.deb
wget https://github.com/vmware/container-service-extension-templates/raw/tkgm/tkgm_build_artifacts/1_3_0/kubelet_1.20.4%2Bvmware.1-1_amd64.deb
# Installing all three at once since they depend on one another
apt install -y ./kubeadm_1.20.4+vmware.1-1_amd64.deb ./kubectl_1.20.4+vmware.1-1_amd64.deb ./kubelet_1.20.4+vmware.1-1_amd64.deb
systemctl restart kubelet
while [ `systemctl is-active kubelet` != 'active' ]; do echo 'waiting for kubelet'; sleep 5; done

# Install kubernetes components, coredns, and antrea binary
docker pull projects.registry.vmware.com/tkg/antrea/antrea-debian:v0.11.3_vmware.2
docker pull projects.registry.vmware.com/tkg/coredns:v1.7.0_vmware.8
docker pull projects.registry.vmware.com/tkg/etcd:v3.4.13_vmware.7
docker pull projects.registry.vmware.com/tkg/kube-apiserver:v1.20.4_vmware.1
docker pull projects.registry.vmware.com/tkg/kube-controller-manager:v1.20.4_vmware.1
docker pull projects.registry.vmware.com/tkg/kube-proxy:v1.20.4_vmware.1
docker pull projects.registry.vmware.com/tkg/kube-scheduler:v1.20.4_vmware.1
docker pull projects.registry.vmware.com/tkg/pause:3.2

docker tag projects.registry.vmware.com/tkg/antrea/antrea-debian:v0.11.3_vmware.2 projects.registry.vmware.com/tkg/antrea/antrea-debian:v0.11.3-vmware.2
docker tag projects.registry.vmware.com/tkg/coredns:v1.7.0_vmware.8 projects.registry.vmware.com/tkg/coredns:$coredns_image_version
docker tag projects.registry.vmware.com/tkg/etcd:v3.4.13_vmware.7 projects.registry.vmware.com/tkg/etcd:$etcd_image_version
docker tag projects.registry.vmware.com/tkg/kube-proxy:v1.20.4_vmware.1 projects.registry.vmware.com/tkg/kube-proxy:$kubernetes_version
docker tag projects.registry.vmware.com/tkg/kube-apiserver:v1.20.4_vmware.1 projects.registry.vmware.com/tkg/kube-apiserver:$kubernetes_version
docker tag projects.registry.vmware.com/tkg/kube-controller-manager:v1.20.4_vmware.1 projects.registry.vmware.com/tkg/kube-controller-manager:$kubernetes_version
docker tag projects.registry.vmware.com/tkg/kube-scheduler:v1.20.4_vmware.1 projects.registry.vmware.com/tkg/kube-scheduler:$kubernetes_version

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

# Download antrea.yml to /root/antrea_0.11.3.yml
export kubever=$(kubectl version --client | base64 | tr -d '\n')
/sbin/modprobe openvswitch
wget --no-verbose -O /root/antrea_0.11.3.yml https://github.com/vmware-tanzu/antrea/releases/download/v0.11.3/antrea.yml

# Download cpi and csi yaml
wget -O /root/vcloud-basic-auth.yaml https://raw.githubusercontent.com/vmware/cloud-provider-for-cloud-director/main/manifests/vcloud-basic-auth.yaml
wget -O /root/vcloud-configmap.yaml https://raw.githubusercontent.com/vmware/cloud-provider-for-cloud-director/main/manifests/vcloud-configmap.yaml
wget -O /root/cloud-director-ccm.yaml https://raw.githubusercontent.com/vmware/cloud-provider-for-cloud-director/main/manifests/cloud-director-ccm.yaml
wget -O /root/csi-driver.yaml https://github.com/vmware/cloud-director-named-disk-csi-driver/raw/main/manifests/csi-driver.yaml
wget -O /root/csi-controller.yaml https://github.com/vmware/cloud-director-named-disk-csi-driver/raw/main/manifests/csi-controller.yaml
wget -O /root/csi-node.yaml https://github.com/vmware/cloud-director-named-disk-csi-driver/raw/main/manifests/csi-node.yaml

# /etc/machine-id must be empty so that new machine-id gets assigned on boot (in our case boot is vApp deployment)
# https://jaylacroix.com/fixing-ubuntu-18-04-virtual-machines-that-fight-over-the-same-ip-address/
truncate -s 0 /etc/machine-id
rm /var/lib/dbus/machine-id || :
ln -fs /etc/machine-id /var/lib/dbus/machine-id || : # dbus/machine-id is symlink pointing to /etc/machine-id

echo 'deleting downloaded files'
rm *.tar.gz* || :
rm *.deb* || :

# enable kubelet service
systemctl enable kubelet

# create /root/kubeadm-defaults.conf
echo "---
apiVersion: kubeadm.k8s.io/v1beta2
kind: InitConfiguration
bootstrapTokens:
- groups:
  - system:bootstrappers:kubeadm:default-node-token
  ttl: 0s
  usages:
  - signing
  - authentication
nodeRegistration:
  kubeletExtraArgs:
    cloud-provider: external
---
apiVersion: kubeadm.k8s.io/v1beta2
kind: ClusterConfiguration
dns:
  type: CoreDNS
  imageRepository: projects.registry.vmware.com/tkg
  imageTag: $coredns_image_version
etcd:
  local:
    imageRepository: projects.registry.vmware.com/tkg
    imageTag: $etcd_image_version
networking:
  serviceSubnet: SERVICE_SUBNET_CIDR
  podSubnet: POD_SUBNET_CIDR
imageRepository: projects.registry.vmware.com/tkg
kubernetesVersion: $kubernetes_version
---" > /root/kubeadm-defaults.conf

echo "---
apiVersion: kubeadm.k8s.io/v1beta2
kind: JoinConfiguration
caCertPath: /etc/kubernetes/pki/ca.crt
discovery:
  bootstrapToken:
    apiServerEndpoint: IP_PORT
    token: TOKEN
    unsafeSkipCAVerification: false
    caCertHashes: [DISCOVERY_CA_CERT_HASH]
  timeout: 5m0s
nodeRegistration:
  kubeletExtraArgs:
    cloud-provider: external
" > /root/kubeadm-defaults-join.conf

sync
sync
echo 'customization completed'
