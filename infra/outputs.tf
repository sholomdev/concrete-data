output "pipeline_sa_email" {
  value       = google_service_account.pipeline.email
  description = "Email of the dlt pipeline service account — add as GH secret PIPELINE_SA_EMAIL"
}

output "dbt_sa_email" {
  value       = google_service_account.dbt.email
  description = "Email of the dbt runner service account — add as GH secret DBT_SA_EMAIL"
}

output "dashboard_sa_email" {
  value       = google_service_account.dashboard.email
  description = "Email of the Evidence dashboard service account — add as GH secret DASHBOARD_SA_EMAIL"
}

output "workload_identity_provider" {
  value       = google_iam_workload_identity_pool_provider.github.name
  description = "Full WIF provider resource name — add as GH secret WIF_PROVIDER"
}

output "gcs_backup_bucket" {
  value       = google_storage_bucket.raw_backup.url
  description = "GCS backup bucket URL — use in .dlt/config.toml"
}

output "tf_state_bucket" {
  value       = google_storage_bucket.tf_state.name
  description = "Terraform state bucket — update backend.tf before first apply"
}
