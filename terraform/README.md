# OpenClaw on Google Cloud Run - Terraform

This directory contains Terraform configuration to deploy OpenClaw on Google Cloud Run with persistent storage.

## Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Google Cloud Platform                     │
│                                                              │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐ │
│  │   Cloud      │     │   Cloud      │     │    Cloud     │ │
│  │   Build      │────▶│  Artifact    │────▶│    Run       │ │
│  │   (CI/CD)    │     │  Registry    │     │  (Gateway)   │ │
│  └──────────────┘     └──────────────┘     └──────┬───────┘ │
│                                                    │         │
│                                                    ▼         │
│  ┌──────────────┐     ┌──────────────┐     ┌──────────────┐ │
│  │   Secret     │     │    IAP       │     │    Cloud     │ │
│  │   Manager    │     │   (Auth)     │     │   Storage    │ │
│  │  (API Keys)  │     │  (Optional)  │     │ (Persistent) │ │
│  └──────────────┘     └──────────────┘     └──────────────┘ │
│                                                              │
└─────────────────────────────────────────────────────────────┘
```

## Prerequisites

1. **GCP Account** with billing enabled
2. **gcloud CLI** installed and authenticated
3. **Terraform** >= 1.0 installed
4. **Anthropic API Key** (or OpenAI API Key)

## Quick Start

### 1. Set up GCP Project

```bash
# Create a new project (or use existing)
gcloud projects create my-openclaw-project --name="OpenClaw"
gcloud config set project my-openclaw-project

# Enable billing
# Go to: https://console.cloud.google.com/billing

# Authenticate Terraform
gcloud auth application-default login
```

### 2. Configure Terraform

```bash
cd terraform

# Copy example variables
cp terraform.tfvars.example terraform.tfvars

# Edit with your values
vim terraform.tfvars
```

### 3. Initialize and Apply

```bash
# Initialize Terraform
terraform init

# Preview changes
terraform plan

# Apply (creates all resources)
terraform apply
```

### 4. Set Secrets

After Terraform creates the infrastructure, add your secret values:

```bash
# Set Anthropic API Key
echo -n "sk-ant-..." | gcloud secrets versions add openclaw-anthropic-api-key --data-file=-

# Set Gateway Token (generate a random one)
openssl rand -hex 32 | gcloud secrets versions add openclaw-gateway-token --data-file=-
```

### 5. Build and Deploy Container

```bash
# From the repository root
cd ..

# Build and push to Artifact Registry
gcloud builds submit --config=cloudbuild.yaml \
  --substitutions=_REGION=us-central1,_REPOSITORY=openclaw-images,_SERVICE_NAME=openclaw-gateway

# Or use the Terraform output command
terraform -chdir=terraform output -raw next_steps
```

### 6. Access Your Gateway

```bash
# Get the service URL
terraform -chdir=terraform output cloud_run_url

# Get your gateway token
gcloud secrets versions access latest --secret=openclaw-gateway-token

# Open in browser
# https://your-service-url.run.app?token=YOUR_TOKEN
```

## Files

| File | Description |
|------|-------------|
| `main.tf` | Provider configuration, required APIs |
| `variables.tf` | Input variable definitions |
| `outputs.tf` | Output values |
| `cloud-run.tf` | Cloud Run service |
| `storage.tf` | GCS bucket for persistent data |
| `artifact-registry.tf` | Container image repository |
| `iam.tf` | Service accounts and permissions |
| `secrets.tf` | Secret Manager secrets |
| `build.tf` | Cloud Build trigger (optional) |
| `iap.tf` | Identity-Aware Proxy (optional) |

## Persistence

OpenClaw state is persisted to Cloud Storage using a backup/restore pattern:

- **On startup**: State is restored from GCS
- **Every 5 minutes**: State is synced to GCS
- **On shutdown**: Final sync before container stops

This ensures your paired devices, conversation history, and configuration survive container restarts.

## Cost Estimates

| Resource | Monthly Cost |
|----------|--------------|
| Cloud Run (1 instance, always-on) | ~$25-50 |
| Cloud Storage | ~$0.02/GB |
| Artifact Registry | ~$0.10/GB |
| Secret Manager | ~$0.06/secret |
| **Total (minimal)** | ~$30-60 |

Set `cloud_run_min_instances = 0` for scale-to-zero (lower cost, but 30-60s cold starts).

## Troubleshooting

### Container fails to start

Check Cloud Run logs:

```bash
gcloud run services logs read openclaw-gateway --region=us-central1
```

### Secrets not accessible

Verify the secret has a version:

```bash
gcloud secrets versions list openclaw-anthropic-api-key
```

### GCS sync issues

The service account needs `storage.objectAdmin` on the bucket. Verify:

```bash
gsutil iam get gs://$(terraform output -raw gcs_bucket_name)
```

## Cleanup

To destroy all resources:

```bash
terraform destroy
```

**Warning**: This will delete all data including the GCS bucket contents.
