# OpenClaw Cloud Run - Secret Manager Secrets

# Anthropic API Key secret
resource "google_secret_manager_secret" "anthropic_api_key" {
  secret_id = "${local.name_prefix}-anthropic-api-key"
  project   = var.project_id

  labels = local.common_labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

# Gateway Token secret
resource "google_secret_manager_secret" "gateway_token" {
  secret_id = "${local.name_prefix}-gateway-token"
  project   = var.project_id

  labels = local.common_labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

# Optional: OpenAI API Key secret (for alternative models)
resource "google_secret_manager_secret" "openai_api_key" {
  secret_id = "${local.name_prefix}-openai-api-key"
  project   = var.project_id

  labels = local.common_labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

# Optional: Telegram Bot Token
resource "google_secret_manager_secret" "telegram_bot_token" {
  secret_id = "${local.name_prefix}-telegram-bot-token"
  project   = var.project_id

  labels = local.common_labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

# Optional: Discord Bot Token
resource "google_secret_manager_secret" "discord_bot_token" {
  secret_id = "${local.name_prefix}-discord-bot-token"
  project   = var.project_id

  labels = local.common_labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

# Optional: Slack tokens
resource "google_secret_manager_secret" "slack_bot_token" {
  secret_id = "${local.name_prefix}-slack-bot-token"
  project   = var.project_id

  labels = local.common_labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

resource "google_secret_manager_secret" "slack_app_token" {
  secret_id = "${local.name_prefix}-slack-app-token"
  project   = var.project_id

  labels = local.common_labels

  replication {
    auto {}
  }

  depends_on = [google_project_service.required_apis]
}

# Grant service account access to all secrets
resource "google_secret_manager_secret_iam_member" "anthropic_access" {
  secret_id = google_secret_manager_secret.anthropic_api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.openclaw.email}"
}

resource "google_secret_manager_secret_iam_member" "gateway_token_access" {
  secret_id = google_secret_manager_secret.gateway_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.openclaw.email}"
}

resource "google_secret_manager_secret_iam_member" "openai_access" {
  secret_id = google_secret_manager_secret.openai_api_key.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.openclaw.email}"
}

resource "google_secret_manager_secret_iam_member" "telegram_access" {
  secret_id = google_secret_manager_secret.telegram_bot_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.openclaw.email}"
}

resource "google_secret_manager_secret_iam_member" "discord_access" {
  secret_id = google_secret_manager_secret.discord_bot_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.openclaw.email}"
}

resource "google_secret_manager_secret_iam_member" "slack_bot_access" {
  secret_id = google_secret_manager_secret.slack_bot_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.openclaw.email}"
}

resource "google_secret_manager_secret_iam_member" "slack_app_access" {
  secret_id = google_secret_manager_secret.slack_app_token.id
  role      = "roles/secretmanager.secretAccessor"
  member    = "serviceAccount:${google_service_account.openclaw.email}"
}
