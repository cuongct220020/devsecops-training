# Part 2 — Kubernetes Cluster Deployment & Hardening (RKE2 / kube-bench)

Stand up a 2-node RKE2 cluster (1 master + 1 worker) in the **CIS profile** on
the VMs from Part 1, then audit it with kube-bench.

## Files
```
part-2-k8s-cluster/
├── install.sh                       # installs RKE2 server/agent in the CIS profile
├── rke2-config/
│   ├── config.yaml.master           # /etc/rancher/rke2/config.yaml for the master
│   └── config.yaml.worker           # ditto for the worker (server URL + token)
└── reports/                         # kube-bench outputs
```

`install.sh {master|worker}` does: download RKE2 → create the `etcd` user and
apply the CIS kernel sysctls (both required by the CIS profile) → copy the
matching config to `/etc/rancher/rke2/config.yaml` (mode 600) → enable+start the
service. For the worker it also prints how to use kubectl / read the token.

> ⚠️ **Two config changes vs. the original plan** (already applied here):
> - `profile: "cis"` — RKE2 v1.35 **rejects** the old `cis-1.23` value
>   (`fatal: invalid value provided for --profile flag`). `cis` selects the
>   latest bundled CIS benchmark.
> - **No `selinux: true`** — that's RHEL/CoreOS only; Ubuntu uses AppArmor and
>   the server won't start with SELinux enforced on a non-SELinux host.

## 1. Install the master
```bash
# from the KVM host: copy the lab files onto the node
scp -r part-2-k8s-cluster lab-master:/home/labadmin/

ssh lab-master
cd part-2-k8s-cluster
sudo ./install.sh master          # downloads RKE2 (~hundreds of MB) and starts rke2-server
```
The service takes a few minutes to become `active` (etcd → apiserver → CNI).
Set up kubectl and wait for the node to be `Ready`:
```bash
export KUBECONFIG=/etc/rancher/rke2/rke2.yaml
export PATH=$PATH:/var/lib/rancher/rke2/bin
sudo ln -sf /var/lib/rancher/rke2/bin/kubectl /usr/local/bin/kubectl
kubectl get nodes        # node1-master  Ready  control-plane,etcd
```
Grab the join token for the worker:
```bash
sudo cat /var/lib/rancher/rke2/server/node-token
```

## 2. Join the worker
On the worker, write its config with the **master IP** and the **token**, then
install:
```bash
ssh lab-worker
cd part-2-k8s-cluster
cat > rke2-config/config.yaml.worker <<CFG
profile: "cis"
server: "https://192.168.122.79:9345"      # master IP, supervisor port 9345
token: "K10...<paste node-token>"
node-label:
  - "node-role.lab/worker=true"
CFG
sudo ./install.sh worker          # starts rke2-agent, joins the cluster
```
Back on the master, confirm both nodes are `Ready`:
```bash
kubectl get nodes -o wide
# node1-master  Ready  control-plane,etcd   v1.35.5+rke2r2
# node2-worker  Ready  <none>               v1.35.5+rke2r2   ... containerd://2.x
```

## 3. Audit with kube-bench
```bash
ssh lab-master
cd /tmp
TAG=v0.15.6; VER=0.15.6
curl -sSL -o kb.tgz \
  "https://github.com/aquasecurity/kube-bench/releases/download/${TAG}/kube-bench_${VER}_linux_amd64.tar.gz"
mkdir kb && tar -xzf kb.tgz -C kb && cd kb
ls cfg | grep rke2          # rke2-cis-1.7 / 1.8 / 1.23 / 1.24

# control plane
sudo ./kube-bench run --targets master --benchmark rke2-cis-1.24 \
  --config-dir ./cfg --config ./cfg/config.yaml | tee /tmp/kb-master.txt
```
Run the node checks on the worker the same way with `--targets node`.

Observed:

| Target | PASS | FAIL | WARN | INFO |
|--------|------|------|------|------|
| master | 43 | 3 | 8 | 8 |
| node   | 5  | 7 | 7 | 4 |

## 4. Triaging the FAILs (Step 3: remediation) — read before chmod-ing anything
The master FAILs are **kube-bench false positives, not real misconfigurations**:
```bash
# the actual files are already locked down tighter than CIS asks
sudo ls -l /var/lib/rancher/rke2/agent/pod-manifests/
# -rw------- root root  kube-apiserver.yaml   (i.e. 600 root:root)

# but the benchmark's test for 1.1.1 is:
#   audit: stat -c permissions=%a .../kube-apiserver.yaml
#   compare: { op: eq, value: "644" }      <-- requires EXACTLY 644
```
600 is *more* restrictive than 644, yet the equality test marks it FAIL. Running
kube-bench's suggested `chmod 644` would **weaken** security, so don't.
The node `4.2.x` kubelet FAILs (anonymous-auth, authorization-mode, …) are the
same kind of artifact: kube-bench inspects the kubelet **command line**, but
RKE2 supplies those via a config file it can't see.

Verify the real posture directly instead:
```bash
# secrets encrypted at rest?
sudo grep -o '"aescbc"' /var/lib/rancher/rke2/server/cred/encryption-config.json
# -> "aescbc"   (yes)
```

## Result
2-node RKE2 cluster in the CIS profile, both `Ready`; control-plane manifests at
`600 root:root`; secrets encrypted at rest (aescbc). Remaining kube-bench
FAIL/WARN items are benchmark/tooling artifacts or manual-review items.
Outputs saved in `reports/kb-master.txt`, `reports/kb-node.txt`.
