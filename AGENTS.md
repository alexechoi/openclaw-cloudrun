# AGENTS.md

Tiny instructions for AI agents working in this repo.

## What this repo is

`openclaw-cloudrun` is a **thin Cloud Run overlay** on top of upstream OpenClaw.
It does not contain the OpenClaw source. The runtime image comes from
`ghcr.io/openclaw/openclaw:<version>` (multi-arch, built and published by
upstream on every release). Everything in this repo is *just* what's needed
to deploy that image on Google Cloud Run with persistent state.

Upstream source: <https://github.com/openclaw/openclaw>.

## Repo layout

| Path | What it is |
| --- | --- |
| `Dockerfile.cloudrun` | Overlay on `ghcr.io/openclaw/openclaw:${OPENCLAW_VERSION}` adding gsutil + entrypoint. Default `OPENCLAW_VERSION=latest`. |
| `scripts/cloudrun-entrypoint.sh` | The only meaningful piece of code here. Handles GCS rsync, headless config patching, gateway launch, signal forwarding. |
| `cloudbuild.yaml` / `cloudbuild.build.yaml` | Cloud Build pipelines. `.build.yaml` is build+push only; `.yaml` is build+push+deploy. |
| `.gcloudignore` / `.dockerignore` | Whitelist only the Dockerfile + entrypoint into the build context. |
| `terraform/` | Optional IaC (Cloud Run, Artifact Registry, GCS, Secret Manager, IAM, Cloud Build trigger). |
| `README.md` | The full deploy guide. Read this before changing anything else. |

## Hard rules

- **Do not re-add upstream openclaw source.** No `src/`, `extensions/`, `apps/`,
  `package.json`, `pnpm-lock.yaml`, etc. The overlay model only works because
  this repo has no build of its own.
- **Do not add npm / pnpm / bun dependencies.** This repo has no Node
  package; the runtime ships in the upstream base image.
- **Bug in the gateway itself?** Fix it upstream
  (<https://github.com/openclaw/openclaw>) and bump `OPENCLAW_VERSION` here.
  Do not patch the source through this repo.
- **Bug in the Cloud Run integration?** That's `scripts/cloudrun-entrypoint.sh`
  or `Dockerfile.cloudrun` -- fix here.
- **Secrets.** Never commit `terraform.tfvars`, `terraform.tfstate*`, `.env*`,
  or anything containing API keys / tokens. The root `.gitignore` blocks the
  obvious cases; if you see a near-miss, refuse the commit rather than work
  around it.
- **OPENCLAW_VERSION pinning.** `latest` is the default for convenience, but
  for production deploys prefer pinning a specific tag (e.g. `2026.4.27`)
  via `--build-arg` or Cloud Build substitutions, then bump in a PR after
  testing.

## Common operations

| Goal | Command |
| --- | --- |
| Build + push image | `gcloud builds submit --config=cloudbuild.build.yaml --substitutions=_REGION=us-central1,_REPOSITORY=docker,_IMAGE_NAME=openclaw,_OPENCLAW_VERSION=latest` |
| Pin a specific upstream version | Add `,_OPENCLAW_VERSION=2026.4.27` to the substitutions above |
| Roll service to fresh image | `gcloud run services update <SERVICE> --region=<REGION> --image=<IMAGE>:latest` |
| Tail logs | `gcloud run services logs read <SERVICE> --region=<REGION> --limit=200` |
| Inspect synced state | `gsutil ls -l gs://<BUCKET>/openclaw-data/` |

## When debugging gateway behavior

1. Check the published openclaw version actually runs:
   `docker pull ghcr.io/openclaw/openclaw:latest && docker run --rm ghcr.io/openclaw/openclaw:latest --help`.
2. Reproduce the issue with the upstream image alone (no Cloud Run wrapper).
   If it repros there, it's an upstream bug -- file there, not here.
3. If it only fails on Cloud Run, the suspect is `cloudrun-entrypoint.sh`,
   the env vars wired into the service, or IAM on the runtime service
   account. Read recent revisions' logs in Cloud Logging filtered by
   `resource.type=cloud_run_revision`.

## Security defaults the entrypoint enforces

The entrypoint patches `openclaw.json` so token-only auth works in a headless
environment. The flags it sets are dangerous if the gateway is exposed without
a strong token:

- `gateway.controlUi.allowInsecureAuth: true`
- `gateway.controlUi.dangerouslyDisableDeviceAuth: true`
- `gateway.controlUi.allowedOrigins`: merged from `OPENCLAW_CONTROL_UI_ALLOWED_ORIGINS`

Before changing this behavior, read the relevant section in `README.md` --
removing `dangerouslyDisableDeviceAuth` will lock everyone out (no operator
exists in the container to approve pairing requests).
