FROM python:3.12-slim

# Install system deps (gsutil via google-cloud-sdk is large; use pip's gcloud storage instead)
RUN apt-get update && apt-get install -y --no-install-recommends \
    git \
    curl \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /app

# ── Python dependencies ──────────────────────────────────────────────────────
# Copy requirements first so Docker layer cache is reused when only code changes

COPY pipeline/requirements.txt pipeline/requirements.txt
RUN pip install --no-cache-dir -r pipeline/requirements.txt

COPY transform/requirements.txt transform/requirements.txt
RUN pip install --no-cache-dir -r transform/requirements.txt

# google-cloud-storage for gsutil-equivalent uploads
RUN pip install --no-cache-dir google-cloud-storage

# ── Application code ─────────────────────────────────────────────────────────

COPY pipeline/   pipeline/
COPY transform/  transform/
COPY .dlt/       .dlt/
COPY dashboard/  dashboard/

# Install dbt packages at build time (bakes them into the image)
RUN cd transform && dbt deps

# ── Entrypoint ───────────────────────────────────────────────────────────────

COPY entrypoint.sh .
RUN chmod +x entrypoint.sh

ENTRYPOINT ["./entrypoint.sh"]
