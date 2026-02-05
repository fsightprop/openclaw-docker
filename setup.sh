#!/usr/bin/env bash
set -euo pipefail

PROJECT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_DIR="$PROJECT_DIR/openclaw"
ENV_FILE="$PROJECT_DIR/.env"
IMAGE_NAME="openclaw:local"

OPENCLAW_CONFIG_DIR="${HOME}/.openclaw"
OPENCLAW_WORKSPACE_DIR="${HOME}/.openclaw/workspace"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

info()  { echo -e "${GREEN}==>${NC} $*"; }
warn()  { echo -e "${YELLOW}==> WARNING:${NC} $*"; }
error() { echo -e "${RED}==> ERROR:${NC} $*" >&2; }
header() { echo -e "\n${BOLD}${CYAN}$*${NC}\n"; }

# ============================================================
# Step 1: Validate prerequisites
# ============================================================
header "Step 1/9: Checking prerequisites"

if ! command -v docker &>/dev/null; then
  error "Docker is not installed. Install it from https://docs.docker.com/get-docker/"
  exit 1
fi
info "Docker found: $(docker --version)"

if ! docker compose version &>/dev/null; then
  error "Docker Compose v2 not found. Update Docker or install the compose plugin."
  exit 1
fi
info "Docker Compose found: $(docker compose version --short)"

if ! command -v git &>/dev/null; then
  error "Git is not installed."
  exit 1
fi
info "Git found: $(git --version)"

if ! docker info &>/dev/null 2>&1; then
  error "Docker daemon is not running. Start Docker first."
  exit 1
fi
info "Docker daemon is running"

# ============================================================
# Step 2: Stop existing cloudflared system service
# ============================================================
header "Step 2/9: Checking for existing cloudflared service"

if systemctl is-active --quiet cloudflared 2>/dev/null; then
  warn "cloudflared is running as a system service."
  warn "This will conflict with the Docker sidecar. Stopping and uninstalling..."
  sudo systemctl stop cloudflared
  sudo cloudflared service uninstall 2>/dev/null || true
  info "Existing cloudflared service removed"
elif systemctl is-enabled --quiet cloudflared 2>/dev/null; then
  warn "cloudflared system service found (not running). Uninstalling..."
  sudo cloudflared service uninstall 2>/dev/null || true
  info "Existing cloudflared service removed"
else
  info "No existing cloudflared system service found"
fi

# ============================================================
# Step 3: Cloudflare tunnel token
# ============================================================
header "Step 3/9: Cloudflare Tunnel Configuration"

if [[ -z "${CLOUDFLARE_TUNNEL_TOKEN:-}" ]]; then
  echo "You need a Cloudflare Tunnel token before continuing."
  echo ""
  echo "  1. Go to https://one.dash.cloudflare.com/"
  echo "     -> Networks -> Connectors"
  echo "  2. Create a new connector (or select an existing one)"
  echo "  3. Add a public hostname with these settings:"
  echo "       Service type: HTTP"
  echo "       URL:          openclaw-gateway:18789"
  echo "  4. Copy the tunnel token from the install command"
  echo ""
  read -rsp "Paste your Cloudflare Tunnel Token (input hidden): " CLOUDFLARE_TUNNEL_TOKEN
  echo ""
fi

if [[ -z "$CLOUDFLARE_TUNNEL_TOKEN" ]]; then
  error "Cloudflare tunnel token cannot be empty."
  exit 1
fi
info "Cloudflare tunnel token received"

# ============================================================
# Step 4: Generate gateway token
# ============================================================
header "Step 4/9: Generating OpenClaw Gateway Token"

OPENCLAW_GATEWAY_TOKEN="$(openssl rand -hex 32)"
info "Gateway token generated"

# ============================================================
# Step 5: Create config directories
# ============================================================
header "Step 5/9: Creating Config Directories"

mkdir -p "$OPENCLAW_CONFIG_DIR"
mkdir -p "$OPENCLAW_WORKSPACE_DIR"
info "Config directory: $OPENCLAW_CONFIG_DIR"
info "Workspace directory: $OPENCLAW_WORKSPACE_DIR"

# ============================================================
# Step 6: Clone or update OpenClaw repo
# ============================================================
header "Step 6/9: Cloning OpenClaw Repository"

if [[ -d "$REPO_DIR/.git" ]]; then
  info "Existing repo found, pulling latest changes..."
  git -C "$REPO_DIR" pull --ff-only || {
    warn "Fast-forward pull failed. You may need to resolve conflicts manually in $REPO_DIR"
    warn "Continuing with existing version..."
  }
