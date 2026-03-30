#!/bin/bash
# entrypoint.sh — full pipeline sequence run inside Cloud Run Job
# Each step exits non-zero on failure, which marks the job execution as failed.
set -euo pipefail

log() { echo "[$(date -u '+%Y-%m-%dT%H:%M:%SZ')] $*"; }

log "=== concrete-data pipeline ==="
log "ENV=${ENV:-prod} | GCP_PROJECT_ID=${GCP_PROJECT_ID:-unset}"
log "INITIAL_START_DATE=${INITIAL_START_DATE:-2025-01-01T00:00:00}"
log "END_DATE=${END_DATE:-none}"

# ── Step 1: dlt extract + load ────────────────────────────────────────────────
log "--- Step 1: dlt extract + load ---"
cd /app/pipeline
python pipeline.py
log "dlt complete"

# ── Step 2: dbt source freshness ──────────────────────────────────────────────
log "--- Step 2: dbt source freshness ---"
cd /app/transform
dbt source freshness \
  --profiles-dir . \
  --target prod
log "source freshness complete"

# ── Step 3: dbt run ───────────────────────────────────────────────────────────
log "--- Step 3: dbt run ---"
dbt run \
  --profiles-dir . \
  --target prod
log "dbt run complete"

# ── Step 4: dbt test ──────────────────────────────────────────────────────────
log "--- Step 4: dbt test ---"
dbt test \
  --profiles-dir . \
  --target prod \
  --store-failures
log "dbt test complete"

# ── Step 5: Elementary monitor ────────────────────────────────────────────────
log "--- Step 5: Elementary monitor ---"
edr monitor \
  --project-dir . \
  --profiles-dir . \
  --profile concrete_data \
  --target prod || log "WARNING: Elementary monitor exited non-zero (non-fatal)"
# Elementary failures are non-fatal — anomalies show in the dashboard,
# they shouldn't prevent the dashboard from deploying.
log "Elementary complete"

# ── Step 6: Build Evidence dashboard ─────────────────────────────────────────
log "--- Step 6: Build Evidence dashboard ---"
cd /app/dashboard
npm ci --prefer-offline
EVIDENCE_SOURCE__DEFAULT__CONNECTOR=bigquery \
  EVIDENCE_SOURCE__DEFAULT__PROJECT_ID="${GCP_PROJECT_ID}" \
  EVIDENCE_SOURCE__DEFAULT__DATASET=nyc_311_marts \
  npm run build
log "Evidence build complete"

# ── Step 7: Deploy to GCS ────────────────────────────────────────────────────
log "--- Step 7: Deploy dashboard to GCS ---"
# Use Python's google-cloud-storage instead of gsutil (already installed)
python - <<'PYEOF'
import os
import sys
from pathlib import Path
from google.cloud import storage

bucket_name = os.environ["DASHBOARD_BUCKET"]
build_dir   = Path("/app/dashboard/build")

if not build_dir.exists():
    print(f"ERROR: build dir {build_dir} not found", file=sys.stderr)
    sys.exit(1)

client = storage.Client()
bucket = client.bucket(bucket_name)

CONTENT_TYPES = {
    ".html":  ("text/html",              "public, max-age=300"),
    ".js":    ("application/javascript", "public, max-age=31536000"),
    ".css":   ("text/css",               "public, max-age=31536000"),
    ".json":  ("application/json",       "public, max-age=300"),
    ".svg":   ("image/svg+xml",          "public, max-age=31536000"),
    ".png":   ("image/png",              "public, max-age=31536000"),
    ".ico":   ("image/x-icon",           "public, max-age=31536000"),
    ".woff2": ("font/woff2",             "public, max-age=31536000"),
}

uploaded = 0
for local_path in sorted(build_dir.rglob("*")):
    if not local_path.is_file():
        continue
    blob_name   = str(local_path.relative_to(build_dir))
    suffix      = local_path.suffix.lower()
    content_type, cache_control = CONTENT_TYPES.get(
        suffix, ("application/octet-stream", "public, max-age=3600")
    )
    blob = bucket.blob(blob_name)
    blob.content_type  = content_type
    blob.cache_control = cache_control
    blob.upload_from_filename(str(local_path))
    uploaded += 1

print(f"Uploaded {uploaded} files to gs://{bucket_name}")
PYEOF

log "Dashboard deployed to gs://${DASHBOARD_BUCKET}"
log "Public URL: https://storage.googleapis.com/${DASHBOARD_BUCKET}/index.html"
log "=== Pipeline complete ==="
