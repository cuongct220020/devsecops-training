# =============================================================================
# Lab 3 — LEGACY / INSECURE starting state (Section 3.2).
#
# This is the image you SCAN first (`trivy fs .`, `trivy image`) to discover
# problems, then fix. The three planted bugs:
#   Bug 1: a large, legacy base image full of OS CVEs (python:3.9, not -slim)
#   Bug 2: a secret hardcoded in plain text in the image layers
#   Bug 3: the container runs as the root user
#
# The remediated version lives in Dockerfile.secure — diff the two.
# =============================================================================
FROM python:3.9
WORKDIR /app

COPY requirements.txt .
RUN pip install -r requirements.txt

COPY app/ /app

ENV SECRET_KEY="super-secret-key-in-code"
USER root

EXPOSE 8000
CMD ["python", "manage.py", "runserver", "0.0.0.0:8000"]
