# Part 1 — OS Provisioning & Hardening (OpenSCAP / CIS)

Provision Ubuntu 24.04 VMs on local KVM with Terraform, scan them against the
CIS Level 1 Server benchmark with OpenSCAP, auto-remediate, and re-scan to
measure the improvement.

> This part provisions **two** VMs (`node1-master`, `node2-worker`). node1 is
> the OpenSCAP hardening target here and the RKE2 master in Part 2; node2 is the
> Part 2 worker. The OpenSCAP workflow below is run on node1.

## Files
```
part-1-os-hardening/
├── main.tf            # libvirt provider, base image, per-node disk/cloudinit/domain (for_each)
├── variables.tf       # node map, image URL, SSH key path, pool/network names
├── outputs.tf         # node name → IP, ready-to-run ssh commands
├── cloud-init/
│   ├── user-data.yaml     # minimal: inject SSH key only (kept vanilla on purpose)
│   └── network-config.yaml
└── reports/           # OpenSCAP HTML reports produced by the scans
```

## Prerequisites (on the KVM host)
```bash
# libvirt daemon running + a 'default' storage pool and network, active
sudo systemctl enable --now libvirtd
export LIBVIRT_DEFAULT_URI=qemu:///system
virsh net-list --all     # 'default' must be active
virsh pool-list --all    # 'default' must be active
# an SSH keypair (variables.tf defaults to ~/.ssh/id_ed25519.pub)
ls ~/.ssh/id_ed25519.pub
```
If the `default` net/pool don't exist, create them (dir pool at
`/var/lib/libvirt/images`, NAT network on `virbr0`/`192.168.122.0/24`).

## 1. Provision the VMs
```bash
cd part-1-os-hardening
export LIBVIRT_DEFAULT_URI=qemu:///system
terraform init
terraform apply -auto-approve
```
`terraform apply` downloads the Ubuntu 24.04 cloud image (~600 MB, cached as the
base volume), clones a CoW disk per node, and boots both. Output:
```
nodes = {
  "node1-master" = "192.168.122.79"
  "node2-worker" = "192.168.122.88"
}
ssh_commands = { "node1-master" = "ssh labadmin@192.168.122.79", ... }
```

> ⚠️ **Provider pin.** `main.tf` pins `dmacvicar/libvirt` to `>= 0.7.0, < 0.9.0`.
> The 0.9.x line is a schema rewrite that removes `source` / `base_volume_id` /
> `size` / `format` on `libvirt_volume`; the classic HCL here needs 0.8.x.

Wait for cloud-init and confirm SSH (the VMs use NAT; the host reaches them
directly):
```bash
ssh -i ~/.ssh/id_ed25519 -o StrictHostKeyChecking=no labadmin@192.168.122.79 \
  'cloud-init status --wait; hostname; . /etc/os-release; echo $PRETTY_NAME'
# -> status: done / node1-master / Ubuntu 24.04.4 LTS
```
Tip: add host aliases to `~/.ssh/config` (`Host lab-master` → 192.168.122.79,
user labadmin, IdentityFile id_ed25519) so the rest is just `ssh lab-master`.

## 2. Install OpenSCAP + CIS content (on node1)
The Ubuntu `ssg-base` apt package does **not** ship the 24.04 datastream, so
pull the official SCAP Security Guide release:
```bash
ssh lab-master
sudo apt-get update
sudo apt-get install -y openscap-scanner unzip

# Download the latest SSG release (ships ssg-ubuntu2404-ds.xml)
cd /tmp
TAG=$(curl -s https://api.github.com/repos/ComplianceAsCode/content/releases/latest \
      | grep -oP '"tag_name":\s*"\K[^"]+')          # e.g. v0.1.81
curl -sSL -o ssg.zip \
  "https://github.com/ComplianceAsCode/content/releases/download/${TAG}/scap-security-guide-${TAG#v}.zip"
unzip -q ssg.zip
sudo mkdir -p /usr/share/xml/scap/ssg/content
sudo cp scap-security-guide-*/ssg-ubuntu2404-ds.xml /usr/share/xml/scap/ssg/content/

# Confirm the CIS L1 Server profile is present
oscap info /usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml | grep -i cis
```

## 3. Baseline scan
```bash
PROFILE=xccdf_org.ssgproject.content_profile_cis_level1_server
DS=/usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml
sudo oscap xccdf eval --profile $PROFILE \
  --results-arf /tmp/arf-baseline.xml \
  --report /tmp/report-baseline.html $DS
# exit code 2 just means "some rules failed" — expected on a vanilla OS
```
Baseline observed: **233 pass / 110 fail (67.9%)**.

## 4. Remediate — run it detached so you can't get locked out
CIS hardening touches SSH and can create a firewall. Run it with `nohup` and
have the *same* script re-open SSH at the end, so a dropped connection can
neither abort the run nor lock you out:
```bash
cat > /tmp/remediate.sh <<'EOF'
#!/bin/bash
PROFILE=xccdf_org.ssgproject.content_profile_cis_level1_server
DS=/usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml
sudo oscap xccdf eval --remediate --profile $PROFILE \
  --results-arf /tmp/arf-remediate.xml $DS > /tmp/remediate.log 2>&1
# safety net: never lock SSH out from the host network
command -v ufw >/dev/null && { sudo ufw allow from 192.168.122.0/24 to any port 22 proto tcp; sudo ufw allow OpenSSH; }
sudo systemctl enable --now ssh; sudo systemctl restart ssh
echo "DONE" >> /tmp/remediate.log
EOF
chmod +x /tmp/remediate.sh
nohup /tmp/remediate.sh >/dev/null 2>&1 &

# poll from the host until it finishes (reconnect-safe)
while ! ssh lab-master 'tail -1 /tmp/remediate.log' | grep -q DONE; do sleep 10; done
```
The AIDE install/init is the slow step. After it, confirm the firewall didn't
block SSH (`sudo nft list ruleset | grep -i 'hook input'` → policy `accept`).

## 5. Re-scan & compare
```bash
sudo oscap xccdf eval --profile $PROFILE \
  --report /tmp/report-hardened.html $DS
```
Hardened observed: **331 pass / 22 fail (93.8%)**. Pull the reports to the host:
```bash
# (hardened report is root-owned; chmod first)
ssh lab-master 'sudo chmod 644 /tmp/report-hardened.html'
scp lab-master:/tmp/report-baseline.html lab-master:/tmp/report-hardened.html reports/
```

## Result
| Scan | Pass | Fail | Pass % |
|------|------|------|--------|
| Baseline | 233 | 110 | 67.9% |
| Hardened | 331 | 22 | 93.8% |

The remaining ~22 fails are mostly manual/structural items auto-remediation
can't fix (separate `/tmp` `/var` partitions, bootloader password, AIDE cron).

## Teardown
```bash
terraform destroy -auto-approve   # removes both VMs, disks, cloudinit ISOs
```
