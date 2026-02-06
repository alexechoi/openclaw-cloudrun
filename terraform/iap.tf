# OpenClaw Cloud Run - Identity-Aware Proxy Configuration
# This file is optional - only needed if iap_enabled = true
#
# IAP provides Google-based authentication in front of Cloud Run.
# Users must authenticate with their Google account to access the service.
#
# Prerequisites:
# 1. Create an OAuth consent screen in the GCP Console
# 2. Create OAuth credentials (Web application type)
# 3. Set the authorized redirect URI to: https://iap.googleapis.com/v1/oauth/clientIds/{client_id}:handleRedirect
# 4. Provide the client ID and secret to Terraform

# Note: IAP for Cloud Run requires additional setup that cannot be fully
# automated with Terraform. This file provides the IAM bindings.
#
# To enable IAP for Cloud Run:
# 1. Go to Cloud Run in the GCP Console
# 2. Select your service
# 3. Click on "Security" tab
# 4. Enable "Require authentication" and configure IAP
#
# See: https://cloud.google.com/iap/docs/enabling-cloud-run

# Grant IAP-secured access to specified members
resource "google_cloud_run_v2_service_iam_member" "iap_access" {
  for_each = var.iap_enabled ? toset(var.iap_allowed_members) : []

  project  = var.project_id
  location = var.region
  name     = google_cloud_run_v2_service.openclaw.name
  role     = "roles/run.invoker"
  member   = each.value
}

# If IAP is enabled, ensure allUsers and allAuthenticatedUsers are NOT granted access
# This is handled by the conditional in cloud-run.tf

# Output IAP configuration instructions
output "iap_instructions" {
  description = "Instructions for setting up IAP"
  value = var.iap_enabled ? join("\n", [
    "",
    "========================================",
    "Identity-Aware Proxy (IAP) Setup",
    "========================================",
    "",
    "IAP has been partially configured. Complete the setup:",
    "",
    "1. Go to: https://console.cloud.google.com/security/iap?project=${var.project_id}",
    "",
    "2. Find 'Cloud Run' in the resources list",
    "",
    "3. Toggle IAP ON for the '${google_cloud_run_v2_service.openclaw.name}' service",
    "",
    "4. Configure the OAuth consent screen if not already done:",
    "   https://console.cloud.google.com/apis/credentials/consent?project=${var.project_id}",
    "",
    "5. Allowed users have been configured:",
    "   ${join(", ", var.iap_allowed_members)}",
    "",
    "Note: The gateway token is still required after IAP authentication.",
    "Access the service at: ${google_cloud_run_v2_service.openclaw.uri}?token=YOUR_TOKEN",
    "",
  ]) : "IAP is not enabled. Set iap_enabled = true to enable."
}
