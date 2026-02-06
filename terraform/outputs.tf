# OpenClaw Cloud Run - Outputs

output "cloud_run_url" {
  description = "URL of the Cloud Run service"
  value       = google_cloud_run_v2_service.openclaw.uri
}

output "cloud_run_service_name" {
  description = "Name of the Cloud Run service"
  value       = google_cloud_run_v2_service.openclaw.name
}

output "gcs_bucket_name" {
  description = "Name of the GCS bucket for persistent storage"
  value       = google_storage_bucket.openclaw_data.name
}

output "gcs_bucket_url" {
  description = "URL of the GCS bucket"
  value       = google_storage_bucket.openclaw_data.url
}

output "artifact_registry_repository" {
  description = "Artifact Registry repository URL"
  value       = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.openclaw.name}"
}

output "service_account_email" {
  description = "Service account email used by Cloud Run"
  value       = google_service_account.openclaw.email
}

output "container_image" {
  description = "Container image being deployed"
  value       = local.container_image
}

# Instructions for initial setup
output "next_steps" {
  description = "Next steps after terraform apply"
  value       = <<-EOT
    
    ========================================
    OpenClaw Cloud Run Deployment Complete!
    ========================================
    
    1. Set your secrets in Secret Manager:
       gcloud secrets versions add openclaw-anthropic-api-key --data-file=-
       gcloud secrets versions add openclaw-gateway-token --data-file=-
    
    2. Build and push your container image:
       gcloud builds submit --config=cloudbuild.yaml
    
    3. Access your gateway at:
       ${google_cloud_run_v2_service.openclaw.uri}
    
    4. Use this token parameter in the URL:
       ${google_cloud_run_v2_service.openclaw.uri}?token=YOUR_GATEWAY_TOKEN
    
  EOT
}
