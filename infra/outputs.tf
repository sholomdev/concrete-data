output "pipeline_sa_email" {
  value       = google_service_account.pipeline.email
  description = "Pipeline service account — add as GH secret PIPELINE_SA_EMAIL"
}

output "workload_identity_provider" {
  value       = google_iam_workload_identity_pool_provider.github.name
  description = "WIF provider resource name — add as GH secret WIF_PROVIDER"
}

output "artifact_registry_url" {
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/concrete-data"
  description = "Artifact Registry URL prefix for Docker images"
}

output "cloud_run_job_name" {
  value       = google_cloud_run_v2_job.pipeline.name
  description = "Cloud Run Job name"
}

output "dashboard_bucket" {
  value       = google_storage_bucket.dashboard.name
  description = "GCS dashboard bucket — add as GH secret DASHBOARD_BUCKET"
}

output "dashboard_url" {
  value       = "https://storage.googleapis.com/${google_storage_bucket.dashboard.name}/index.html"
  description = "Public URL of the Evidence dashboard"
}

output "gcs_backup_bucket" {
  value       = google_storage_bucket.raw_backup.url
  description = "GCS backup bucket URL — use in .dlt/config.toml"
}
