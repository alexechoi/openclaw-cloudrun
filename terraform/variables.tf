# OpenClaw Cloud Run - Input Variables

variable "project_id" {
  description = "GCP project ID"
  type        = string
}

variable "region" {
  description = "GCP region for Cloud Run and other resources"
  type        = string
  default     = "us-central1"
}

variable "environment" {
  description = "Environment name (e.g., dev, staging, prod)"
  type        = string
  default     = "prod"
}

# Cloud Run configuration
variable "cloud_run_cpu" {
  description = "CPU allocation for Cloud Run (e.g., '1', '2', '4')"
  type        = string
  default     = "1"
}

variable "cloud_run_memory" {
  description = "Memory allocation for Cloud Run (e.g., '512Mi', '1Gi', '2Gi')"
  type        = string
  default     = "1Gi"
}

variable "cloud_run_min_instances" {
  description = "Minimum number of Cloud Run instances (0 for scale-to-zero, 1+ for always-on)"
  type        = number
  default     = 1
}

variable "cloud_run_max_instances" {
  description = "Maximum number of Cloud Run instances"
  type        = number
  default     = 1
}

variable "cloud_run_timeout" {
  description = "Request timeout in seconds (max 3600 for gen2)"
  type        = number
  default     = 300
}

# Container configuration
variable "container_image" {
  description = "Container image to deploy (leave empty to use Artifact Registry image)"
  type        = string
  default     = ""
}

# Gateway configuration
variable "gateway_bind" {
  description = "Gateway bind mode ('lan' for external access)"
  type        = string
  default     = "lan"
}

variable "gateway_port" {
  description = "Port the gateway listens on inside the container"
  type        = number
  default     = 18789
}

# Authentication
variable "allow_unauthenticated" {
  description = "Allow unauthenticated access to Cloud Run (set false for IAP)"
  type        = bool
  default     = false
}

variable "iap_enabled" {
  description = "Enable Identity-Aware Proxy for authentication"
  type        = bool
  default     = false
}

variable "iap_oauth_client_id" {
  description = "OAuth client ID for IAP (required if iap_enabled=true)"
  type        = string
  default     = ""
}

variable "iap_oauth_client_secret" {
  description = "OAuth client secret for IAP (required if iap_enabled=true)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "iap_allowed_members" {
  description = "List of members allowed through IAP (e.g., ['user:alice@example.com'])"
  type        = list(string)
  default     = []
}

# Cloud Build
variable "github_repo_owner" {
  description = "GitHub repository owner (for Cloud Build trigger)"
  type        = string
  default     = ""
}

variable "github_repo_name" {
  description = "GitHub repository name (for Cloud Build trigger)"
  type        = string
  default     = "openclaw"
}

variable "github_branch" {
  description = "GitHub branch to trigger builds on"
  type        = string
  default     = "main"
}

variable "cloud_build_enabled" {
  description = "Enable Cloud Build trigger for CI/CD"
  type        = bool
  default     = false
}
