#!/bin/sh
# Ensure node user owns the persistent .local volume
chown -R node:node /home/node/.local

# Symlink user-installed skill binaries into PATH so the gateway can find them
if [ -d /home/node/.local/bin ]; then
  for bin in /home/node/.local/bin/*; do
    [ -f "$bin" ] && ln -sf "$bin" /usr/local/bin/"$(basename "$bin")" 2>/dev/null
  done
fi

# Exec as node user with npm prefix configured
exec su -s /bin/sh node -c 'export NPM_CONFIG_PREFIX=/home/node/.local && exec node dist/index.js '"$*"''
