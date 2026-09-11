#!/bin/sh
# Ensure node user owns the persistent .local volume
chown -R node:node /home/node/.local

# Fix permissions on agent config files (CLI runs as root, gateway as node)
chmod -R go+r /home/node/.openclaw/agents/*/agent/ 2>/dev/null || true
chmod -R go+r /home/node/.openclaw/devices/ 2>/dev/null || true

# v2026.4.22+ plugin runtime deps mirror — gateway refreshes files here on boot,
# needs node:node ownership end-to-end. Stray root-owned subdirs cause EACCES
# unlink during plugin init (telegram/etc), which fails channel boot silently.
chown -R node:node /home/node/.openclaw/plugin-runtime-deps/ 2>/dev/null || true

# Symlink user-installed skill binaries into PATH so the gateway can find them
if [ -d /home/node/.local/bin ]; then
  for bin in /home/node/.local/bin/*; do
    [ -f "$bin" ] && ln -sf "$bin" /usr/local/bin/"$(basename "$bin")" 2>/dev/null
  done
fi

# Ensure trusted temp dir exists for v2026.3.1+
mkdir -p /tmp/openclaw-1000
chown node:node /tmp/openclaw-1000

# v2026.4.5 strips XDG_CONFIG_HOME from exec tool env (config-path sanitization).
# Symlink default ~/.config/gogcli -> /home/node/.openclaw/gogcli so gog finds
# credentials when agents invoke it via exec.
mkdir -p /home/node/.config
rm -f /home/node/.config/gogcli
ln -s /home/node/.openclaw/gogcli /home/node/.config/gogcli
chown -h node:node /home/node/.config/gogcli /home/node/.config 2>/dev/null || true

# --- Mission Control startup ---
# Copy app source from persistent volume (not symlink — Turbopack rejects symlinks)
if [ -d "/home/node/.local/mission-control/src" ]; then
    rm -rf /home/node/mission-control/src
    cp -r /home/node/.local/mission-control/src /home/node/mission-control/src
    chown -R node:node /home/node/mission-control/src
fi
# Data dir symlink is fine — Turbopack doesn't scan it
mkdir -p /home/node/.local/mission-control/data
ln -sf /home/node/.local/mission-control/data /home/node/mission-control/data
# Copy custom config files from persistent volume
for f in next.config.ts tailwind.config.ts tsconfig.json postcss.config.mjs; do
    if [ -f "/home/node/.local/mission-control/$f" ]; then
        cp "/home/node/.local/mission-control/$f" "/home/node/mission-control/$f"
        chown node:node "/home/node/mission-control/$f"
    fi
done
# Copy .env.local from persistent volume
if [ -f "/home/node/.local/mission-control/.env.local" ]; then
    cp "/home/node/.local/mission-control/.env.local" "/home/node/mission-control/.env.local"
    chown node:node "/home/node/mission-control/.env.local"
fi
# Start persistent production HTTPS supervisor, independent of tool-session timeouts.
su -s /bin/sh node -c '/home/node/.local/mission-control/ops/supervise.sh > /tmp/mission-control.log 2>&1 &'

# Exec as node user with npm prefix configured.
# setpriv (not su) so node becomes PID 1 and receives SIGTERM directly. su does not
# forward signals, so `docker compose stop` used to SIGKILL node after the grace
# period — an unclean kill mid-write, which v2026.8.1 fences as an unbootable
# database rather than recovering. Also stops su orphaning zombie children.
export NPM_CONFIG_PREFIX=/home/node/.local
exec setpriv --reuid=node --regid=node --init-groups node dist/index.js "$@"
