#!/bin/bash
# Cloud Run Entrypoint for OpenClaw
# 
# This script:
# 1. Restores state from GCS on startup
# 2. Starts a background sync process
# 3. Starts the OpenClaw gateway
# 4. Handles graceful shutdown with final sync

set -e

# Configuration from environment variables
GCS_BUCKET="${GCS_BUCKET:-}"
OPENCLAW_STATE_DIR="${OPENCLAW_STATE_DIR:-/data/.openclaw}"
OPENCLAW_WORKSPACE_DIR="${OPENCLAW_WORKSPACE_DIR:-/data/workspace}"
SYNC_INTERVAL="${SYNC_INTERVAL:-300}"  # Default: 5 minutes
PORT="${PORT:-8080}"
GATEWAY_PORT="${GATEWAY_PORT:-18789}"
GATEWAY_BIND="${GATEWAY_BIND:-lan}"

# Logging helper
log() {
    echo "[$(date -Iseconds)] [entrypoint] $*"
}

# Restore state from GCS
restore_from_gcs() {
    if [ -z "$GCS_BUCKET" ]; then
        log "GCS_BUCKET not set, skipping restore"
        return 0
    fi

    log "Checking for existing state in gs://$GCS_BUCKET/openclaw-data/..."
    
    # Check if backup exists
    if gsutil -q stat "gs://$GCS_BUCKET/openclaw-data/.last-sync" 2>/dev/null; then
        log "Found existing backup, restoring..."
        
        # Restore config directory
        gsutil -m rsync -r "gs://$GCS_BUCKET/openclaw-data/config/" "$OPENCLAW_STATE_DIR/" 2>/dev/null || true
        
        # Restore workspace (optional, may be large)
        if [ "${RESTORE_WORKSPACE:-true}" = "true" ]; then
            gsutil -m rsync -r "gs://$GCS_BUCKET/openclaw-data/workspace/" "$OPENCLAW_WORKSPACE_DIR/" 2>/dev/null || true
        fi
        
        log "Restore completed"
    else
        log "No existing backup found, starting fresh"
    fi
}

# Sync state to GCS
sync_to_gcs() {
    if [ -z "$GCS_BUCKET" ]; then
        return 0
    fi

    log "Syncing state to GCS..."
    
    # Sync config directory (excludes locks and temp files)
    gsutil -m rsync -r -x '.*\.lock$|.*\.log$|.*\.tmp$' \
        "$OPENCLAW_STATE_DIR/" "gs://$GCS_BUCKET/openclaw-data/config/" 2>/dev/null || true
    
    # Sync workspace
    gsutil -m rsync -r -x '.*\.lock$|.*\.log$|.*\.tmp$|node_modules/.*' \
        "$OPENCLAW_WORKSPACE_DIR/" "gs://$GCS_BUCKET/openclaw-data/workspace/" 2>/dev/null || true
    
    # Write sync timestamp
    echo "$(date -Iseconds)" | gsutil cp - "gs://$GCS_BUCKET/openclaw-data/.last-sync" 2>/dev/null || true
    
    log "Sync completed"
}

# Background sync loop
background_sync() {
    if [ -z "$GCS_BUCKET" ]; then
        return 0
    fi

    log "Starting background sync (interval: ${SYNC_INTERVAL}s)"
    
    while true; do
        sleep "$SYNC_INTERVAL"
        sync_to_gcs
    done
}

# Graceful shutdown handler
shutdown_handler() {
    log "Received shutdown signal, performing final sync..."
    
    # Kill the background sync process first
    if [ -n "$SYNC_PID" ]; then
        kill "$SYNC_PID" 2>/dev/null || true
    fi
    
    sync_to_gcs
    log "Final sync completed"
    
    # Kill the gateway process
    if [ -n "$GATEWAY_PID" ]; then
        kill -TERM "$GATEWAY_PID" 2>/dev/null || true
        wait "$GATEWAY_PID" 2>/dev/null || true
    fi
    
    log "Shutdown complete, exiting"
    exit 0
}

