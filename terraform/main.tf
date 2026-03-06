provider "google" {
  project = var.project_id
  region  = "us-central1"
}

# 1. BigQuery Datasets
resource "google_bigquery_dataset" "raw" {
  dataset_id = "nyc_311_raw"
  location   = "US"
}

resource "google_bigquery_dataset" "prod" {
  dataset_id = "nyc_311_prod"
  location   = "US"
}

# 2. Pipeline Service Account
resource "google_service_account" "pipeline_sa" {
  account_id   = "nyc-pipeline-runner"
  display_name = "SA for DLT and DBT"
}

# 3. Permissions (Grant SA access to BigQuery)
resource "google_project_iam_member" "bq_admin" {
  project = var.project_id
  role    = "roles/bigquery.admin"
  member  = "serviceAccount:${google_service_account.pipeline_sa.email}"
}