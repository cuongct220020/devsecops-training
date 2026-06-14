# DevSecOps Hands-On Lab Series: Comprehensive Guide

This practical lab series is designed to guide you through building, deploying, and securing an application environment across three critical layers: Operating System (OS), Platform (Kubernetes), and Application.

All resources are organized in a single repository. There are no lecture slides—this is a 100% hands-on experience.

---

## 📁 Repository Structure (`devsecops-lab-series`)

Clone this repository to your local machine or access it via your USB drive to begin:

```text
devsecops-lab-series/
├── README.md
├── part-1-os-hardening/
│   ├── main.tf
│   ├── variables.tf
│   └── outputs.tf
├── part-2-k8s-cluster/
│   ├── rke2-config/
│   │   ├── config.yaml.master
│   │   └── config.yaml.worker
│   └── install.sh
├── part-3-app-security/
│   ├── app/ (Django Project)
│   ├── Dockerfile
│   ├── docker-compose.yml
│   └── .env.example
└── part-4-k8s-deployment/
    ├── deployment.yaml
    └── service.yaml

```

---

## 🛠️ Lab 1: OS Provisioning and Hardening (OS Layer)

### 1.1. Objectives & Preparation

* **Objective:** Provision a clean Ubuntu 24.04 Virtual Machine using Infrastructure as Code (Terraform) on a KVM environment, assess its security compliance, and harden the OS to match CIS (Center for Internet Security) Benchmarks.
* **Requirements:** Local machine with KVM/Libvirt, Terraform, and Git installed.

### 1.2. Infrastructure as Code (IaC) Deployment

Navigate to the `part-1-os-hardening/` directory and review the `main.tf` file (which uses the libvirt provider to boot an Ubuntu 24.04 Cloud-init image).

Execute the following commands:

```bash
cd part-1-os-hardening/
terraform init
terraform apply -auto-approve

```

The system will spin up a fresh Ubuntu 24.04 VM and output its allocated IP address (`outputs.tf`).

### 1.3. Hands-on: Security Assessment & OS Hardening with OpenSCAP

SSH into your newly provisioned VM to begin the audit.

#### Step 1: Install OpenSCAP and the Security Profiles

```bash
sudo apt-get update && sudo apt-get install -y openscap-scanner ssg-debian-openssh ssg-ubuntu

```

#### Step 2: Generate a Baseline Security Report (CIS Benchmarks)

Scan the system and export the assessment report to an HTML file:

```bash
oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis_level1_server \
  --report report-baseline.html \
  /usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml

```

Download `report-baseline.html` to your local machine. You will observe a relatively low compliance percentage on this default vanilla OS.

#### Step 3: Perform OS Hardening

Use OpenSCAP's remediation capabilities to automatically correct basic issues (like turning off unused legacy services, adjusting `/etc/sysctl.conf` configurations, or modifying SSH settings).

```bash
# Apply automatic remediation based on the CIS profile
sudo oscap xccdf eval --remediate \
  --profile xccdf_org.ssgproject.content_profile_cis_level1_server \
  /usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml

```

#### Step 4: Re-evaluate Security Score (Post-Hardening)

```bash
oscap xccdf eval \
  --profile xccdf_org.ssgproject.content_profile_cis_level1_server \
  --report report-hardened.html \
  /usr/share/xml/scap/ssg/content/ssg-ubuntu2404-ds.xml

```

Compare the Pass/Fail ratio between `report-baseline.html` and `report-hardened.html` to measure how much your security posture improved.

---

## 🚏 Lab 2: Kubernetes Cluster Deployment & Hardening (Platform Layer)

### 2.1. Objectives & Preparation

* **Objective:** Set up a secure Kubernetes cluster (1 Master, 1 Worker) using RKE2 (Rancher Government Next-Generation Distribution) on top of the hardened VMs from Lab 1. Verify and audit cluster compliance using CIS Kubernetes Benchmarks.

### 2.2. RKE2 Deployment (1 Master, 1 Worker)

Navigate to the `part-2-k8s-cluster/` directory.

#### Step 1: Configure and Initialize the RKE2 Master Node

