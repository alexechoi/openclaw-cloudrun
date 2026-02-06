# OpenClaw Cloud Run - Cloud Run Service

resource "google_cloud_run_v2_service" "openclaw" {
  name     = "${local.name_prefix}-gateway"
  location = var.region
  project  = var.project_id

  # Use gen2 execution environment for better performance
  launch_stage = "GA"

  template {
    # Service account
    service_account = google_service_account.openclaw.email

    # Scaling configuration
    scaling {
      min_instance_count = var.cloud_run_min_instances
      max_instance_count = var.cloud_run_max_instances
    }

    # Request timeout
    timeout = "${var.cloud_run_timeout}s"

    # Container configuration
    containers {
      image = local.container_image

      # Resource limits
      resources {
        limits = {
          cpu    = var.cloud_run_cpu
          memory = var.cloud_run_memory
        }
        cpu_idle          = true # Allow CPU to be throttled when idle
        startup_cpu_boost = true # Boost CPU during startup
      }

      # Port configuration
      ports {
        container_port = 8080
        name           = "http1"
      }

      # Environment variables
      # Note: PORT is automatically set by Cloud Run to the container_port value

      env {
        name  = "GCS_BUCKET"
        value = google_storage_bucket.openclaw_data.name
      }

      env {
        name  = "OPENCLAW_STATE_DIR"
        value = "/data/.openclaw"
      }

      env {
        name  = "OPENCLAW_WORKSPACE_DIR"
        value = "/data/workspace"
      }

      env {
        name  = "GATEWAY_BIND"
        value = var.gateway_bind
      }

      env {
        name  = "SYNC_INTERVAL"
        value = "300" # 5 minutes
      }

      env {
        name  = "NODE_ENV"
        value = "production"
      }

      # Node.js memory configuration (set heap to ~75% of container memory)
      env {
        name  = "NODE_OPTIONS"
        value = "--max-old-space-size=1536"
      }

      # Secrets from Secret Manager
      env {
        name = "ANTHROPIC_API_KEY"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.anthropic_api_key.secret_id
            version = "latest"
          }
        }
      }

      env {
        name = "OPENCLAW_GATEWAY_TOKEN"
        value_source {
          secret_key_ref {
            secret  = google_secret_manager_secret.gateway_token.secret_id
            version = "latest"
          }
        }
      }

      # Note: Optional secrets (Telegram, Discord, Slack) can be added here
      # after their secret versions are created in Secret Manager.
      # Uncomment the env blocks below once you've added secret values.
      #
      # env {
      #   name = "TELEGRAM_BOT_TOKEN"
      #   value_source {
      #     secret_key_ref {
      #       secret  = google_secret_manager_secret.telegram_bot_token.secret_id
      #       version = "latest"
      #     }
      #   }
      # }
      #
      # env {
      #   name = "DISCORD_BOT_TOKEN"
      #   value_source {
      #     secret_key_ref {
      #       secret  = google_secret_manager_secret.discord_bot_token.secret_id
      #       version = "latest"
      #     }
      #   }
      # }

      # Startup probe
      startup_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 10
        timeout_seconds       = 3
        period_seconds        = 5
        failure_threshold     = 30 # Allow up to 150s for startup
      }

      # Liveness probe
      liveness_probe {
        http_get {
          path = "/health"
          port = 8080
        }
        initial_delay_seconds = 60
        timeout_seconds       = 3
        period_seconds        = 30
        failure_threshold     = 3
      }
    }

    # VPC connector (optional, for private networking)
    # vpc_access {
    #   connector = "projects/${var.project_id}/locations/${var.region}/connectors/openclaw-vpc"
    #   egress    = "ALL_TRAFFIC"
    # }

    labels = local.common_labels
  }

  # Traffic routing - all traffic to latest revision
  traffic {
    type    = "TRAFFIC_TARGET_ALLOCATION_TYPE_LATEST"
    percent = 100
  }

  labels = local.common_labels

  depends_on = [
    google_project_service.required_apis,
    google_secret_manager_secret.anthropic_api_key,
    google_secret_manager_secret.gateway_token,
  ]
}

# IAM: Allow unauthenticated access (if enabled)
resource "google_cloud_run_v2_service_iam_member" "public_access" {
  count = var.allow_unauthenticated ? 1 : 0

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.openclaw.name
  role     = "roles/run.invoker"
  member   = "allUsers"
}

# IAM: Allow authenticated users only (if not public)
resource "google_cloud_run_v2_service_iam_member" "authenticated_access" {
  count = var.allow_unauthenticated ? 0 : 1

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.openclaw.name
  role     = "roles/run.invoker"
  member   = "allAuthenticatedUsers"
}
