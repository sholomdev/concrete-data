terraform {
  required_version = ">= 1.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  # Replace YOUR_GCP_PROJECT_ID with your actual project ID (no variable interpolation allowed here)
  backend "gcs" {
    bucket = "YOUR_GCP_PROJECT_ID-tf-state"
    prefix = "concrete-data/terraform/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ─── Required APIs ───────────────────────────────────────────────────────────

resource "google_project_service" "apis" {
  for_each = toset([
    "bigquery.googleapis.com",
    "storage.googleapis.com",
    "iam.googleapis.com",
    "iamcredentials.googleapis.com",
    "sts.googleapis.com",
    "run.googleapis.com",
    "artifactregistry.googleapis.com",
    "cloudscheduler.googleapis.com",
    "cloudbuild.googleapis.com",
  ])
  service            = each.value
  disable_on_destroy = false
}

# ─── Locals ──────────────────────────────────────────────────────────────────

locals {
  labels = {
    project     = "concrete-data"
    environment = var.environment
    managed_by  = "terraform"
  }
  image_url = "${var.region}-docker.pkg.dev/${var.project_id}/concrete-data/pipeline:latest"
}

# ─── BigQuery ────────────────────────────────────────────────────────────────

resource "google_bigquery_dataset" "raw" {
  dataset_id    = "nyc_311_raw"
  friendly_name = "NYC 311 — raw (dlt-managed)"
  location      = var.bq_location
  description   = "Raw 311 requests loaded by dlt. Schema managed by dlt."

  delete_contents_on_destroy = false
  labels                     = local.labels
}

resource "google_bigquery_dataset" "staging" {
  dataset_id    = "nyc_311_staging"
  friendly_name = "NYC 311 — staging (dbt views)"
  location      = var.bq_location
  labels        = local.labels
}

resource "google_bigquery_dataset" "marts" {
  dataset_id    = "nyc_311_marts"
  friendly_name = "NYC 311 — marts (dbt tables)"
  location      = var.bq_location
  labels        = local.labels
}

resource "google_bigquery_dataset" "elementary" {
  dataset_id    = "elementary"
  friendly_name = "Elementary observability"
  location      = var.bq_location
  labels        = local.labels
}

# ─── GCS — raw backup ────────────────────────────────────────────────────────

resource "google_storage_bucket" "raw_backup" {
  name          = "${var.project_id}-nyc311-raw-backup"
  location      = var.gcs_location
  force_destroy = false

  uniform_bucket_level_access = true

  lifecycle_rule {
    condition { age = 90 }
    action    { type = "Delete" }
  }

  labels = local.labels
}

# ─── GCS — Terraform state ───────────────────────────────────────────────────

resource "google_storage_bucket" "tf_state" {
  name          = "${var.project_id}-tf-state"
  location      = var.gcs_location
  force_destroy = false

  versioning { enabled = true }

  uniform_bucket_level_access = true
  labels                      = local.labels
}

# ─── GCS — Dashboard static hosting ─────────────────────────────────────────

resource "google_storage_bucket" "dashboard" {
  name          = "${var.project_id}-nyc311-dashboard"
  location      = var.gcs_location
  force_destroy = true

  # Website hosting requires uniform_bucket_level_access = false
  uniform_bucket_level_access = false

  website {
    main_page_suffix = "index.html"
    not_found_page   = "404.html"
  }

  cors {
    origin          = ["*"]
    method          = ["GET", "HEAD"]
    response_header = ["*"]
    max_age_seconds = 3600
  }

  labels = local.labels
}

resource "google_storage_bucket_iam_member" "dashboard_public" {
  bucket = google_storage_bucket.dashboard.name
  role   = "roles/storage.objectViewer"
  member = "allUsers"
}

# ─── Artifact Registry — Docker images ───────────────────────────────────────

resource "google_artifact_registry_repository" "pipeline" {
  repository_id = "concrete-data"
  format        = "DOCKER"
  location      = var.region
  description   = "Docker images for the NYC 311 pipeline"
  labels        = local.labels

  depends_on = [google_project_service.apis]
}

# ─── Service accounts ────────────────────────────────────────────────────────

# One SA runs everything inside the Cloud Run Job container
resource "google_service_account" "pipeline" {
  account_id   = "nyc311-pipeline"
  display_name = "NYC 311 pipeline"
  description  = "Runs inside Cloud Run Job — dlt, dbt, dashboard deploy."
}

# Separate SA for Cloud Scheduler (only needs run.invoker)
resource "google_service_account" "scheduler" {
  account_id   = "nyc311-scheduler"
  display_name = "NYC 311 scheduler"
  description  = "Used by Cloud Scheduler to trigger the Cloud Run Job."
}

# ─── IAM — pipeline SA ───────────────────────────────────────────────────────

locals {
  pipeline_project_roles = [
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
    "roles/logging.logWriter",
    "roles/artifactregistry.writer",  # push images from GitHub Actions via WIF
  ]
}

resource "google_project_iam_member" "pipeline_roles" {
  for_each = toset(local.pipeline_project_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.pipeline.email}"
}

resource "google_storage_bucket_iam_member" "pipeline_backup_gcs" {
  bucket = google_storage_bucket.raw_backup.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pipeline.email}"
}

resource "google_storage_bucket_iam_member" "pipeline_dashboard_gcs" {
  bucket = google_storage_bucket.dashboard.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pipeline.email}"
}

