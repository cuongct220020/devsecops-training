# DevSecOps Lab — Execution Results

Ran end-to-end on a local KVM/libvirt host (Ubuntu 24.04, 8 vCPU / 31 GiB) on 2026-06-14.

## Infrastructure provisioned
Two Ubuntu 24.04 VMs via Terraform + the `dmacvicar/libvirt` provider:

| Node | Role | IP | vCPU / RAM |
|------|------|----|-----------|
| `devsecops-node1-master` | OpenSCAP target + RKE2 master | 192.168.122.79 | 2 / 4 GiB |
| `devsecops-node2-worker` | RKE2 worker | 192.168.122.88 | 2 / 3 GiB |

## Lab 1 — OS hardening (OpenSCAP, CIS L1 Server)
Scanned with SCAP Security Guide v0.1.81 (`ssg-ubuntu2404-ds.xml`), profile `cis_level1_server`.

| Scan | Pass | Fail | Pass % |
|------|------|------|--------|
| Baseline (vanilla) | 233 | 110 | **67.9 %** |
| After `--remediate` | 331 | 22 | **93.8 %** |

Reports: `part-1-os-hardening/reports/report-{baseline,hardened}.html`.
Remediation was run detached with an SSH-allow safety net so firewall changes couldn't lock the session out.

## Lab 2 — Kubernetes platform (RKE2 + kube-bench)
RKE2 **v1.35.5+rke2r2**, `profile: cis`, 1 master + 1 worker, both `Ready`.

kube-bench v0.15.6, benchmark `rke2-cis-1.24`:

| Target | PASS | FAIL | WARN |
|--------|------|------|------|
| master | 43 | 3 | 8 |
| node   | 5  | 7 | 7 |

- Control-plane pod manifests are `600 root:root`; secrets are **encrypted at rest** (aescbc).
- The FAILs are tooling artifacts, not real exposure: e.g. check 1.1.1 uses `op: eq, value: "644"` and rejects the actual `600` perms even though 600 is *more* restrictive; the node `4.2.x` kubelet FAILs come from kube-bench reading the process command line while RKE2 supplies those settings via a config file. Following kube-bench's `chmod 644` advice would *weaken* security, so it was deliberately not applied.

Reports: `part-2-k8s-cluster/reports/kb-{master,node}.txt`.

## Lab 3 — Application security (Trivy + Docker)
| Image | Base | Size | CRITICAL | HIGH | Total CVEs |
|-------|------|------|----------|------|-----------|
| `todo-app:insecure` | python:3.9 | 1.67 GB | 188 | 982 | **5,565** |
| `todo-app:secure` | python:3.11-slim (multi-stage) | 249 MB | 4 | 27 | **154** |

≈ **97 % fewer CVEs**, 85 % smaller image.
Dockerfile misconfig (Trivy): insecure = 3 findings incl. **DS-0031 CRITICAL secret in ENV** + DS-0002 root user → secure = 1 (only LOW "no HEALTHCHECK").
Reports: `part-3-app-security/reports/trivy-*-image.txt`.

## Lab 4 — Secure deployment (Trivy config + RKE2)
Manifest misconfig (Trivy `config`, KSV checks):

| Manifest | HIGH | MEDIUM | LOW | Total |
|----------|------|--------|-----|-------|
| `deployment.yaml` (baseline) | 3 | 3 | 11 | **17** |
| `deployment.secure.yaml` + `service.yaml` | 0 | 0 | 3 | **3** |

Deployed to the cluster (image imported into containerd on both nodes):
- `deployment todo-deployment` **2/2 Running**, `service todo-service` NodePort `30080`.
- Runtime checks confirmed: container runs as **uid 999**, **read-only root** blocks `/app` writes, `/tmp` (emptyDir) writable, `SECRET_KEY` sourced from a Kubernetes Secret.
- `GET /healthz/` → **200** via `http://192.168.122.79:30080/healthz/` and from localhost on both nodes.

Reports: `part-4-k8s-deployment/reports/trivy-{baseline,hardened}-manifest.txt`.

## Fixes applied during execution (repo updated to match)
- **Terraform provider**: pinned `dmacvicar/libvirt` to `>= 0.7.0, < 0.9.0` — 0.9.x is a schema rewrite (`source`/`base_volume_id`/`size` removed).
- **Multi-node**: Part 1 now provisions 2 VMs (master + worker) via `for_each`; SSH key default → `~/.ssh/id_ed25519.pub`.
- **RKE2 config**: `profile: "cis-1.23"` → `profile: "cis"` (old value rejected by v1.35); removed `selinux: true` (RHEL-only; Ubuntu uses AppArmor).
- **Deployment**: added `DJANGO_ALLOWED_HOSTS="*"` — with `DEBUG` off Django returned HTTP 400 to the probes (pod IP not an allowed Host), causing a restart loop.

## Known caveats
- The hardened pod's `readOnlyRootFilesystem` means the demo SQLite DB at `/app/db.sqlite3` is unwritable, so `GET /` returns 500 (DB write). `/healthz/` needs no DB and returns 200. For real use, point Django at an external DB or the `/app/data` emptyDir.
- External NodePort access works on the master node IP; reaching the worker node IP from outside is filtered by Calico's host policy (NodePort isn't a Calico failsafe port like 22/6443). Intra-node and master-IP access are unaffected.