else
  info "Cloning https://github.com/openclaw/openclaw.git ..."
  git clone --depth 1 https://github.com/openclaw/openclaw.git "$REPO_DIR"
fi
info "OpenClaw source ready at $REPO_DIR"

# ============================================================
# Step 7: Build Docker image
# ============================================================
header "Step 7/9: Building Docker Image"

info "Building image '$IMAGE_NAME' from upstream Dockerfile..."
info "This may take several minutes on first run."
echo ""
docker build \
  -t "$IMAGE_NAME" \
  -f "$REPO_DIR/Dockerfile" \
  "$REPO_DIR"

info "Docker image built successfully"

# ============================================================
# Step 8: Write .env file
# ============================================================
header "Step 8/9: Writing Configuration"

cat > "$ENV_FILE" <<EOF
# OpenClaw Docker Configuration
# Generated by setup.sh on $(date -Iseconds)

# Image
OPENCLAW_IMAGE=${IMAGE_NAME}

# Paths (bind-mounted into container)
OPENCLAW_CONFIG_DIR=${OPENCLAW_CONFIG_DIR}
OPENCLAW_WORKSPACE_DIR=${OPENCLAW_WORKSPACE_DIR}

# Gateway
OPENCLAW_GATEWAY_TOKEN=${OPENCLAW_GATEWAY_TOKEN}
OPENCLAW_GATEWAY_PORT=18789

# Cloudflare Tunnel
CLOUDFLARE_TUNNEL_TOKEN=${CLOUDFLARE_TUNNEL_TOKEN}
EOF

chmod 600 "$ENV_FILE"
info ".env written (permissions: 600)"

# ============================================================
# Step 9: Onboarding + Launch
# ============================================================
header "Step 9/9: Onboarding & Launch"

echo "The OpenClaw onboarding wizard will now run interactively."
echo "You will be asked to configure your AI model provider (API keys, etc.)."
echo ""
echo "  Recommended settings when prompted:"
echo "    Gateway bind:    lan"
echo "    Gateway auth:    token"
echo "    Install daemon:  No (Docker handles this)"
echo ""
echo "Your gateway token (copy if needed):"
echo "  $OPENCLAW_GATEWAY_TOKEN"
echo ""
read -rp "Press Enter to start onboarding..."

docker compose -f "$PROJECT_DIR/docker-compose.yml" \
  --env-file "$ENV_FILE" \
  run --rm openclaw-cli onboard --no-install-daemon

info "Onboarding complete. Starting services..."
echo ""

docker compose -f "$PROJECT_DIR/docker-compose.yml" \
  --env-file "$ENV_FILE" \
  up -d openclaw-gateway cloudflared

# Wait briefly for healthcheck
info "Waiting for gateway to become healthy..."
sleep 5

# ============================================================
# Done
# ============================================================
header "Setup Complete"

echo "  Gateway Token:    $OPENCLAW_GATEWAY_TOKEN"
echo "  Local Access:     http://127.0.0.1:18789/"
echo "  Config Dir:       $OPENCLAW_CONFIG_DIR"
echo "  Workspace Dir:    $OPENCLAW_WORKSPACE_DIR"
echo "  Compose File:     $PROJECT_DIR/docker-compose.yml"
echo ""
echo "  The Cloudflare tunnel is running."
echo "  Access OpenClaw via your configured Cloudflare hostname."
echo ""
echo "Useful commands:"
echo "  # View logs"
echo "  docker compose -f $PROJECT_DIR/docker-compose.yml --env-file $ENV_FILE logs -f"
echo ""
echo "  # Stop everything"
echo "  docker compose -f $PROJECT_DIR/docker-compose.yml --env-file $ENV_FILE down"
echo ""
echo "  # Restart"
echo "  docker compose -f $PROJECT_DIR/docker-compose.yml --env-file $ENV_FILE restart"
echo ""
echo "  # Add a messaging channel (e.g. Telegram)"
echo "  docker compose -f $PROJECT_DIR/docker-compose.yml --env-file $ENV_FILE run --rm openclaw-cli channels add --channel telegram"
echo ""
echo "  # Run any OpenClaw CLI command"
echo "  docker compose -f $PROJECT_DIR/docker-compose.yml --env-file $ENV_FILE run --rm openclaw-cli <command>"
echo ""
