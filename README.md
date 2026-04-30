# OpenClaw on Google Cloud Run

This repo is a **thin Cloud Run overlay** on top of upstream [OpenClaw](https://github.com/openclaw/openclaw). It does *not* contain the OpenClaw source — instead it consumes the official multi-arch image upstream publishes on every release at:

```
ghcr.io/openclaw/openclaw:<version>
```

…and adds the three things you need to run it on Cloud Run:

1. The Google Cloud SDK (`gsutil`) so the entrypoint can rsync state to/from a GCS bucket — without it, every cold start would lose channel pairings, sessions, and config.
2. A `/data` state dir owned by the upstream `node` user, since Cloud Run's filesystem is ephemeral but writable.
3. An entrypoint shim ([`scripts/cloudrun-entrypoint.sh`](./scripts/cloudrun-entrypoint.sh)) that handles GCS rsync, headless config patching (token-only auth — see below), and graceful shutdown.

Build time on Cloud Build: **~30–60 s** (just `apt install google-cloud-cli` on top of the upstream image — no pnpm/Bun build required).

## Files in this repo

| Path | Purpose |
| --- | --- |
| [`Dockerfile.cloudrun`](./Dockerfile.cloudrun) | Overlay on `ghcr.io/openclaw/openclaw:${OPENCLAW_VERSION}`; default `latest`. Pin via `--build-arg OPENCLAW_VERSION=2026.4.27` for reproducibility. |
| [`scripts/cloudrun-entrypoint.sh`](./scripts/cloudrun-entrypoint.sh) | GCS rsync + config patcher + signal-aware gateway launcher. |
| [`cloudbuild.build.yaml`](./cloudbuild.build.yaml) | Build + push only (paired with manual `gcloud run deploy`). |
| [`cloudbuild.yaml`](./cloudbuild.yaml) | All-in-one CI: build → push → `gcloud run deploy`. Used by the Terraform-managed Cloud Build trigger. |
| [`.gcloudignore`](./.gcloudignore) / [`.dockerignore`](./.dockerignore) | Whitelist only the Dockerfile + entrypoint into the build context. |
| [`terraform/`](./terraform/) | Full IaC (Cloud Run, Artifact Registry, GCS, Secret Manager, IAM, optional IAP, Cloud Build trigger). See [`terraform/README.md`](./terraform/README.md). |

## How it works

```
Cloud Build (Dockerfile.cloudrun)
        │  pull upstream openclaw image, layer gsutil + entrypoint
        ▼
Artifact Registry (Docker repo)
        │
        ▼
Cloud Run service ── 5 min sync ──► GCS bucket (gs://.../openclaw-data/)
   │  port 8080                              ▲
   │  /data/.openclaw  (state)               │ restore on cold start /
   │  /data/workspace  (workspace)           │ final sync on SIGTERM
   ▼
Secret Manager: openclaw-gateway-token, GEMINI_API_KEY, …
```

On every container start, [`cloudrun-entrypoint.sh`](./scripts/cloudrun-entrypoint.sh):

1. `gsutil rsync` from `gs://$GCS_BUCKET/openclaw-data/` into `/data/.openclaw` and `/data/workspace`.
2. Patches `openclaw.json` with two break-glass flags so token-only auth works in a headless environment:
   - `gateway.controlUi.dangerouslyDisableDeviceAuth: true` — the *only* flag that actually skips device pairing for **remote** operator connections (operator role only; node-role registrations still require a device identity). Required on Cloud Run because there's no local operator to approve a pairing request, and the load balancer means connections are never classified as "local".
   - `gateway.controlUi.allowInsecureAuth: true` — relaxes the secure-context check so the in-browser Control UI can connect without a `SubtleCrypto`-generated device key.
   It also merges any URLs in `OPENCLAW_CONTROL_UI_ALLOWED_ORIGINS` into `gateway.controlUi.allowedOrigins`, and writes `agents.defaults.model` from `OPENCLAW_AGENT_MODEL` if set.
3. Spawns a background loop that rsyncs back to GCS every `SYNC_INTERVAL` seconds (default `300`).
4. Resolves the `openclaw` CLI from the upstream image and runs `openclaw gateway --allow-unconfigured --bind $GATEWAY_BIND --port $PORT`.
5. On `SIGTERM` (Cloud Run shutdown): kills the sync loop, runs one last `rsync`, forwards the signal to the gateway.

## Quick deploy via `gcloud` (no Terraform)

This is the path used to bring up `openclaw-test-gateway` in `claw-for-all-app` (`us-central1`). Replace project + region with yours.

```bash
PROJECT_ID=claw-for-all-app
REGION=us-central1
REPO=docker                  # any existing Artifact Registry Docker repo
SERVICE=openclaw-test-gateway
IMAGE=$REGION-docker.pkg.dev/$PROJECT_ID/$REPO/openclaw

gcloud config set project "$PROJECT_ID"

# 1. One-time APIs (idempotent)
gcloud services enable \
  run.googleapis.com \
  cloudbuild.googleapis.com \
  artifactregistry.googleapis.com \
  secretmanager.googleapis.com \
  storage.googleapis.com

# 2. Create the gateway token (HTTP auth on the Control UI / WebSocket)
openssl rand -hex 32 \
  | gcloud secrets create openclaw-gateway-token \
      --replication-policy=automatic --data-file=-

# 2b. Provider auth — at least one is required for chat to work. Pick one or
#     more of: GEMINI_API_KEY (google), OPENAI_API_KEY, ANTHROPIC_API_KEY.
echo -n "AIza..." \
  | gcloud secrets create GEMINI_API_KEY \
      --replication-policy=automatic --data-file=-

# 3. Create a GCS bucket for persistent state
gcloud storage buckets create "gs://${PROJECT_ID}-openclaw-data" \
  --location="$REGION" --uniform-bucket-level-access

# 4. Build + push the image
#    Tracks ghcr.io/openclaw/openclaw:latest by default. To pin a version,
#    add: --substitutions=_OPENCLAW_VERSION=2026.4.27,...
gcloud builds submit \
  --config=cloudbuild.build.yaml \
  --substitutions=_REGION=$REGION,_REPOSITORY=$REPO,_IMAGE_NAME=openclaw

# 5. Deploy with the secret + GCS bucket wired in.
#    Two-pass: first deploy to learn the URL, then feed it back into the
#    OPENCLAW_CONTROL_UI_ALLOWED_ORIGINS env var (without it, the browser
#    Control UI gets `code=1008 reason=origin not allowed`).
gcloud run deploy "$SERVICE" \
  --image="$IMAGE:latest" \
  --region="$REGION" \
  --platform=managed \
  --port=8080 \
  --cpu=1 --memory=2Gi \
  --min-instances=1 --max-instances=1 \
  --timeout=3600 \
  --allow-unauthenticated \
  --set-env-vars="^@^GCS_BUCKET=${PROJECT_ID}-openclaw-data@^GATEWAY_BIND=lan@^SYNC_INTERVAL=300@^OPENCLAW_AGENT_MODEL=google/gemini-3-flash" \
  --set-secrets="OPENCLAW_GATEWAY_TOKEN=openclaw-gateway-token:latest,GEMINI_API_KEY=GEMINI_API_KEY:latest"

URL=$(gcloud run services describe "$SERVICE" --region="$REGION" --format='value(status.url)')
gcloud run services update "$SERVICE" --region="$REGION" \
  --update-env-vars="OPENCLAW_CONTROL_UI_ALLOWED_ORIGINS=${URL}"
```

> The `^@^` prefix tells `gcloud` to use `@` as the env-var separator instead of `,`. Required because comma-separated env vars (e.g. multiple URLs in `OPENCLAW_CONTROL_UI_ALLOWED_ORIGINS`) otherwise get parsed as separate env vars.

The Cloud Run runtime service account (default: `<PROJECT_NUMBER>-compute@developer.gserviceaccount.com`) needs `roles/storage.objectAdmin` on the bucket and `roles/secretmanager.secretAccessor` on each secret. Grant once:

```bash
PROJECT_NUMBER=$(gcloud projects describe "$PROJECT_ID" --format='value(projectNumber)')
RUNTIME_SA="${PROJECT_NUMBER}-compute@developer.gserviceaccount.com"

gcloud storage buckets add-iam-policy-binding "gs://${PROJECT_ID}-openclaw-data" \
  --member="serviceAccount:${RUNTIME_SA}" --role="roles/storage.objectAdmin"

for secret in openclaw-gateway-token GEMINI_API_KEY; do
  gcloud secrets add-iam-policy-binding "$secret" \
    --member="serviceAccount:${RUNTIME_SA}" --role="roles/secretmanager.secretAccessor"
done
```

## Open the gateway

```bash
URL=$(gcloud run services describe "$SERVICE" --region="$REGION" --format='value(status.url)')
TOKEN=$(gcloud secrets versions access latest --secret=openclaw-gateway-token)
echo "${URL}/?token=${TOKEN}"
```

Open the printed URL in a browser to reach the Control UI. Use the same `${URL}` and `${TOKEN}` for `openclaw devices pair-token` from any local CLI / mobile node.

## Day-2 operations

```bash
# Tail logs
gcloud run services logs read "$SERVICE" --region="$REGION" --limit=200

# Roll a new image (picks up the latest upstream openclaw release if you
# track :latest in cloudbuild.build.yaml)
gcloud builds submit --config=cloudbuild.build.yaml \
  --substitutions=_REGION=$REGION,_REPOSITORY=$REPO,_IMAGE_NAME=openclaw
gcloud run services update "$SERVICE" --region="$REGION" --image="$IMAGE:latest"

# Pin a specific upstream openclaw version on the next build
gcloud builds submit --config=cloudbuild.build.yaml \
  --substitutions=_REGION=$REGION,_REPOSITORY=$REPO,_IMAGE_NAME=openclaw,_OPENCLAW_VERSION=2026.4.27

# Force-revision rollout without rebuilding (re-reads secret latest version, etc.)
gcloud run services update "$SERVICE" --region="$REGION"

# Inspect synced state
gsutil ls -l "gs://${PROJECT_ID}-openclaw-data/openclaw-data/"
```

## Configuration knobs (env vars)

| Env var | Default | Purpose |
| --- | --- | --- |
| `PORT` | `8080` | Cloud Run-injected listen port. The gateway binds to this directly. |
| `GCS_BUCKET` | _unset_ | Bucket used by the entrypoint for restore + periodic sync. If unset, the service runs ephemerally. |
| `SYNC_INTERVAL` | `300` | Seconds between background `gsutil rsync` calls. |
| `RESTORE_WORKSPACE` | `true` | Set to `false` to skip restoring `/data/workspace` on cold start. |
| `GATEWAY_BIND` | `lan` | Passed through to `openclaw gateway --bind`. |
| `OPENCLAW_STATE_DIR` | `/data/.openclaw` | Persistent config dir. The CLI honors this directly (`src/utils.ts`). |
| `OPENCLAW_WORKSPACE_DIR` | `/data/workspace` | Workspace dir (synced to GCS, excluding `node_modules`, `*.lock`, `*.tmp`, `*.log`). |
| `OPENCLAW_GATEWAY_TOKEN` | _from secret_ | Bearer token for the Control UI / WebSocket. The token is the only thing standing between the open internet and your gateway because the entrypoint sets `controlUi.allowInsecureAuth: true` and `controlUi.dangerouslyDisableDeviceAuth: true`. Generate with `openssl rand -hex 32`; rotate if exposed. |
| `OPENCLAW_CONTROL_UI_ALLOWED_ORIGINS` | _unset_ | Comma-separated URLs merged into `gateway.controlUi.allowedOrigins`. Without it, the gateway only allows `http://localhost:8080` and the browser-served Control UI gets `code=1008 reason=origin not allowed` on the WebSocket upgrade. |
| `OPENCLAW_AGENT_MODEL` | _unset_ | Pin `agents.defaults.model` (e.g. `google/gemini-3-flash`, `anthropic/claude-sonnet-4.6`, `openai/gpt-5.5`). Without it, the gateway uses its built-in default (`openai/gpt-5.5`) which freezes chat unless `OPENAI_API_KEY` is also set. |
| `GEMINI_API_KEY` / `OPENAI_API_KEY` / `ANTHROPIC_API_KEY` | _from secret_ | Provider auth, picked up natively by OpenClaw. **At least one provider key must be wired in for chat to work** — the gateway boots fine without it, but messages will hang on the first agent call. |

## Notes / gotchas

- **Single instance, sticky state.** Cloud Run can in theory scale, but the GCS sync is last-writer-wins and the gateway holds local locks. Keep `min-instances=max-instances=1` (or use Cloud Run jobs / a different runtime if you need horizontal scale).
- **Cold starts.** First start with `min-instances=0` does a full GCS rsync; budget ~30–60 s on top of normal Cloud Run cold-start latency. Set `min-instances=1` for an always-on personal gateway.
- **No interactive pairing.** The entrypoint sets both `gateway.controlUi.allowInsecureAuth: true` and `gateway.controlUi.dangerouslyDisableDeviceAuth: true` so the token alone is sufficient (operator role only — node registrations still require device identity). `allowInsecureAuth` on its own is *not* enough on Cloud Run: it only loosens the secure-context check for connections the gateway considers local, and the load balancer means your browser never looks local. If you remove `dangerouslyDisableDeviceAuth`, the Control UI will fail with `device pairing required (requestId: …)` on every connect because no operator UI exists in the container to approve the request. Treat the gateway URL + token as full root access.
- **Memory.** Defaults to `NODE_OPTIONS=--max-old-space-size=1536` and the deploy uses `--memory=2Gi`. Bump both together if you load heavy skills.
- **Tracking upstream openclaw.** `Dockerfile.cloudrun` defaults `OPENCLAW_VERSION=latest`, so each Cloud Build pulls whatever upstream tagged most recently. To pin (recommended for prod), pass `_OPENCLAW_VERSION` in your Cloud Build substitutions and bump it in a PR after testing.
- **Production / IaC.** For repeatable environments use [`terraform/`](./terraform/) instead of the manual flow above.

## Cleanup

```bash
gcloud run services delete "$SERVICE" --region="$REGION" --quiet
gcloud secrets delete openclaw-gateway-token --quiet
gcloud secrets delete GEMINI_API_KEY --quiet
gcloud storage rm -r "gs://${PROJECT_ID}-openclaw-data"
```

## License

MIT — see [LICENSE](./LICENSE). Upstream OpenClaw is also MIT-licensed; the runtime image referenced here is built and published by [openclaw/openclaw](https://github.com/openclaw/openclaw).
