# Part 3 — Secure Application Development (Trivy / Docker)

Take a deliberately insecure Django "todo" app + Dockerfile, find the problems
with Trivy, and fix them with a multi-stage, slim, non-root image.

## Files
```
part-3-app-security/
├── app/                    # Django project: todo/ (settings, urls, wsgi) + todos/ app
│   └── todos/views.py      # includes /healthz/ (no-DB endpoint used by K8s probes in Part 4)
├── Dockerfile              # INSECURE baseline (scan target): python:3.9, ENV secret, USER root
├── Dockerfile.secure       # REMEDIATED: multi-stage python:3.11-slim, non-root uid 999
├── docker-compose.yml      # local run (builds Dockerfile.secure, runs migrate + gunicorn)
├── requirements.txt
├── .env.example            # copy to .env (gitignored); holds SECRET_KEY
└── reports/                # Trivy image-scan outputs
```

The three planted bugs in `Dockerfile`: (1) fat legacy base `python:3.9`,
(2) `ENV SECRET_KEY="…"` baked into a layer, (3) `USER root`. The app's
`settings.py` already reads `SECRET_KEY` from the environment via `python-dotenv`
(the secret-remediation), so the secure image never embeds it.

## 0. Install Trivy
The convenience install script didn't drop the binary on this host, so install
the release binary directly:
```bash
cd /tmp
TAG=$(curl -s https://api.github.com/repos/aquasecurity/trivy/releases/latest \
      | grep -oP '"tag_name":\s*"\K[^"]+')
curl -sSL -o trivy.tgz \
  "https://github.com/aquasecurity/trivy/releases/download/${TAG}/trivy_${TAG#v}_Linux-64bit.tar.gz"
tar -xzf trivy.tgz trivy && sudo install -m0755 trivy /usr/local/bin/trivy
trivy --version      # 0.71.0
```

## 1. Scan the workspace (secrets + Dockerfile misconfig)
```bash
cd part-3-app-security

# secret scanner: note it is PATTERN-based — the placeholder value
# "super-secret-key-in-code" doesn't match a known credential format, so the
# real catch for the baked-in secret is the Dockerfile MISCONFIG check below.
trivy fs --scanners secret .

# Dockerfile misconfiguration scan (the insecure one)
mkdir -p /tmp/ins && cp Dockerfile /tmp/ins/Dockerfile
trivy fs --scanners misconfig /tmp/ins
```
Findings on the insecure Dockerfile (3):
- **DS-0031 CRITICAL** — `Possible exposure of secret env "SECRET_KEY" in ENV`
- **DS-0002 HIGH** — running as `root`
- **DS-0026 LOW** — no `HEALTHCHECK`

> ⚠️ Use `trivy config <DIR>` (it takes a **directory**, not a file) **without**
> `--no-progress` — that flag isn't valid on the `config` subcommand in v0.71
> and makes it print usage. `trivy fs --scanners misconfig` works on files/dirs.

## 2. Build both images
```bash
# (this host runs Docker as root → prefix with sudo)
sudo docker build -t todo-app:insecure -f Dockerfile        .
sudo docker build -t todo-app:secure   -f Dockerfile.secure .
sudo docker images | grep todo-app
# todo-app:insecure  1.67GB
# todo-app:secure    249MB
```

## 3. Scan the images and compare
Run Trivy with `sudo` so it can reach the root Docker daemon (otherwise it finds
no image and returns an empty report):
```bash
sudo trivy image --scanners vuln todo-app:insecure
sudo trivy image --scanners vuln todo-app:secure
```

| Image | Base | Size | CRITICAL | HIGH | Total CVEs |
|-------|------|------|----------|------|-----------|
| insecure | python:3.9 | 1.67 GB | 188 | 982 | 5,565 |
| secure | python:3.11-slim | 249 MB | 4 | 27 | 154 |

≈ **97% fewer CVEs**. Misconfig drops from 3 → 1 (only the LOW "no HEALTHCHECK").
Reports saved in `reports/trivy-{insecure,secure}-image.txt`.

## Run it locally (optional)
```bash
cp .env.example .env      # set a real SECRET_KEY:
#   python -c "import secrets;print(secrets.token_urlsafe(50))"
sudo docker compose up --build      # migrate + gunicorn on :8000
curl -s localhost:8000/healthz/     # {"status": "ok"}
```

The `todo-app:secure` image built here is what Part 4 deploys to the RKE2
cluster.