Activate the strict CIS profile of RKE2 by defining `/etc/rancher/rke2/config.yaml` on the Master node:

```yaml
profile: "cis-1.23" # Enables strict security constraints based on CIS Benchmarks
selinux: true

```

Execute the installation script:

```bash
curl -sfL https://get.rke2.io | sh -
sudo systemctl enable rke2-server.service --now

```

#### Step 2: Configure and Connect the RKE2 Worker Node

Retrieve the join token from the Master, apply the matching configuration on your Worker VM, and start the `rke2-agent.service`.

### 2.3. Hands-on: Security Assessment with Kube-bench

#### Step 1: Install Kube-bench on the Cluster

You can run kube-bench as a Kubernetes job, or execute its binary directly on the node. For this lab, run the binary directly on the Master node:

```bash
wget https://github.com/aquasecurity/kube-bench/releases/download/v0.8.0/kube-bench_0.8.0_linux_amd64.tar.gz
tar -xvf kube-bench_0.8.0_linux_amd64.tar.gz

```

#### Step 2: Scan Control Plane Components

```bash
./kube-bench run --targets master --benchmark rke2-cis-1.7

```

Observe the console output indicating `[PASS]`, `[FAIL]`, and `[WARN]`. Because RKE2 is running with the `profile: "cis-1.23"` flag, most of the core configurations (like etcd encryption, TLS parameters, etc.) will pass by default.

#### Step 3: Resolve Warning Items (Remediation)

Scroll down to the Remediations section at the end of the kube-bench output. Execute the suggested remediation steps (e.g., restricting permission settings of agent configuration files such as `/var/lib/rancher/rke2/agent/kubelet.config` to `600`), then rerun the scan until all critical warnings are addressed.

---

## 🐍 Lab 3: Secure Application Development (Application Layer)

### 3.1. Objectives & Preparation

* **Objective:** Find and fix security vulnerabilities, outdated libraries, hardcoded credentials (Secrets), and misconfigured base images within a legacy Python Django application.
* **Environment:** A dedicated VM acting as your Developer/Build Agent.

### 3.2. Target Application Legacy State (`part-3-app-security/`)

Here is the initial, insecure `Dockerfile` provided in your directory:

```dockerfile
FROM python:3.9  # Bug 1: Large, legacy base image containing hundreds of OS vulnerabilities
WORKDIR /app
COPY . /app
RUN pip install -r requirements.txt
ENV SECRET_KEY="super-secret-key-in-code" # Bug 2: Leaking secrets directly in plain text code
USER root # Bug 3: Running application as administrative 'root' user
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]

```

### 3.3. Hands-on: Vulnerability Scanning with Trivy

First, inspect your codebase and configuration using Trivy before attempting to build.

```bash
# Install Trivy
sudo apt-get install wget apt-transport-https gnupg lsb-release -y
wget -qO - https://aquasecurity.github.io/trivy-repo/deb/public.key | gpg --dearmor | sudo tee /usr/share/keyrings/trivy.gpg > /dev/null
echo "deb [signed-by=/usr/share/keyrings/trivy.gpg] https://aquasecurity.github.io/trivy-repo/deb $(lsb_release -sc) main" | sudo tee /etc/apt/sources.list.d/trivy.list
sudo apt-get update && sudo apt-get install trivy -y

# Scan the local workspace directory (Detects secrets, dependencies, and misconfigurations)
trivy fs .

```

Trivy will flag a **CRITICAL** severity rating due to exposed keys and a vulnerable OS base.

### 3.4. Hands-on: Remediation (Fixing CVEs & Secrets)

Modify the codebase and Dockerfile to make them secure.

#### Step 1: Move Secrets to an Environment File

Remove the `ENV SECRET_KEY` line from the Dockerfile. Create a local `.env` file (ensure it is listed in `.gitignore`) and use a library like `python-dotenv` to call environment variables in your Django `settings.py`.

#### Step 2: Implement a Multi-stage, Non-root, Slim Dockerfile

Update the `Dockerfile` with the following secure configuration:

