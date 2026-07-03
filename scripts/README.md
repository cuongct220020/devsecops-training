# DevSecOps Lab Preparation Guide

This directory contains the installation steps and automation scripts to configure your host machine and guest VMs for all parts of the DevSecOps lab series.

---

## 💻 1. Host Machine Tooling (KVM, Terraform, Docker, Trivy)

These tools must be installed on your local host (management machine).

### A. KVM/Libvirt Hypervisor
Install the hypervisor packages, start the daemon, and configure the user group memberships:
```bash
# Update package list and install libvirt/QEMU packages
sudo apt-get update
sudo apt-get install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virtinst libvirt-daemon

# Enable and start the libvirt service
sudo systemctl enable --now libvirtd

# Add current user to the libvirt and kvm groups to run commands without sudo
sudo usermod -aG libvirt $USER
sudo usermod -aG kvm $USER
```
*Note: You must log out and log back in (or run `newgrp libvirt` and `newgrp kvm`) for group modifications to take effect.*

#### Activate Default Network and Storage Pool (Required for Lab 1)
Ensure the `default` virtual network (NAT on 192.168.122.0/24) and `default` storage pool (directory pool at `/var/lib/libvirt/images`) are active and set to autostart:
```bash
# Configure Default Network
sudo virsh net-start default || true
sudo virsh net-autostart default || true

# Configure Default Storage Pool
sudo virsh pool-define-as default dir --target /var/lib/libvirt/images || true
sudo virsh pool-start default || true
sudo virsh pool-autostart default || true
```

---

### B. HashiCorp Terraform CLI
Install the official HashiCorp repository and the Terraform package:
```bash
sudo apt-get update && sudo apt-get install -y gnupg software-properties-common curl

# Add the GPG key
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor | sudo tee /usr/share/keyrings/hashicorp-archive-keyring.gpg > /dev/null

# Add the repository
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" | sudo tee /etc/apt/sources.list.d/hashicorp.list

# Update & install
sudo apt-get update && sudo apt-get install -y terraform
```

---

### C. Docker Engine & Docker Compose
Install the official Docker repository, the Docker runtime, and the compose plugin:
```bash
# Add Docker's official GPG key:
sudo apt-get update
sudo apt-get install -y ca-certificates curl
sudo install -m 0755 -d /etc/apt/keyrings
sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
sudo chmod a+r /etc/apt/keyrings/docker.asc

# Add the repository to Apt sources:
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" | \
  sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
sudo apt-get update

# Install Docker components
sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Allow running docker commands without sudo
sudo usermod -aG docker $USER
```
*Note: Log out and log back in to apply docker group permissions.*

---

### D. Trivy Vulnerability Scanner
Install the Aqua Security Trivy package repository and binary:
```bash
sudo apt-get install -y wget apt-transport-https gnupg lsb-release
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/trivy.list
sudo apt-get update && sudo apt-get install -y trivy
```

---

## 🖥️ 2. Remote VM/Node Tooling (OpenSCAP, Kube-bench, kubectl)

These steps are executed on the VMs created in Lab 1 (using SSH).

### A. OpenSCAP (Run on Master VM)
Used for scanning and hardening the OS against CIS Benchmarks in Lab 1:
```bash
# Install scanner & zip packages
sudo apt-get update && sudo apt-get install -y openscap-scanner unzip

# Download compliance content (SCAP Security Guide) with Ubuntu 24.04 support
cd /tmp
TAG=$(curl -s https://api.github.com/repos/ComplianceAsCode/content/releases/latest \
      | grep -oP '"tag_name":\s*"\K[^"]+')
curl -sSL -o ssg.zip "https://github.com/ComplianceAsCode/content/releases/download/${TAG}/scap-security-guide-${TAG#v}.zip"
unzip -q ssg.zip
sudo mkdir -p /usr/share/xml/scap/ssg/content
sudo cp scap-security-guide-*/ssg-ubuntu2404-ds.xml /usr/share/xml/scap/ssg/content/
```

---

### B. Kube-bench (Run on Master/Worker VMs)
Used for scanning the Kubernetes cluster control-plane and nodes against CIS Benchmarks in Lab 2:
```bash
cd /tmp
TAG=v0.15.6; VER=0.15.6
curl -sSL -o kb.tgz "https://github.com/aquasecurity/kube-bench/releases/download/${TAG}/kube-bench_${VER}_linux_amd64.tar.gz"
mkdir kb && tar -xzf kb.tgz -C kb && cd kb
# The executable ./kube-bench is now ready to run
```

---

### C. kubectl Client Tooling (Run on Master VM)
Already bundled by RKE2 in `/var/lib/rancher/rke2/bin/kubectl`. To expose it globally:
```bash
sudo ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
```
To run it on the host machine, copy the `/etc/rancher/rke2/rke2.yaml` file from the master VM to `~/.kube/config` on the host, and change `server: https://127.0.0.1:6443` to point to the master VM's IP address.
