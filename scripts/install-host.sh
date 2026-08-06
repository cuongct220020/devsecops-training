#!/usr/bin/env bash
#
# Automated host-side setup script for the DevSecOps Lab Series.
# Installs Terraform, Docker, and Trivy on Ubuntu/Debian hosts.
# KVM installation is documented in README.md and requires a system reboot.
#

set -euo pipefail

# Ensure script is run with sudo
if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: Please run this script with sudo." >&2
  exit 1
fi

echo "==> Updating package repository index..."
apt-get update

echo "==> Installing common utility packages..."
apt-get install -y gnupg software-properties-common curl ca-certificates wget lsb-release

# 1. Install Terraform
echo "==> Configuring HashiCorp repository & installing Terraform..."
wget -O- https://apt.releases.hashicorp.com/gpg | gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg --yes
echo "deb [signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(lsb_release -cs) main" \
  | tee /etc/apt/sources.list.d/hashicorp.list
apt-get update
apt-get install -y terraform

# 2. Install Docker
echo "==> Configuring Docker repository & installing Docker Engine..."
install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
chmod a+r /etc/apt/keyrings/docker.asc
echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  | tee /etc/apt/sources.list.d/docker.list > /dev/null
apt-get update
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Configure Docker permissions for the non-root sudoer user
if [[ -n "${SUDO_USER:-}" ]]; then
  echo "==> Adding user ${SUDO_USER} to 'docker' group..."
  usermod -aG docker "${SUDO_USER}"
fi

# 3. Install Trivy
echo "==> Configuring Aqua Security repository & installing Trivy..."
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor -o /usr/share/keyrings/trivy.gpg --yes
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" \
  | tee /etc/apt/sources.list.d/trivy.list
apt-get update
apt-get install -y trivy

echo ""
echo "=========================================================="
echo " Host Tools Installation Completed Successfully!"
echo "=========================================================="
echo "Installed:"
echo "  - Terraform: $(terraform --version | head -n 1)"
echo "  - Docker:    $(docker --version)"
echo "  - Trivy:     $(trivy --version | head -n 1)"
echo ""
echo "Next steps:"
echo "  1. Log out and log back in to apply group changes for Docker."
echo "  2. Refer to preps/README.md for KVM hypervisor setup."
echo "=========================================================="
