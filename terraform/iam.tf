# OpenClaw Cloud Run - IAM Configuration

# Service account for Cloud Run
resource "google_service_account" "openclaw" {
  account_id   = "${local.name_prefix}-run"
  display_name = "OpenClaw Cloud Run Service Account"
  description  = "Service account for OpenClaw Cloud Run service"
  project      = var.project_id
}

# Grant GCS access to the service account
resource "google_storage_bucket_iam_member" "openclaw_gcs_admin" {
  bucket = google_storage_bucket.openclaw_data.name
  role   = "roles/storage.objectAdmin"
  member = "serviceAccount:${google_service_account.openclaw.email}"
}

# Grant Secret Manager access to the service account
resource "google_project_iam_member" "openclaw_secret_accessor" {
  project = var.project_id
  role    = "roles/secretmanager.secretAccessor"
  member  = "serviceAccount:${google_service_account.openclaw.email}"
}

# Grant logging access
resource "google_project_iam_member" "openclaw_log_writer" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.openclaw.email}"
}

# Grant metrics access
resource "google_project_iam_member" "openclaw_metric_writer" {
  project = var.project_id
  role    = "roles/monitoring.metricWriter"
  member  = "serviceAccount:${google_service_account.openclaw.email}"
}

# Grant trace access
resource "google_project_iam_member" "openclaw_trace_agent" {
  project = var.project_id
  role    = "roles/cloudtrace.agent"
  member  = "serviceAccount:${google_service_account.openclaw.email}"
}
