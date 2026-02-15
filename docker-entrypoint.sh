#!/bin/sh
set -e

# Fix volume mount permissions (Railway, Render, etc. mount as root)
if [ -d /data ] && [ "$(id -u)" = "0" ]; then
  chown -R node:node /data

  # Ensure gateway config for cloud platforms
  CONFIG_DIR="/data/.openclaw"
  CONFIG_FILE="$CONFIG_DIR/openclaw.json"
  mkdir -p "$CONFIG_DIR"
  if [ ! -f "$CONFIG_FILE" ]; then
    cat > "$CONFIG_FILE" <<'CONF'
{
  "gateway": {
    "controlUi": {
      "allowInsecureAuth": true,
      "dangerouslyDisableDeviceAuth": true
    }
  }
}
CONF
  fi
  chown -R node:node "$CONFIG_DIR"

  # trustedProxies is handled via OPENCLAW_TRUSTED_PROXIES env var
  # (see applyTrustedProxiesEnv in src/config/io.ts)
  export OPENCLAW_TRUSTED_PROXIES="${OPENCLAW_TRUSTED_PROXIES:-100.64.0.0/10}"
  export OPENCLAW_STATE_DIR="$CONFIG_DIR"
  export OPENCLAW_CONFIG_PATH="$CONFIG_FILE"
  export HOME="/data"

  exec gosu node "$@"
else
  exec "$@"
fi
