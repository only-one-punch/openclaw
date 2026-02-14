#!/bin/sh
set -e

# Fix volume mount permissions (Railway, Render, etc. mount as root)
if [ -d /data ] && [ "$(id -u)" = "0" ]; then
  chown -R node:node /data

  # Ensure gateway config has allowInsecureAuth for cloud platforms
  CONFIG_DIR="/data/.openclaw"
  CONFIG_FILE="$CONFIG_DIR/openclaw.json"
  mkdir -p "$CONFIG_DIR"
  if [ -f "$CONFIG_FILE" ]; then
    # Inject allowInsecureAuth if not already present
    if ! grep -q '"allowInsecureAuth"' "$CONFIG_FILE" 2>/dev/null; then
      # Use node to merge config safely
      node -e "
        const fs = require('fs');
        const cfg = JSON.parse(fs.readFileSync('$CONFIG_FILE', 'utf8'));
        cfg.gateway = cfg.gateway || {};
        cfg.gateway.controlUi = cfg.gateway.controlUi || {};
        cfg.gateway.controlUi.allowInsecureAuth = true;
        fs.writeFileSync('$CONFIG_FILE', JSON.stringify(cfg, null, 2) + '\n');
      "
    fi
  else
    cat > "$CONFIG_FILE" <<'CONF'
{
  "gateway": {
    "controlUi": {
      "allowInsecureAuth": true
    }
  }
}
CONF
  fi
  chown -R node:node "$CONFIG_DIR"
  export OPENCLAW_STATE_DIR="$CONFIG_DIR"
  export OPENCLAW_CONFIG_PATH="$CONFIG_FILE"
  export HOME="/data"

  exec gosu node "$@"
else
  exec "$@"
fi