# Set up signal handlers
trap shutdown_handler SIGTERM SIGINT

# Create directories
mkdir -p "$OPENCLAW_STATE_DIR" "$OPENCLAW_WORKSPACE_DIR"

# Ensure gateway config exists with headless-friendly defaults.
#
# Cloud Run is headless: there is no operator UI to approve pairing requests, and
# the gateway sits behind a load balancer so connections are never treated as
# local. We therefore have to opt out of device pairing entirely for the
# Control UI -- token auth is still enforced.
#
# - controlUi.dangerouslyDisableDeviceAuth: true is the only flag that actually
#   skips device pairing for *remote* operator connections (operator role only;
#   node-role registrations still require a device identity). `allowInsecureAuth`
#   alone does NOT do this -- it only loosens the secure-context check for
#   connections the gateway considers local, which Cloud Run is not.
# - controlUi.allowedOrigins must include the public Cloud Run URL or any
#   browser-served origin (the gateway otherwise rejects WS upgrades with
#   `origin not allowed`). Sourced from OPENCLAW_CONTROL_UI_ALLOWED_ORIGINS
#   (comma-separated list) so the same image works behind any URL.
# - agent.model can be pinned via OPENCLAW_AGENT_MODEL (e.g.
#   "google/gemini-3-flash"). Without it the gateway falls back to its built-in
#   default ("openai/gpt-5.5"), which only works if OPENAI_API_KEY is set.
ensure_gateway_config() {
    local config_file="$OPENCLAW_STATE_DIR/openclaw.json"

    if [ ! -f "$config_file" ]; then
        log "Creating default gateway config at $config_file"
        cat > "$config_file" <<'CFGEOF'
{
  "gateway": {
    "mode": "local",
    "controlUi": {
      "allowInsecureAuth": true,
      "dangerouslyDisableDeviceAuth": true
    }
  }
}
CFGEOF
    fi

    if ! command -v node >/dev/null 2>&1; then
        log "WARN: node not found, cannot patch gateway config"
        return 0
    fi

    OPENCLAW_CONTROL_UI_ALLOWED_ORIGINS="${OPENCLAW_CONTROL_UI_ALLOWED_ORIGINS:-}" \
    OPENCLAW_AGENT_MODEL="${OPENCLAW_AGENT_MODEL:-}" \
        node -e "
const fs = require('fs');
const f = '$config_file';
const c = JSON.parse(fs.readFileSync(f, 'utf8'));
if (!c.gateway) c.gateway = {};
if (!c.gateway.controlUi) c.gateway.controlUi = {};

let dirty = false;

if (c.gateway.controlUi.allowInsecureAuth !== true) {
  c.gateway.controlUi.allowInsecureAuth = true;
  dirty = true;
  console.log('[entrypoint] Patched allowInsecureAuth=true');
}

if (c.gateway.controlUi.dangerouslyDisableDeviceAuth !== true) {
  c.gateway.controlUi.dangerouslyDisableDeviceAuth = true;
  dirty = true;
  console.log('[entrypoint] Patched dangerouslyDisableDeviceAuth=true (headless break-glass)');
}

const rawOrigins = process.env.OPENCLAW_CONTROL_UI_ALLOWED_ORIGINS || '';
const requestedOrigins = rawOrigins.split(',').map((s) => s.trim()).filter(Boolean);
if (requestedOrigins.length > 0) {
  const existing = Array.isArray(c.gateway.controlUi.allowedOrigins)
    ? c.gateway.controlUi.allowedOrigins.filter((o) => typeof o === 'string')
    : [];
  const merged = Array.from(new Set([...existing, ...requestedOrigins]));
  if (merged.length !== existing.length || merged.some((o, i) => o !== existing[i])) {
    c.gateway.controlUi.allowedOrigins = merged;
    dirty = true;
    console.log('[entrypoint] Set controlUi.allowedOrigins=' + JSON.stringify(merged));
  }
}

// agents.defaults.model is the correct path; old configs used 'agent.model'
// which the current schema rejects with 'Unrecognized key: agent'.
const requestedModel = (process.env.OPENCLAW_AGENT_MODEL || '').trim();
if (requestedModel) {
  if (!c.agents) c.agents = {};
  if (!c.agents.defaults) c.agents.defaults = {};
  if (c.agents.defaults.model !== requestedModel) {
    c.agents.defaults.model = requestedModel;
    dirty = true;
    console.log('[entrypoint] Set agents.defaults.model=' + JSON.stringify(requestedModel));
  }
}

// Strip any legacy top-level 'agent' key written by older entrypoint versions.
if (Object.prototype.hasOwnProperty.call(c, 'agent')) {
  delete c.agent;
  dirty = true;
  console.log('[entrypoint] Removed legacy top-level \"agent\" key');
}

if (dirty) {
  fs.writeFileSync(f, JSON.stringify(c, null, 2) + '\n');
}
"
}

