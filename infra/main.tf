terraform {
  required_version = ">= 1.7"

  required_providers {
    google = {
      source  = "hashicorp/google"
      version = "~> 5.0"
    }
  }

  backend "gcs" {
    bucket = "YOUR_TERRAFORM_STATE_BUCKET"
    prefix = "concrete-data/terraform/state"
  }
}

provider "google" {
  project = var.project_id
  region  = var.region
}

# ─── BigQuery ────────────────────────────────────────────────────────────────

resource "google_bigquery_dataset" "raw" {
  dataset_id    = "nyc_311_raw"
  friendly_name = "NYC 311 — raw (dlt-managed)"
  location      = var.bq_location
  description   = "Raw 311 requests loaded by dlt. Schema managed by dlt."

  delete_contents_on_destroy = false

  labels = local.labels
}

resource "google_bigquery_dataset" "staging" {
  dataset_id    = "nyc_311_staging"
  friendly_name = "NYC 311 — staging (dbt views)"
  location      = var.bq_location

  labels = local.labels
}

resource "google_bigquery_dataset" "marts" {
  dataset_id    = "nyc_311_marts"
  friendly_name = "NYC 311 — marts (dbt tables)"
  location      = var.bq_location

  labels = local.labels
}

resource "google_bigquery_dataset" "elementary" {
  dataset_id    = "elementary"
  friendly_name = "Elementary observability"
  location      = var.bq_location

  labels = local.labels
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
  labels = local.labels
}

# ─── Service accounts ────────────────────────────────────────────────────────

resource "google_service_account" "pipeline" {
  account_id   = "dlt-pipeline"
  display_name = "dlt pipeline — NYC 311"
  description  = "Used by dlt in GitHub Actions to load data into BigQuery and GCS."
}

resource "google_service_account" "dbt" {
  account_id   = "dbt-runner"
  display_name = "dbt runner — NYC 311"
  description  = "Used by dbt in GitHub Actions to transform data in BigQuery."
}

resource "google_service_account" "dashboard" {
  account_id   = "evidence-dashboard"
  display_name = "Evidence dashboard reader"
  description  = "Read-only access to marts dataset for the Evidence build."
}

# ─── IAM — pipeline SA ───────────────────────────────────────────────────────

locals {
  pipeline_bq_roles = [
    "roles/bigquery.dataEditor",
    "roles/bigquery.jobUser",
  ]
  labels = {
    project     = "concrete-data"
    environment = var.environment
    managed_by  = "terraform"
  }
}

resource "google_project_iam_member" "pipeline_bq" {
  for_each = toset(local.pipeline_bq_roles)
  project  = var.project_id
  role     = each.value
  member   = "serviceAccount:${google_service_account.pipeline.email}"
}

resource "google_storage_bucket_iam_member" "pipeline_gcs" {
  bucket = google_storage_bucket.raw_backup.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.pipeline.email}"
}

# ─── IAM — dbt SA ────────────────────────────────────────────────────────────

resource "google_bigquery_dataset_iam_member" "dbt_raw_reader" {
  dataset_id = google_bigquery_dataset.raw.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.dbt.email}"
}

resource "google_bigquery_dataset_iam_member" "dbt_staging_editor" {
  dataset_id = google_bigquery_dataset.staging.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dbt.email}"
}

resource "google_bigquery_dataset_iam_member" "dbt_marts_editor" {
  dataset_id = google_bigquery_dataset.marts.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dbt.email}"
}

resource "google_bigquery_dataset_iam_member" "dbt_elementary_editor" {
  dataset_id = google_bigquery_dataset.elementary.dataset_id
  role       = "roles/bigquery.dataEditor"
  member     = "serviceAccount:${google_service_account.dbt.email}"
}

resource "google_project_iam_member" "dbt_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.dbt.email}"
}

# ─── IAM — dashboard SA ──────────────────────────────────────────────────────

resource "google_bigquery_dataset_iam_member" "dashboard_marts_reader" {
  dataset_id = google_bigquery_dataset.marts.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.dashboard.email}"
}

resource "google_bigquery_dataset_iam_member" "dashboard_elementary_reader" {
  dataset_id = google_bigquery_dataset.elementary.dataset_id
  role       = "roles/bigquery.dataViewer"
  member     = "serviceAccount:${google_service_account.dashboard.email}"
}

resource "google_project_iam_member" "dashboard_job_user" {
  project = var.project_id
  role    = "roles/bigquery.jobUser"
  member  = "serviceAccount:${google_service_account.dashboard.email}"
}

# ─── Workload Identity Federation — GitHub Actions ───────────────────────────

resource "google_iam_workload_identity_pool" "github" {
  workload_identity_pool_id = "github-actions-pool"
  display_name              = "GitHub Actions"
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

resource "google_service_account_iam_member" "pipeline_wif" {
  service_account_id = google_service_account.pipeline.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

resource "google_service_account_iam_member" "dbt_wif" {
  service_account_id = google_service_account.dbt.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}

resource "google_service_account_iam_member" "dashboard_wif" {
  service_account_id = google_service_account.dashboard.name
  role               = "roles/iam.workloadIdentityUser"
  member             = "principalSet://iam.googleapis.com/${google_iam_workload_identity_pool.github.name}/attribute.repository/${var.github_repo}"
}
