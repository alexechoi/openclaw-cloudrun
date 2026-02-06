# OpenClaw Cloud Run - Artifact Registry

# Container image repository
resource "google_artifact_registry_repository" "openclaw" {
  provider = google-beta

  location      = var.region
  repository_id = "${local.name_prefix}-images"
  description   = "Docker images for OpenClaw"
  format        = "DOCKER"

  labels = local.common_labels

  # Clean up old images automatically
  cleanup_policies {
    id     = "keep-recent"
    action = "KEEP"
    most_recent_versions {
      keep_count = 10
    }
  }

  cleanup_policies {
    id     = "delete-old-untagged"
    action = "DELETE"
    condition {
      tag_state  = "UNTAGGED"
      older_than = "604800s" # 7 days
    }
  }

  depends_on = [google_project_service.required_apis]
}

# Allow Cloud Build to push images
resource "google_artifact_registry_repository_iam_member" "cloud_build_writer" {
  provider = google-beta

  location   = google_artifact_registry_repository.openclaw.location
  repository = google_artifact_registry_repository.openclaw.name
  role       = "roles/artifactregistry.writer"
  member     = "serviceAccount:${data.google_project.current.number}@cloudbuild.gserviceaccount.com"

  depends_on = [google_project_service.required_apis]
}

# Allow Cloud Run service account to pull images
resource "google_artifact_registry_repository_iam_member" "cloud_run_reader" {
  provider = google-beta

  location   = google_artifact_registry_repository.openclaw.location
  repository = google_artifact_registry_repository.openclaw.name
  role       = "roles/artifactregistry.reader"
  member     = "serviceAccount:${google_service_account.openclaw.email}"
}

# Get current project info
data "google_project" "current" {
  project_id = var.project_id
}

# Container image reference
locals {
  artifact_registry_image = "${var.region}-docker.pkg.dev/${var.project_id}/${google_artifact_registry_repository.openclaw.name}/openclaw"
  container_image         = var.container_image != "" ? var.container_image : "${local.artifact_registry_image}:latest"
}
