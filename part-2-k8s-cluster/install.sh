#!/usr/bin/env bash
#
# RKE2 installer for the DevSecOps lab (Lab 2.2).
# Installs RKE2 in the CIS-hardened profile on either a master or worker node.
#
# Usage:
#   sudo ./install.sh master
#   sudo ./install.sh worker
#
# The matching rke2-config/config.yaml.<role> is copied to
# /etc/rancher/rke2/config.yaml before the service is started. Edit that file
# (server address, token, tls-san) before running for the worker.

set -euo pipefail

ROLE="${1:-}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CONFIG_DIR="/etc/rancher/rke2"

if [[ "${EUID}" -ne 0 ]]; then
  echo "ERROR: run as root (sudo)." >&2
  exit 1
fi

case "${ROLE}" in
  master) INSTALL_TYPE="server"; SVC="rke2-server.service"; SRC="config.yaml.master" ;;
  worker) INSTALL_TYPE="agent";  SVC="rke2-agent.service";  SRC="config.yaml.worker" ;;
  *)
    echo "Usage: sudo $0 {master|worker}" >&2
    exit 1
    ;;
esac

echo "==> Installing RKE2 (${INSTALL_TYPE}) ..."
curl -sfL https://get.rke2.io | INSTALL_RKE2_TYPE="${INSTALL_TYPE}" sh -

echo "==> Applying CIS hardening prerequisites ..."
# The CIS profile requires the etcd user and the kernel hardening sysctls.
if ! id etcd &>/dev/null; then
  useradd -r -c "etcd user" -s /sbin/nologin -M etcd || true
fi
if [[ -f /usr/local/share/rke2/rke2-cis-sysctl.conf ]]; then
  cp -f /usr/local/share/rke2/rke2-cis-sysctl.conf /etc/sysctl.d/60-rke2-cis.conf
  sysctl -p /etc/sysctl.d/60-rke2-cis.conf
fi

echo "==> Writing ${CONFIG_DIR}/config.yaml from ${SRC} ..."
mkdir -p "${CONFIG_DIR}"
cp -f "${SCRIPT_DIR}/rke2-config/${SRC}" "${CONFIG_DIR}/config.yaml"
chmod 0600 "${CONFIG_DIR}/config.yaml"

echo "==> Enabling and starting ${SVC} ..."
systemctl enable "${SVC}" --now

cat <<EOF

==> Done.

Service: ${SVC}
Check status:   systemctl status ${SVC}
Logs:           journalctl -u ${SVC} -f

EOF

if [[ "${ROLE}" == "master" ]]; then
  cat <<EOF
Master next steps:
  1. Node join token (give this to workers):
       sudo cat /var/lib/rancher/rke2/server/node-token
  2. Use kubectl:
       export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
       export PATH=\$PATH:/var/lib/rancher/rke2/bin
       kubectl get nodes
EOF
fi
