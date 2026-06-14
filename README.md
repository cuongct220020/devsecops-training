# DevSecOps Hands-On Lab Series

A 100% hands-on lab that walks through building, deploying, and securing an
application across three layers: **OS**, **Platform (Kubernetes)**, and
**Application**. Each lab ships a deliberately *insecure* starting state plus a
remediated reference solution so you can scan, fix, and re-scan.

> Full step-by-step instructions live in [`docs/plan.md`](docs/plan.md). This
> README is the quick map of what's in the repo and how the pieces fit.

## Repository layout

```text
devsecops-lab/
├── part-1-os-hardening/        # Terraform + libvirt → Ubuntu 24.04 VM; OpenSCAP CIS audit
│   ├── main.tf  variables.tf  outputs.tf
│   └── cloud-init/             # vanilla cloud-init (kept stock for a realistic baseline)
├── part-2-k8s-cluster/         # RKE2 (CIS profile) 1 master + 1 worker; kube-bench audit
│   ├── rke2-config/config.yaml.{master,worker}
│   └── install.sh
├── part-3-app-security/        # Django "todo" app; Trivy fs/image scanning
│   ├── app/                    # Django project (todo/) + todos app
│   ├── Dockerfile              # INSECURE baseline (scan target)
│   ├── Dockerfile.secure       # remediated multi-stage, non-root image
│   ├── docker-compose.yml  requirements.txt  .env.example
└── part-4-k8s-deployment/      # Ship the secure image to RKE2; Trivy config scanning
    ├── deployment.yaml         # UNOPTIMIZED baseline (scan target)
    ├── deployment.secure.yaml  # hardened: securityContext + resources + probes
    └── service.yaml            # NodePort exposure
```

## The four labs at a glance

| # | Layer | Tool | What you do |
|---|-------|------|-------------|
| 1 | OS | OpenSCAP | `terraform apply` an Ubuntu 24.04 VM, scan with the CIS profile, `--remediate`, re-scan |
| 2 | Platform | kube-bench | Install RKE2 in the `cis-1.23` profile, run kube-bench, fix warnings |
| 3 | Application | Trivy | Scan the legacy Dockerfile/code, move secrets to env, build a slim non-root multi-stage image |
| 4 | Deployment | Trivy config | Scan the bare manifest, add `securityContext`/resources, expose via NodePort |

## Quick start per lab

**Lab 1 — OS:**
```bash
cd part-1-os-hardening
terraform init && terraform apply -auto-approve   # outputs the VM IP + ssh command
```
Then SSH in and follow `docs/plan.md` §1.3 (OpenSCAP install, baseline scan,
`--remediate`, re-scan).

**Lab 2 — Kubernetes (run on each node):**
```bash
cd part-2-k8s-cluster
sudo ./install.sh master      # on the master
# grab the token: sudo cat /var/lib/rancher/rke2/server/node-token
# edit rke2-config/config.yaml.worker (server + token), then on the worker:
sudo ./install.sh worker
```

**Lab 3 — Application:**
```bash
cd part-3-app-security
cp .env.example .env          # then set a real SECRET_KEY
trivy fs .                    # scan the legacy state (secrets + CVEs)
docker build -t todo-app:insecure .                       # baseline
docker build -f Dockerfile.secure -t todo-app:secure .    # remediated
trivy image todo-app:secure   # CVEs drop, no root, no leaked secret
# local run:
docker compose up --build
```

**Lab 4 — Deployment (on the RKE2 master):**
```bash
cd part-4-k8s-deployment
trivy config deployment.yaml          # flags the missing securityContext
kubectl create secret generic todo-secrets \
  --from-literal=SECRET_KEY="$(python3 -c 'from django.core.management.utils import get_random_secret_key; print(get_random_secret_key())')"
kubectl apply -f deployment.secure.yaml
kubectl apply -f service.yaml
kubectl get pods && kubectl get svc todo-service
```

## Prerequisites

- **Lab 1:** KVM/libvirt, Terraform ≥ 1.5, the `dmacvicar/libvirt` provider, an SSH keypair.
- **Lab 2:** Two VMs (ideally the hardened ones from Lab 1) with network reachability on port 9345.
- **Labs 3–4:** Docker, Trivy, and `kubectl` access to the RKE2 cluster.

## Notes

- Secrets are **never** committed: `.env` is gitignored; Kubernetes pulls
  `SECRET_KEY` from a Secret. Only `.env.example` is tracked.
- The hardened deployment sets `readOnlyRootFilesystem: true`, so writable
  `emptyDir` volumes are mounted at `/tmp` and `/app/data`. The demo uses
  SQLite; for anything beyond the lab, point Django at an external database.
