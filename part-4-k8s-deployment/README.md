# Part 4 — Secure Deployment on Kubernetes (Trivy config / RKE2)

Ship the `todo-app:secure` image from Part 3 onto the RKE2 cluster from Part 2,
scanning the manifests with Trivy first and hardening them before applying.

## Files
```
part-4-k8s-deployment/
├── deployment.yaml          # UNOPTIMIZED baseline (scan target): no securityContext, no limits
├── deployment.secure.yaml   # HARDENED: securityContext + resources + probes + Secret + volumes
├── service.yaml             # NodePort 30080
└── reports/                 # Trivy config-scan outputs
```

## 1. Scan the manifests (Lab 4.3)
`trivy config` takes a **directory**; scan the baseline and the hardened set
separately:
```bash
cd part-4-k8s-deployment
mkdir -p /tmp/base /tmp/secure
cp deployment.yaml /tmp/base/
cp deployment.secure.yaml service.yaml /tmp/secure/

trivy config -q /tmp/base       # baseline
trivy config -q /tmp/secure     # hardened
```
> ⚠️ Don't pass `--no-progress` to `trivy config` (invalid on that subcommand in
> v0.71 → prints usage). Use `-q`. First run downloads the checks bundle.

| Manifest | HIGH | MEDIUM | LOW | Total |
|----------|------|--------|-----|-------|
| `deployment.yaml` | 3 | 3 | 11 | 17 |
| `deployment.secure.yaml` + `service.yaml` | 0 | 0 | 3 | 3 |

Baseline HIGH findings: `KSV-0014` root filesystem not read-only,
`KSV-0118` default security context; plus `KSV-0012` runs as root and
`KSV-0001` can escalate privileges. All resolved in the hardened manifest;
the 3 residual LOWs are cosmetic (default namespace, GID ≤ 10000, capability note).

## 2. Get the image into the cluster's containerd
RKE2 uses **containerd**, not Docker — a `docker build` on the host is invisible
to the cluster. Export the image and import it into containerd on **both** nodes
(pods can land on either):
```bash
# on the KVM host
sudo docker save todo-app:secure -o /tmp/todo-secure.tar
sudo chown $USER /tmp/todo-secure.tar
scp /tmp/todo-secure.tar lab-master:/tmp/ ; scp /tmp/todo-secure.tar lab-worker:/tmp/

for h in lab-master lab-worker; do
  ssh $h 'sudo /var/lib/rancher/rke2/bin/ctr \
    -a /run/k3s/containerd/containerd.sock -n k8s.io \
    images import /tmp/todo-secure.tar'
done
# imported as docker.io/library/todo-app:secure
```
The hardened deployment sets `imagePullPolicy: IfNotPresent` so it uses this
local image instead of trying to pull.

## 3. Create the Secret and deploy
`deployment.secure.yaml` reads `SECRET_KEY` from a Secret (never the image):
```bash
scp deployment.secure.yaml service.yaml lab-master:/home/labadmin/
ssh lab-master
KC="sudo kubectl --kubeconfig /etc/rancher/rke2/rke2.yaml"

$KC create secret generic todo-secrets \
  --from-literal=SECRET_KEY="$(python3 -c 'import secrets;print(secrets.token_urlsafe(50))')"
$KC apply -f /home/labadmin/deployment.secure.yaml
$KC apply -f /home/labadmin/service.yaml
$KC rollout status deploy/todo-deployment
$KC get pods -o wide -l app=todo
$KC get svc todo-service
```

> ⚠️ **`DJANGO_ALLOWED_HOSTS="*"`** is set in the deployment env. With `DEBUG`
> off, Django validates the `Host` header; the kubelet probes hit the **pod IP**
> and NodePort traffic carries the **node IP**, neither of which is in the
> default `ALLOWED_HOSTS`. Without this the probes get HTTP 400 and the pods
> crash-loop. In production, list concrete hostnames instead of `*`.

## 4. Verify
```bash
# runtime security context is actually enforced
$KC exec deploy/todo-deployment -- id
#   uid=999(appuser) gid=999(appuser)
$KC exec deploy/todo-deployment -- sh -c 'touch /app/x'
#   touch: cannot touch '/app/x': Read-only file system   <-- readOnlyRootFilesystem
$KC exec deploy/todo-deployment -- sh -c 'touch /tmp/x && echo writable'
#   writable                                              <-- /tmp emptyDir

# reach the service via NodePort (from the host)
curl http://192.168.122.79:30080/healthz/      # {"status": "ok"}  (HTTP 200)
```

## Result
`todo-deployment` **2/2 Running**, `todo-service` NodePort `30080`, pods running
as uid 999 with read-only root, dropped capabilities, no privilege escalation,
resource limits, and the secret sourced from a Kubernetes Secret. Effective
context:
```json
{"allowPrivilegeEscalation":false,"capabilities":{"drop":["ALL"]},
 "readOnlyRootFilesystem":true,"runAsNonRoot":true,"runAsUser":999}
```

## Caveats observed
- `readOnlyRootFilesystem` makes the demo **SQLite** DB at `/app/db.sqlite3`
  unwritable, so `GET /` returns 500 (DB write); `/healthz/` needs no DB → 200.
  For real use, point Django at an external DB or the `/app/data` emptyDir mount.
- External NodePort works on the **master** node IP. Reaching the **worker**
  node IP from outside is filtered by Calico's host policy (30080 isn't a Calico
  failsafe port like 22/6443); intra-node (`localhost:30080`) works on both.