```dockerfile
# Stage 1: Build dependencies
FROM python:3.11-slim AS builder
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends gcc python3-dev
COPY requirements.txt .
RUN pip install --user --no-cache-dir -r requirements.txt

# Stage 2: Final Secure Runtime Image
FROM python:3.11-slim
WORKDIR /app
# Create an unprivileged user to execute application runtimes
RUN groupadd -g 999 appuser && useradd -r -u 999 -g appuser appuser
COPY --from=builder /root/.local /home/appuser/.local
COPY --chown=appuser:appuser . /app

ENV PATH=/home/appuser/.local/bin:$PATH
USER appuser

EXPOSE 8000
CMD ["gunicorn", "--bind", "0.0.0.0:8000", "todo.wsgi:application"]

```

#### Step 3: Re-scan and Verify

Build your updated secure image and perform a Trivy scan:

```bash
docker build -t todo-app:secure .
trivy image todo-app:secure

```

* **Expected Result:** Vulnerabilities (CVEs) drop drastically, the root user warning is resolved, and secrets are no longer flagged.

---

## 🚀 Lab 4: Secure Application Deployment on Kubernetes (Deployment Layer)

### 4.1. Objectives & Preparation

* **Objective:** Draft a Kubernetes deployment manifest to ship your secure container from Lab 3 onto the RKE2 cluster from Lab 2. Assess and resolve misconfigurations using Trivy prior to publishing your service outside the network using NodePort.

### 4.2. Unoptimized Initial Manifest State (`part-4-k8s-deployment/`)

Here is the baseline `deployment.yaml` manifest:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: todo-deployment
spec:
  replicas: 1
  selector:
    matchLabels:
      app: todo
  template:
    metadata:
      labels:
        app: todo
    spec:
      containers:
      - name: todo-app
        image: todo-app:secure
        ports:
        - containerPort: 8000

```

### 4.3. Hands-on: Manifest Misconfiguration Scanning with Trivy

Inspect the manifest configuration before applying it to your live cluster:

```bash
trivy config deployment.yaml

```

Trivy will flag multiple warnings because the Container lacks explicit `SecurityContext` parameters (e.g. running with unchecked privileges, writeable root filesystems, and missing resource allocations).

### 4.4. Hardening the Kubernetes Manifest

Update `deployment.yaml` and add a `service.yaml` configuration to mitigate the highlighted security risks.

**Updated `deployment.yaml` (Hardened):**

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: todo-deployment
  labels:
    app: todo
spec:
  replicas: 2
  selector:
    matchLabels:
      app: todo
  template:
    metadata:
      labels:
        app: todo
    spec:
      containers:
      - name: todo-app
        image: todo-app:secure
        ports:
        - containerPort: 8000
        # Strict SecurityContext setup matching CIS standards
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          runAsNonRoot: true
          runAsUser: 999
          capabilities:
            drop:
            - ALL
        resources:
          limits:
            cpu: "500m"
            memory: "512Mi"
          requests:
            cpu: "250m"
            memory: "256Mi"

```

**Created `service.yaml` (Exposed securely):**

```yaml
apiVersion: v1
kind: Service
metadata:
  name: todo-service
spec:
  type: NodePort
  selector:
    app: todo
  ports:
    - port: 8000
      targetPort: 8000
      nodePort: 30080 # Port exposed to external lab network

```

### 4.5. Deployment & Final Verification

Deploy your finalized manifests to your hardened RKE2 cluster:

```bash
kubectl apply -f deployment.yaml
kubectl apply -f service.yaml

# Check structural output and components
kubectl get pods
kubectl get svc todo-service

```

---

## 🏆 Final Lab Milestones & Verification

By concluding this series, you will have checked off the following criteria:

| Layer | Assessment Tool | Success Criteria |
| --- | --- | --- |
| **OS Layer** | OpenSCAP | Hardened Ubuntu 24.04 VM auditing green on OpenSCAP-CIS. |
| **Platform Layer** | Kube-bench | Secure RKE2 Master and Agent Node configuration verifying clean run outputs. |
| **Application Layer** | Trivy | Secrets scrubbed from code and critical CVEs mitigated using multi-stage, non-root Docker builds. |
| **Deployment Layer** | Trivy Config | Hardened K8s templates running securely constrained pods isolated with active `SecurityContext` properties. |