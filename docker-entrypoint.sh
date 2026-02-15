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
    cat > "$CONFIG_FILE" <<CONF
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

  # If ANTHROPIC_PROXY_BASE_URL is set, inject a custom provider into config
  if [ -n "$ANTHROPIC_PROXY_BASE_URL" ]; then
    node -e "
      const fs = require('fs');
      const cfg = JSON.parse(fs.readFileSync('$CONFIG_FILE', 'utf8'));
      cfg.models = cfg.models || {};
      cfg.models.providers = cfg.models.providers || {};
      cfg.models.providers['anthropic-proxy'] = {
        baseUrl: process.env.ANTHROPIC_PROXY_BASE_URL,
        api: 'anthropic-messages',
        apiKey: '\${ANTHROPIC_API_KEY}',
      };
      cfg.agent = cfg.agent || {};
      cfg.agent.model = cfg.agent.model || {};
      if (!cfg.agent.model.primary) {
        cfg.agent.model.primary = 'anthropic-proxy/claude-opus-4-6';
      }
      fs.writeFileSync('$CONFIG_FILE', JSON.stringify(cfg, null, 2) + '\n');
    "
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
