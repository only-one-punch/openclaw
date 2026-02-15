#!/bin/sh
set -e

# Fix volume mount permissions (Railway, Render, etc. mount as root)
if [ -d /data ] && [ "$(id -u)" = "0" ]; then
  chown -R node:node /data

  # Ensure gateway config for cloud platforms
  CONFIG_DIR="/data/.openclaw"
  CONFIG_FILE="$CONFIG_DIR/openclaw.json"
  mkdir -p "$CONFIG_DIR"
  if [ -f "$CONFIG_FILE" ]; then
    # Merge required cloud settings into existing config
    node -e "
      const fs = require('fs');
      const cfg = JSON.parse(fs.readFileSync('$CONFIG_FILE', 'utf8'));
      cfg.gateway = cfg.gateway || {};
      if (!cfg.gateway.trustedProxies || !cfg.gateway.trustedProxies.includes('100.64.0.0/10')) {
        cfg.gateway.trustedProxies = ['100.64.0.0/10'];
      }
      cfg.gateway.controlUi = cfg.gateway.controlUi || {};
      cfg.gateway.controlUi.allowInsecureAuth = true;
      cfg.gateway.controlUi.dangerouslyDisableDeviceAuth = true;
      fs.writeFileSync('$CONFIG_FILE', JSON.stringify(cfg, null, 2) + '\n');
    "
  else
    cat > "$CONFIG_FILE" <<'CONF'
{
  "gateway": {
    "trustedProxies": ["100.64.0.0/10"],
    "controlUi": {
      "allowInsecureAuth": true,
      "dangerouslyDisableDeviceAuth": true
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
