#!/bin/sh
set -e

# Fix volume mount permissions (Railway, Render, etc. mount as root)
if [ -d /data ] && [ "$(id -u)" = "0" ]; then
  chown -R node:node /data
  exec gosu node "$@"
else
  exec "$@"
fi
