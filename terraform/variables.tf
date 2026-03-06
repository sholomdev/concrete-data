variable "project_id" {
  type        = string
  description = "The unique GCP Project ID"
  # No default value here! This forces you to provide one.
}

variable "region" {
  type        = string
  description = "GCP Region"
  default     = "us-central1"
}