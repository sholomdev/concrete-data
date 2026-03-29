variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "Default GCP region"
  type        = string
  default     = "us-central1"
}

variable "bq_location" {
  description = "BigQuery dataset location"
  type        = string
  default     = "US"
}

variable "gcs_location" {
  description = "GCS bucket location"
  type        = string
  default     = "US"
}

variable "environment" {
  description = "prod or dev"
  type        = string
  default     = "prod"
}

variable "github_repo" {
  description = "GitHub repo in owner/repo format for WIF"
  type        = string
  # e.g. "sholomdev/concrete-data"
}
