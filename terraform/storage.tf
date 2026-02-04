# OpenClaw Cloud Run - Cloud Storage for Persistent State

# GCS bucket for OpenClaw persistent data
resource "google_storage_bucket" "openclaw_data" {
  name     = "${local.name_prefix}-data-${local.name_suffix}"
  location = var.region
  project  = var.project_id

  # Use Standard storage class for frequently accessed data
  storage_class = "STANDARD"

  # Enable uniform bucket-level access (recommended)
  uniform_bucket_level_access = true

  # Versioning for data protection
  versioning {
    enabled = true
  }

  # Lifecycle rules to manage old versions
  # Delete archived versions when there are more than 5 newer versions
  lifecycle_rule {
    condition {
      num_newer_versions = 5
      with_state         = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  # Delete archived versions older than 30 days
  lifecycle_rule {
    condition {
      age        = 30
      with_state = "ARCHIVED"
    }
    action {
      type = "Delete"
    }
  }

  labels = local.common_labels

  # Prevent accidental deletion
  force_destroy = false

  depends_on = [google_project_service.required_apis]
}

# Create initial folder structure in the bucket
resource "google_storage_bucket_object" "data_folder" {
  name    = "openclaw-data/.keep"
  content = "# OpenClaw persistent data folder"
  bucket  = google_storage_bucket.openclaw_data.name
}

resource "google_storage_bucket_object" "skills_folder" {
  name    = "skills/.keep"
  content = "# OpenClaw skills folder"
  bucket  = google_storage_bucket.openclaw_data.name
}
