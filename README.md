# concrete-data — NYC 311 pipeline

![Pipeline](https://github.com/sholomdev/concrete-data/actions/workflows/pipeline.yml/badge.svg)
![CI](https://github.com/sholomdev/concrete-data/actions/workflows/ci.yml/badge.svg)
![Terraform](https://github.com/sholomdev/concrete-data/actions/workflows/terraform.yml/badge.svg)

Daily incremental pipeline ingesting NYC 311 service requests from the Socrata API
into BigQuery, transformed with dbt, and published as a static Evidence dashboard
hosted on GCS.

```
Socrata API → dlt → BigQuery (raw) → dbt → BigQuery (marts) → Evidence → GCS
                         ↓
                     GCS backup
```

## Stack

| Layer | Tool | Notes |
|---|---|---|
| Ingest | dlt | dev: DuckDB · prod: BigQuery + GCS backup |
| Transform | dbt Core + dbt-expectations | dev: DuckDB · prod: BigQuery |
| Observability | Elementary | prod only |
| Dashboard | Evidence | Static site hosted on GCS |
| Container | Docker + Artifact Registry | Cloud Run Job runs the pipeline |
| Orchestration | Cloud Scheduler → Cloud Run Job | Daily at 05:00 UTC |
| CI/CD | GitHub Actions | Build image on push; Terraform on infra changes |
| Infrastructure | Terraform | All GCP resources |
| Auth | Workload Identity Federation | GitHub Actions → GCP, no long-lived keys |

## Architecture

```
GitHub push
    │
    ▼
GitHub Actions
    ├── Build Docker image
    ├── Push to Artifact Registry
    ├── Update Cloud Run Job image
    └── Trigger Cloud Run Job (waits for completion)

Cloud Scheduler (05:00 UTC daily)
    └── Trigger Cloud Run Job

Cloud Run Job (Docker container)
    ├── dlt → BigQuery raw + GCS backup
    ├── dbt source freshness check
    ├── dbt run (staging → marts)
    ├── dbt test + store failures
    ├── Elementary monitor
    ├── Evidence build
    └── Deploy static site → GCS bucket
```

---

## Local development

### Prerequisites
- Python 3.12+
- Node.js 20+
- Docker (for image builds)
- gcloud CLI

### 1. Clone and configure secrets

```bash
git clone https://github.com/sholomdev/concrete-data
cd concrete-data
cp .dlt/secrets.toml.template .dlt/secrets.toml
# Add your Socrata app token to .dlt/secrets.toml
```

### 2. Install dependencies

```bash
make install
```

### 3. Run the pipeline locally (DuckDB — no GCP needed)

```bash
make pipeline-dev   # dlt → concrete_data_dev.duckdb
make dbt-dev        # dbt run + test
make dashboard-dev  # Evidence at http://localhost:3000
```

Or all at once:
```bash
make dev
```

---

## Deploying to production

### Step 1 — GCP bootstrap

```bash
export GCP_PROJECT_ID=your-project-id

# Enable APIs
gcloud services enable \
  bigquery.googleapis.com storage.googleapis.com \
  iam.googleapis.com iamcredentials.googleapis.com sts.googleapis.com \
  run.googleapis.com artifactregistry.googleapis.com \
  cloudscheduler.googleapis.com cloudbuild.googleapis.com

# Create Terraform state bucket (must exist before terraform init)
gsutil mb -l US gs://${GCP_PROJECT_ID}-tf-state
gsutil versioning set on gs://${GCP_PROJECT_ID}-tf-state
```

### Step 2 — Configure Terraform

Edit `infra/main.tf` backend block — replace `YOUR_GCP_PROJECT_ID` with your real project ID.

```bash
cp infra/terraform.tfvars.template infra/terraform.tfvars
# Edit infra/terraform.tfvars with your project_id, github_repo, region
```

### Step 3 — Run Terraform

```bash
cd infra
terraform init
terraform plan
terraform apply
terraform output   # capture these values for GitHub secrets
```

Terraform creates: BigQuery datasets, GCS buckets (backup, dashboard, state),
Artifact Registry, Cloud Run Job, Cloud Scheduler, service accounts, WIF pool.

### Step 4 — GitHub Secrets

Go to repo → Settings → Secrets and variables → Actions:

| Secret | Value |
|---|---|
| `GCP_PROJECT_ID` | your GCP project ID |
| `GCP_REGION` | e.g. `us-central1` |
| `WIF_PROVIDER` | `terraform output workload_identity_provider` |
| `PIPELINE_SA_EMAIL` | `terraform output pipeline_sa_email` |
| `DASHBOARD_BUCKET` | `terraform output dashboard_bucket` |
| `SOCRATA_APP_TOKEN` | from data.cityofnewyork.us → App Tokens |

No Vercel secrets needed — everything runs in GCP.

### Step 5 — Update .dlt/config.toml

```toml
[destination.bigquery]
project = "your-actual-project-id"

[destination.gcs_backup]
bucket_url = "gs://your-project-id-nyc311-raw-backup"
```

### Step 6 — First run (backfill)

```bash
# Trigger a backfill from Jan 1 2025 via GitHub Actions
gh workflow run backfill.yml -f start_date=2025-01-01

# Or run the Cloud Run Job directly (after pushing the image)
make push-image
make run-job
```

After the first run, Cloud Scheduler takes over at 05:00 UTC daily.

### Step 7 — View the dashboard

```bash
terraform output dashboard_url
# https://storage.googleapis.com/your-project-nyc311-dashboard/index.html
```

---

## Project structure

```
concrete-data/
├── Dockerfile                   # Cloud Run Job container
├── entrypoint.sh                # Pipeline sequence: dlt → dbt → Evidence → GCS
├── Makefile                     # Developer shortcuts
├── pyproject.toml               # ruff + pytest config
├── .dlt/
│   ├── config.toml              # Non-secret dlt config
│   └── secrets.toml.template
├── .github/workflows/
│   ├── pipeline.yml             # Build image + trigger Cloud Run Job on push
│   ├── ci.yml                   # PR checks: lint, DuckDB pipeline, Docker build
│   ├── backfill.yml             # Manual backfill via Cloud Run Job
│   └── terraform.yml            # Plan/apply on infra/ changes
├── pipeline/
│   ├── sources/nyc_311.py       # dlt source + incremental resource
│   ├── tests/test_source.py     # pytest smoke tests
│   └── pipeline.py              # Runner (ENV=dev|prod)
├── transform/
│   ├── models/
│   │   ├── sources.yml          # Source freshness config
│   │   ├── staging/             # stg_311_requests
│   │   └── marts/               # complaints_daily, resolution_time, open_requests, health
│   ├── macros/cross_db.sql      # BigQuery/DuckDB compatibility shims
│   ├── dbt_project.yml
│   ├── packages.yml             # elementary, dbt-expectations
│   └── profiles.yml             # dev=DuckDB, prod=BigQuery
├── dashboard/
│   ├── pages/
│   │   ├── index.md             # Overview KPIs
│   │   ├── insights/index.md    # Resolution time, open requests
│   │   └── health.md            # Pipeline health, dbt tests
│   └── package.json
└── infra/
    ├── main.tf                  # All GCP resources
    ├── variables.tf
    ├── outputs.tf
    └── terraform.tfvars.template
```

## Dashboard pages

| Page | Description |
|---|---|
| `/` | 30-day KPIs, daily volume, top complaint types, borough breakdown |
| `/insights` | Resolution times by type/borough, open request aging, channel mix |
| `/health` | Row count anomalies, dbt test results, Elementary output |

## Monitoring

Pipeline is healthy when:
1. Cloud Run Job execution shows **Succeeded** in GCP Console → Cloud Run → Jobs
2. `dbt source freshness` passes (data updated within 25 hours)
3. Row count is within 30% of 7-day rolling average (visible on `/health` page)
4. All dbt tests pass

Logs: GCP Console → Cloud Run → Jobs → `nyc-311-pipeline` → Logs tab.
