# OpenClaw Cloud Run - Cloud Build Configuration
# This file is optional - only needed if cloud_build_enabled = true

# Cloud Build trigger for GitHub pushes
resource "google_cloudbuild_trigger" "openclaw" {
  count = var.cloud_build_enabled ? 1 : 0

  name        = "${local.name_prefix}-build"
  description = "Build and deploy OpenClaw on push to ${var.github_branch}"
  project     = var.project_id
  location    = var.region

  # GitHub configuration
  github {
    owner = var.github_repo_owner
    name  = var.github_repo_name

    push {
      branch = "^${var.github_branch}$"
    }
  }

  # Build configuration file
  filename = "cloudbuild.yaml"

  # Substitution variables
  substitutions = {
    _REGION       = var.region
    _SERVICE_NAME = google_cloud_run_v2_service.openclaw.name
    _REPOSITORY   = google_artifact_registry_repository.openclaw.name
    _IMAGE_NAME   = "openclaw"
  }

  # Service account for builds
  service_account = google_service_account.cloud_build.id

  depends_on = [google_project_service.required_apis]
}

# Service account for Cloud Build
resource "google_service_account" "cloud_build" {
  account_id   = "${local.name_prefix}-build"
  display_name = "OpenClaw Cloud Build Service Account"
  description  = "Service account for Cloud Build to deploy OpenClaw"
  project      = var.project_id
}

# Grant Cloud Build permissions
resource "google_project_iam_member" "cloud_build_run_admin" {
  project = var.project_id
  role    = "roles/run.admin"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_project_iam_member" "cloud_build_sa_user" {
  project = var.project_id
  role    = "roles/iam.serviceAccountUser"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

resource "google_project_iam_member" "cloud_build_logs" {
  project = var.project_id
  role    = "roles/logging.logWriter"
  member  = "serviceAccount:${google_service_account.cloud_build.email}"
}

# Allow Cloud Build to push to Artifact Registry
resource "google_artifact_registry_repository_iam_member" "cloud_build_sa_writer" {
  provider = google-beta

  location   = google_artifact_registry_repository.openclaw.location
  repository = google_artifact_registry_repository.openclaw.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${google_service_account.cloud_build.email}"
}
