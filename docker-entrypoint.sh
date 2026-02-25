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

  # Inject model providers from environment variables
  # - ANTHROPIC_PROXY_BASE_URL → anthropic-proxy provider (Anthropic mirror/proxy)
  # - OPENAI_BASE_URL → openai provider (OpenAI or compatible API)
  if [ -n "$ANTHROPIC_PROXY_BASE_URL" ] || [ -n "$OPENAI_BASE_URL" ]; then
    node -e "
      const fs = require('fs');
      const cfg = JSON.parse(fs.readFileSync('$CONFIG_FILE', 'utf8'));
      cfg.models = cfg.models || {};
      cfg.models.providers = cfg.models.providers || {};

      if (process.env.ANTHROPIC_PROXY_BASE_URL) {
        cfg.models.providers['anthropic-proxy'] = {
          baseUrl: process.env.ANTHROPIC_PROXY_BASE_URL,
          api: 'anthropic-messages',
          apiKey: '\${ANTHROPIC_API_KEY}',
          models: [
            {
              id: 'claude-opus-4-6',
              name: 'Claude Opus 4.6',
              reasoning: true,
              input: ['text', 'image'],
              cost: { input: 15, output: 75, cacheRead: 1.5, cacheWrite: 18.75 },
              contextWindow: 200000,
              maxTokens: 16000,
            },
            {
              id: 'claude-sonnet-4-20250514',
              name: 'Claude Sonnet 4',
              reasoning: true,
              input: ['text', 'image'],
              cost: { input: 3, output: 15, cacheRead: 0.3, cacheWrite: 3.75 },
              contextWindow: 200000,
              maxTokens: 16000,
            },
          ],
        };
      }

      if (process.env.OPENAI_BASE_URL) {
        cfg.models.providers['openai'] = {
          baseUrl: process.env.OPENAI_BASE_URL,
          api: 'openai-chat',
          apiKey: '\${OPENAI_API_KEY}',
          models: [
            {
              id: 'gpt-4o',
              name: 'GPT-4o',
              reasoning: false,
              input: ['text', 'image'],
              cost: { input: 2.5, output: 10, cacheRead: 1.25, cacheWrite: 2.5 },
              contextWindow: 128000,
              maxTokens: 16384,
            },
            {
              id: 'o3',
              name: 'o3',
              reasoning: true,
              input: ['text', 'image'],
              cost: { input: 10, output: 40, cacheRead: 2.5, cacheWrite: 10 },
              contextWindow: 200000,
              maxTokens: 100000,
            },
          ],
        };
      }

      // Clean up legacy 'agent' key (renamed to 'agents.defaults' in newer versions)
      if (cfg.agent) {
        cfg.agents = cfg.agents || {};
        cfg.agents.defaults = cfg.agents.defaults || { ...cfg.agent };
        delete cfg.agent;
      }

      cfg.agents = cfg.agents || {};
      cfg.agents.defaults = cfg.agents.defaults || {};
      cfg.agents.defaults.model = cfg.agents.defaults.model || {};
      if (!cfg.agents.defaults.model.primary) {
        if (process.env.ANTHROPIC_PROXY_BASE_URL) {
          cfg.agents.defaults.model.primary = 'anthropic-proxy/claude-opus-4-6';
        } else if (process.env.OPENAI_BASE_URL) {
          cfg.agents.defaults.model.primary = 'openai/gpt-4o';
        }
      }
      fs.writeFileSync('$CONFIG_FILE', JSON.stringify(cfg, null, 2) + '\n');
    "
  fi
  chown -R node:node "$CONFIG_DIR"

  # Remove duplicate feishu plugin from volume (built-in at /app/extensions/feishu)
  rm -rf "$CONFIG_DIR/extensions/feishu"

  # Enable feishu plugin and configure channel in config
  node -e "
    const fs = require('fs');
    const cfg = JSON.parse(fs.readFileSync('$CONFIG_FILE', 'utf8'));
    cfg.plugins = cfg.plugins || {};
    cfg.plugins.entries = cfg.plugins.entries || {};
    if (!cfg.plugins.entries.feishu) {
      cfg.plugins.entries.feishu = { enabled: true };
    }
    // Configure feishu channel from env vars
    if (process.env.FEISHU_APP_ID && process.env.FEISHU_APP_SECRET) {
      cfg.channels = cfg.channels || {};
      cfg.channels.feishu = cfg.channels.feishu || {};
      cfg.channels.feishu.enabled = true;
      cfg.channels.feishu.appId = process.env.FEISHU_APP_ID;
      cfg.channels.feishu.appSecret = process.env.FEISHU_APP_SECRET;
      cfg.channels.feishu.connectionMode = 'websocket';
      cfg.channels.feishu.domain = 'feishu';
      cfg.channels.feishu.dmPolicy = cfg.channels.feishu.dmPolicy || 'open';
      cfg.channels.feishu.allowFrom = cfg.channels.feishu.allowFrom || ['*'];
      cfg.channels.feishu.requireMention = cfg.channels.feishu.requireMention !== undefined ? cfg.channels.feishu.requireMention : true;
    }
    fs.writeFileSync('$CONFIG_FILE', JSON.stringify(cfg, null, 2) + '\n');
  "

  # Enable headless + no-sandbox browser for Docker containers
  node -e "
    const fs = require('fs');
    const cfg = JSON.parse(fs.readFileSync('$CONFIG_FILE', 'utf8'));
    cfg.browser = cfg.browser || {};
    cfg.browser.enabled = true;
    cfg.browser.headless = true;
    cfg.browser.noSandbox = true;
    fs.writeFileSync('$CONFIG_FILE', JSON.stringify(cfg, null, 2) + '\n');
  "

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