# Restore from GCS on startup
restore_from_gcs

# Ensure gateway config has headless auth settings (after restore, so we
# can patch a restored config if needed)
ensure_gateway_config

# Start background sync
background_sync &
SYNC_PID=$!

# Determine the command to run
case "${1:-gateway}" in
    gateway)
        log "Starting OpenClaw gateway on port $GATEWAY_PORT (Cloud Run port: $PORT)"
        
        # Start the gateway
        # Note: Cloud Run requires the service to listen on $PORT
        # We'll run the gateway on its default port and use socat to proxy if needed
        
        if [ "$PORT" != "$GATEWAY_PORT" ]; then
            log "Port mapping: $PORT -> $GATEWAY_PORT (using gateway's native port binding)"
        fi
        
        # Export environment variables for the gateway
        export HOME="${HOME:-/home/node}"
        export OPENCLAW_GATEWAY_BIND="$GATEWAY_BIND"

        # Resolve the openclaw CLI. Upstream image symlinks /usr/local/bin/openclaw
        # to the bundled openclaw.mjs; fall back to absolute paths if the layout
        # changes upstream.
        if command -v openclaw >/dev/null 2>&1; then
            OPENCLAW_BIN="openclaw"
        elif [ -x /app/openclaw.mjs ]; then
            OPENCLAW_BIN="/app/openclaw.mjs"
        elif [ -x /app/dist/index.js ]; then
            OPENCLAW_BIN="node /app/dist/index.js"
        else
            log "ERROR: cannot find openclaw CLI (checked PATH, /app/openclaw.mjs, /app/dist/index.js)"
            exit 1
        fi
        log "Using openclaw bin: $OPENCLAW_BIN"

        # Run the gateway in background (not exec) so trap handlers remain active.
        # Using exec would replace the shell, discarding trap handlers and preventing
        # graceful shutdown with final GCS sync.
        # Note: We use ${@:2} to skip the first argument ("gateway") which was already matched
        # shellcheck disable=SC2086
        $OPENCLAW_BIN gateway \
            --allow-unconfigured \
            --bind "$GATEWAY_BIND" \
            --port "$PORT" \
            "${@:2}" &
        GATEWAY_PID=$!
        
        log "Gateway started with PID $GATEWAY_PID"
        
        # Wait for the gateway process. This keeps the shell alive so trap handlers
        # can intercept SIGTERM/SIGINT and run shutdown_handler for final sync.
        # If gateway exits on its own, we propagate its exit code.
        wait "$GATEWAY_PID"
        GATEWAY_EXIT_CODE=$?
        
        # Gateway exited without signal (natural exit or crash)
        log "Gateway exited with code $GATEWAY_EXIT_CODE"
        
        # Perform final sync and cleanup
        kill "$SYNC_PID" 2>/dev/null || true
        sync_to_gcs
        
        exit "$GATEWAY_EXIT_CODE"
        ;;
    
    shell)
        log "Starting shell"
        exec /bin/bash
        ;;
    
    sync)
        log "Running manual sync"
        sync_to_gcs
        ;;
    
    *)
        log "Running custom command: $*"
        exec "$@"
        ;;
esac