# ─── IAM — scheduler SA ──────────────────────────────────────────────────────

resource "google_project_iam_member" "scheduler_run_invoker" {
  project = var.project_id
  role    = "roles/run.invoker"
  member  = "serviceAccount:${google_service_account.scheduler.email}"
}

# ─── Cloud Run Job ───────────────────────────────────────────────────────────

resource "google_cloud_run_v2_job" "pipeline" {
  name     = "nyc-311-pipeline"
  location = var.region
  labels   = local.labels

  template {
    labels = local.labels

    template {
      service_account = google_service_account.pipeline.email
      max_retries     = 2
      timeout         = "3600s"

      containers {
        image = local.image_url

        env {
          name  = "ENV"
          value = "prod"
        }
        env {
          name  = "GCP_PROJECT_ID"
          value = var.project_id
        }
        env {
          name  = "DASHBOARD_BUCKET"
          value = google_storage_bucket.dashboard.name
        }
        env {
          name  = "INITIAL_START_DATE"
          value = "2025-01-01T00:00:00"
        }

        resources {
          limits = {
            cpu    = "2"
            memory = "2Gi"
          }
        }
      }
    }
  }

  depends_on = [
    google_project_service.apis,
    google_artifact_registry_repository.pipeline,
  ]

  lifecycle {
    # Don't let Terraform revert image tags that CI updates
    ignore_changes = [template[0].template[0].containers[0].image]
  }
}

# ─── Cloud Scheduler — daily trigger ─────────────────────────────────────────

resource "google_cloud_scheduler_job" "pipeline_daily" {
  name      = "nyc-311-pipeline-daily"
  region    = var.region
  schedule  = "0 5 * * *"
  time_zone = "UTC"

  retry_config {
    retry_count = 1
  }

  http_target {
    uri         = "https://${var.region}-run.googleapis.com/apis/run.googleapis.com/v1/namespaces/${var.project_id}/jobs/nyc-311-pipeline:run"
    http_method = "POST"
    body        = base64encode("{}")

    oauth_token {
      service_account_email = google_service_account.scheduler.email
    }
  }

  depends_on = [google_project_service.apis]
}

# ─── Workload Identity Federation — GitHub Actions ───────────────────────────

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions-pool"
  display_name              = "GitHub Actions"
  depends_on                = [google_project_service.apis]
}

resource "google_iam_workload_identity_pool_provider" "github" {
  workload_identity_pool_id          = google_iam_workload_identity_pool.github.workload_identity_pool_id
  workload_identity_pool_provider_id = "github-provider"
  display_name                       = "GitHub OIDC"

  oidc {
    issuer_uri = "https://token.actions.githubusercontent.com"
  }

  attribute_mapping = {
    "google.subject"       = "assertion.sub"
    "attribute.actor"      = "assertion.actor"
    "attribute.repository" = "assertion.repository"
  }

  attribute_condition = "assertion.repository == '${var.github_repo}'"
}

# GitHub Actions authenticates as pipeline SA to push images and trigger jobs
resource "google_service_account_iam_member" "pipeline_wif" {
  service_account_id = google_service_account.pipeline.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}
