# concrete-data — NYC 311 pipeline

![Pipeline](https://github.com/sholomdev/concrete-data/actions/workflows/pipeline.yml/badge.svg)
![CI](https://github.com/sholomdev/concrete-data/actions/workflows/ci.yml/badge.svg)
![Terraform](https://github.com/sholomdev/concrete-data/actions/workflows/terraform.yml/badge.svg)

Daily incremental pipeline ingesting NYC 311 service requests from the Socrata API into BigQuery, transformed with dbt, and published as a static Evidence dashboard on Vercel.

```
Socrata API → dlt → BigQuery (raw) → dbt → BigQuery (marts) → Evidence → Vercel
                       ↓
                   GCS backup
```

## Stack

| Layer | Tool | Env |
|-------|------|-----|
| Ingest | dlt | dev: DuckDB · prod: BigQuery + GCS |
| Transform | dbt Core + dbt-expectations | dev: DuckDB · prod: BigQuery |
| Observability | Elementary | prod: BigQuery |
| Dashboard | Evidence | dev: DuckDB · prod: BigQuery → Vercel |
| Orchestration | GitHub Actions (cron 05:00 UTC) | — |
| Infrastructure | Terraform | GCP |
| Auth | Workload Identity Federation | GitHub Actions → GCP |

---

## Local development

### Prerequisites
- Python 3.12+
- Node.js 20+
- DuckDB (installed via pip with dlt)

### 1. Clone and set up secrets

```bash
git clone https://github.com/sholomdev/concrete-data
cd concrete-data

cp .dlt/secrets.toml.template .dlt/secrets.toml
# Edit .dlt/secrets.toml — add your Socrata app token.
# For local dev you can leave BigQuery credentials empty.
```

### 2. Run the pipeline locally (DuckDB)

```bash
cd pipeline
pip install -r requirements.txt

ENV=dev python pipeline.py
# Output: concrete_data_dev.duckdb in the repo root
```

Force a full reload:
```bash
ENV=dev python pipeline.py --full
```

### 3. Run dbt (DuckDB)

```bash
cd transform
pip install -r requirements.txt
dbt deps

ENV=dev DUCKDB_PATH=../concrete_data_dev.duckdb \
  dbt run --target dev --profiles-dir .

ENV=dev DUCKDB_PATH=../concrete_data_dev.duckdb \
  dbt test --target dev --profiles-dir .
```

### 4. Run the Evidence dashboard locally (DuckDB)

```bash
cd dashboard
npm install

# Copy the example env file and point it at your local DuckDB
cp .env.example .env
# Edit .env if your duckdb path differs from the default

npm run dev
# Opens at http://localhost:3000
```

---

## Deploying to production

### Step 1 — Bootstrap GCP

```bash
# Create the Terraform state bucket manually (chicken-and-egg)
gsutil mb -l US gs://YOUR_PROJECT_ID-tf-state

# Update infra/main.tf backend bucket name, then:
cd infra
cp terraform.tfvars.template terraform.tfvars
# Edit terraform.tfvars

terraform init
terraform plan
terraform apply
```

Terraform creates:
- BigQuery datasets: `nyc_311_raw`, `nyc_311_staging`, `nyc_311_marts`, `elementary`
- GCS bucket for raw backup (90-day lifecycle)
- Three service accounts: `dlt-pipeline`, `dbt-runner`, `evidence-dashboard`
- Workload Identity Federation pool bound to this GitHub repo

### Step 2 — Add GitHub Secrets

After `terraform apply`, run `terraform output` and add these as GitHub Actions secrets:

| Secret | Source |
|--------|--------|
| `GCP_PROJECT_ID` | Your GCP project ID |
| `WIF_PROVIDER` | `terraform output workload_identity_provider` |
| `PIPELINE_SA_EMAIL` | `terraform output pipeline_sa_email` |
| `DBT_SA_EMAIL` | `terraform output dbt_sa_email` |
| `DASHBOARD_SA_EMAIL` | `terraform output dashboard_sa_email` |
| `TERRAFORM_SA_EMAIL` | `dlt-pipeline` SA (or a dedicated terraform SA) |
| `SOCRATA_APP_TOKEN` | [Register at data.cityofnewyork.us](https://data.cityofnewyork.us/profile/app_tokens) |
| `VERCEL_TOKEN` | Vercel dashboard → Settings → Tokens |
| `VERCEL_ORG_ID` | Vercel dashboard → Settings |
| `VERCEL_PROJECT_ID` | Vercel project settings |

### Step 3 — Update config.toml

Edit `.dlt/config.toml`:
```toml
[destination.bigquery]
project = "YOUR_GCP_PROJECT_ID"

[destination.gcs_backup]
bucket_url = "gs://YOUR_GCP_PROJECT_ID-nyc311-raw-backup"
```

### Step 4 — Trigger first run

```bash
# Full refresh to backfill from Jan 1 2025
gh workflow run pipeline.yml -f full_refresh=true
```

After the first run, the daily cron takes over at 05:00 UTC.

### Manual backfills

The backfill workflow lets you reload a specific date range without touching the daily pipeline:

```bash
# Backfill a specific window
gh workflow run backfill.yml \
  -f start_date=2025-01-01 \
  -f end_date=2025-03-31

# Dry run — prints available row count, loads nothing
gh workflow run backfill.yml \
  -f start_date=2025-06-01 \
  -f dry_run=true
```

Or trigger from GitHub → Actions → Backfill → Run workflow.

---

## Project structure

```
concrete-data/
├── .dlt/
│   ├── config.toml          # non-secret dlt config
│   └── secrets.toml.template
├── .github/workflows/
│   ├── pipeline.yml         # daily cron: dlt → dbt → Evidence
│   ├── ci.yml               # PR checks with DuckDB
│   ├── backfill.yml         # manual: historical reload with date range
│   └── terraform.yml        # infra plan/apply on infra/ changes
├── pyproject.toml            # ruff lint rules + pytest config
├── Makefile                  # developer shortcuts (make dev, make lint, etc.)
├── pipeline/
│   ├── sources/
│   │   └── nyc_311.py       # dlt source + incremental resource
│   ├── tests/
│   │   └── test_source.py   # pytest smoke tests (DuckDB, no GCP needed)
│   └── pipeline.py          # runner (ENV=dev|prod)
├── transform/
│   ├── models/
│   │   ├── sources.yml       # source freshness config
│   │   ├── staging/
│   │   │   ├── stg_311_requests.sql
│   │   │   └── stg_311_requests.yml  # Elementary + dbt-expectations tests
│   │   └── marts/
│   │       ├── mart_complaints_daily.sql
│   │       ├── mart_resolution_time.sql
│   │       ├── mart_open_requests.sql
│   │       ├── mart_pipeline_health.sql
│   │       └── schema.yml
│   ├── macros/
│   │   └── cross_db.sql      # BigQuery/DuckDB compatibility shims
│   ├── dbt_project.yml
│   ├── edr_profiles.yml      # Elementary edr monitor profile
│   ├── packages.yml          # elementary, dbt-expectations
│   └── profiles.yml          # dev=DuckDB, prod=BigQuery
├── dashboard/
│   ├── pages/
│   │   ├── index.md          # Overview: KPIs, volume, top complaints
│   │   ├── insights/index.md # Resolution time, open requests, channels
│   │   └── health.md         # Pipeline health: freshness, anomalies, dbt tests
│   ├── vercel.json           # Vercel deployment + cache headers
│   └── package.json
└── infra/
    ├── main.tf               # BQ datasets, GCS, SAs, WIF
    ├── variables.tf
    ├── outputs.tf
    └── terraform.tfvars.template
```

## Dashboard pages

| Page | URL | Description |
|------|-----|-------------|
| Overview | `/` | 30-day KPIs, daily volume, top complaints, borough breakdown |
| Insights | `/insights` | Resolution times, open request aging, channel mix |
| Health | `/health` | Row count anomalies, dbt test results, Elementary output |

## Monitoring

The pipeline is considered healthy when:
1. GitHub Actions badge is green (workflow ran without error)
2. `dbt source freshness` passes (data updated within 25 hours)
3. Row count is within 30% of the 7-day rolling average
4. All dbt tests pass (warnings reviewed, failures block deploy)

Anomalies surface automatically on the `/health` Evidence page.
