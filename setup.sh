#!/usr/bin/env bash
# ==============================================================
# OpenClaw + Ollama — Linux / macOS Automated Setup Script
# ==============================================================
# Usage:
#   chmod +x setup.sh
#   ./setup.sh
#
# Optional flags:
#   --primary-model   <model>   Primary Ollama model (default: llama3.2:latest)
#   --subagent-model  <model>   Subagent Ollama model (default: qwen2.5-coder:7b)
#   --install-dir     <path>    Where to clone OpenClaw (default: ~/openclaw)
#   --token           <string>  Gateway token (auto-generated if not set)
#
# Examples:
#   ./setup.sh
#   ./setup.sh --primary-model mistral:latest --subagent-model mistral:latest
#   ./setup.sh --install-dir /opt/openclaw --token mysecrettoken123
# ==============================================================

set -euo pipefail

# ── Defaults ──────────────────────────────────────────────────
PRIMARY_MODEL="gpt-oss:20b"
SUBAGENT_MODEL="gemma3:12b"
INSTALL_DIR="$HOME/openclaw"
GATEWAY_TOKEN=""

# ── Colours ───────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
WHITE='\033[1;37m'
NC='\033[0m' # No Colour

info()  { echo -e "${CYAN}[INFO]  $*${NC}"; }
ok()    { echo -e "${GREEN}[ OK ]  $*${NC}"; }
warn()  { echo -e "${YELLOW}[WARN]  $*${NC}"; }
err()   { echo -e "${RED}[ERR ]  $*${NC}"; }
title() {
    echo ""
    echo -e "${MAGENTA}=====================================================${NC}"
    echo -e "${MAGENTA}  $*${NC}"
    echo -e "${MAGENTA}=====================================================${NC}"
}

# ── Argument parsing ──────────────────────────────────────────
while [[ $# -gt 0 ]]; do
    case "$1" in
        --primary-model)   PRIMARY_MODEL="$2";  shift 2 ;;
        --subagent-model)  SUBAGENT_MODEL="$2"; shift 2 ;;
        --install-dir)     INSTALL_DIR="$2";    shift 2 ;;
        --token)           GATEWAY_TOKEN="$2";  shift 2 ;;
        *)
            err "Unknown argument: $1"
            echo "Usage: $0 [--primary-model MODEL] [--subagent-model MODEL] [--install-dir PATH] [--token TOKEN]"
            exit 1
            ;;
    esac
done

# ── Auto-generate a token if not provided ─────────────────────
if [[ -z "$GATEWAY_TOKEN" ]]; then
    if command -v openssl &>/dev/null; then
        GATEWAY_TOKEN=$(openssl rand -base64 32 | tr -dc 'a-zA-Z0-9' | head -c 40)
    else
        GATEWAY_TOKEN=$(cat /dev/urandom | LC_ALL=C tr -dc 'a-zA-Z0-9' | head -c 40)
    fi
    info "Auto-generated gateway token."
fi

# ── Detect OS ─────────────────────────────────────────────────
OS="unknown"
OLLAMA_HOST_URL="http://host.docker.internal:11434/v1"

case "$(uname -s)" in
    Linux*)
        OS="linux"
        # On Linux, host.docker.internal is NOT always available.
        # We use the docker bridge gateway IP instead, which is always 172.17.0.1
        # unless the user has a custom bridge (rare).
        OLLAMA_HOST_URL="http://172.17.0.1:11434/v1"
        ;;
    Darwin*)
        OS="macos"
        # On macOS Docker Desktop, host.docker.internal works fine.
        OLLAMA_HOST_URL="http://host.docker.internal:11434/v1"
        ;;
    *)
        warn "Unknown OS: $(uname -s) — assuming Linux behaviour."
        OS="linux"
        OLLAMA_HOST_URL="http://172.17.0.1:11434/v1"
        ;;
esac

info "Detected OS: $OS"

# ─────────────────────────────────────────────────────────────
# STEP 1 — Prerequisite checks
# ─────────────────────────────────────────────────────────────
title "Checking prerequisites"

# Docker
if ! command -v docker &>/dev/null; then
    err "Docker is not installed."
    if [[ "$OS" == "macos" ]]; then
        err "Download Docker Desktop from: https://www.docker.com/products/docker-desktop"
    else
        err "Install Docker Engine: https://docs.docker.com/engine/install/"
        err "  Ubuntu/Debian:  curl -fsSL https://get.docker.com | bash"
    fi
    exit 1
fi
ok "Docker found: $(docker --version)"

# Docker daemon running?
if ! docker info &>/dev/null; then
    err "Docker daemon is not running."
    if [[ "$OS" == "macos" ]]; then
        err "Start Docker Desktop from Applications."
    else
        err "Run: sudo systemctl start docker"
    fi
    exit 1
fi
ok "Docker daemon is running."

# Docker Compose (v2 plugin preferred, v1 fallback)
if docker compose version &>/dev/null 2>&1; then
    COMPOSE_CMD="docker compose"
    ok "Docker Compose v2 found: $(docker compose version)"
elif command -v docker-compose &>/dev/null; then
    COMPOSE_CMD="docker-compose"
    warn "Using legacy docker-compose v1. Upgrade to v2 is recommended."
    ok "docker-compose found: $(docker-compose --version)"
else
    err "Docker Compose is not installed."
    err "Install: https://docs.docker.com/compose/install/"
    exit 1
fi

# Git
if ! command -v git &>/dev/null; then
    err "Git is not installed."
    if [[ "$OS" == "macos" ]]; then
        err "Install via Homebrew: brew install git"
        err "Or Xcode tools:       xcode-select --install"
    else
        err "Install via apt:      sudo apt install git -y"
        err "Install via dnf:      sudo dnf install git -y"
    fi
    exit 1
fi
ok "Git found: $(git --version)"

# Ollama (warn only — Ollama might not have a CLI on PATH but still run as a service)
if command -v ollama &>/dev/null; then
    ok "Ollama CLI found: $(ollama --version 2>/dev/null || echo 'version unknown')"
else
    warn "Ollama CLI not found in PATH."
    warn "If Ollama is running as a background service, this is fine."
    warn "Otherwise download from: https://ollama.com"
    read -rp "Continue anyway? (y/n): " cont
    [[ "$cont" == "y" ]] || exit 1
fi

# Check Ollama HTTP API is reachable (works whether or not CLI is on PATH)
info "Checking Ollama API is reachable on http://localhost:11434 ..."
if curl -sf "http://localhost:11434/api/tags" &>/dev/null; then
    ok "Ollama API is responding."
else
    warn "Could not reach Ollama API on localhost:11434."
    warn "Make sure Ollama is started before using OpenClaw."
fi

# ─────────────────────────────────────────────────────────────
# STEP 2 — Pull Ollama models
# ─────────────────────────────────────────────────────────────
title "Pulling Ollama models (first pull may take a while)"

info "Pulling primary model: $PRIMARY_MODEL"
if command -v ollama &>/dev/null; then
    ollama pull "$PRIMARY_MODEL" || warn "Could not pull $PRIMARY_MODEL — check Ollama is running."
else
    warn "Ollama CLI not available — skipping model pull."
    warn "Run manually:  ollama pull $PRIMARY_MODEL"
fi

if [[ "$SUBAGENT_MODEL" != "$PRIMARY_MODEL" ]]; then
    info "Pulling subagent model: $SUBAGENT_MODEL"
    if command -v ollama &>/dev/null; then
        ollama pull "$SUBAGENT_MODEL" || warn "Could not pull $SUBAGENT_MODEL"
    fi
fi

ok "Model pull complete."

# ─────────────────────────────────────────────────────────────
# STEP 3 — Clone or update OpenClaw repo
# ─────────────────────────────────────────────────────────────
title "Setting up OpenClaw directory at $INSTALL_DIR"

if [[ -d "$INSTALL_DIR/.git" ]]; then
    info "OpenClaw repo already exists — pulling latest..."
    git -C "$INSTALL_DIR" pull
else
    info "Cloning OpenClaw repo..."
    git clone https://github.com/openclaw/openclaw.git "$INSTALL_DIR"
fi

cd "$INSTALL_DIR"
ok "Repo ready at $INSTALL_DIR"

# ─────────────────────────────────────────────────────────────
# STEP 4 — Copy docker-compose.yml
# ─────────────────────────────────────────────────────────────
title "Writing docker-compose.yml"

# Determine the script's own directory so we can copy our customised compose file
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [[ -f "$SCRIPT_DIR/docker-compose.yml" ]]; then
    # Patch the Ollama URL for the current OS before copying
    sed "s|http://host.docker.internal:11434/v1|$OLLAMA_HOST_URL|g" \
        "$SCRIPT_DIR/docker-compose.yml" > "$INSTALL_DIR/docker-compose.yml"
    ok "docker-compose.yml written (Ollama URL: $OLLAMA_HOST_URL)"
else
    warn "docker-compose.yml not found next to setup.sh — using repo default."
fi

# ─────────────────────────────────────────────────────────────
# STEP 5 — Write .env file
# ─────────────────────────────────────────────────────────────
title "Writing .env"

cat > "$INSTALL_DIR/.env" <<EOF
# Auto-generated by setup.sh on $(date "+%Y-%m-%d %H:%M")
OPENCLAW_GATEWAY_TOKEN=$GATEWAY_TOKEN
OPENCLAW_PRIMARY_MODEL=ollama/$PRIMARY_MODEL
OPENCLAW_SUBAGENT_MODEL=ollama/$SUBAGENT_MODEL
OPENCLAW_OLLAMA_BASE_URL=$OLLAMA_HOST_URL
OPENCLAW_GATEWAY_BIND=loopback
EOF

ok ".env written."

# ─────────────────────────────────────────────────────────────
# STEP 6 — Write openclaw.json into ~/.openclaw/
# ─────────────────────────────────────────────────────────────
title "Writing openclaw.json"

CONFIG_DIR="$HOME/.openclaw"
mkdir -p "$CONFIG_DIR"

# Use our template file if present, otherwise generate inline
if [[ -f "$SCRIPT_DIR/openclaw.json" ]]; then
    sed \
        -e "s|llama3.2:latest|$PRIMARY_MODEL|g" \
        -e "s|qwen2.5-coder:7b|$SUBAGENT_MODEL|g" \
        -e "s|http://host.docker.internal:11434/v1|$OLLAMA_HOST_URL|g" \
        "$SCRIPT_DIR/openclaw.json" > "$CONFIG_DIR/openclaw.json"
else
    # Inline fallback if template is missing
    cat > "$CONFIG_DIR/openclaw.json" <<EOF
{
  "gateway": {
    "bind": "loopback",
    "port": 18789,
    "auth": { "mode": "token" },
    "log": { "level": "info" }
  },
  "models": {
    "providers": {
      "ollama": {
        "baseUrl": "$OLLAMA_HOST_URL",
        "apiKey": "ollama-local",
        "api": "openai-responses",
        "models": [
          {
            "id": "$PRIMARY_MODEL",
            "name": "Primary Model",
            "contextWindow": 65536,
            "maxOutput": 8192
          },
          {
            "id": "$SUBAGENT_MODEL",
            "name": "Subagent Model",
            "contextWindow": 65536,
            "maxOutput": 8192
          }
        ]
      }
    }
  },
  "agents": {
    "defaults": {
      "model": {
        "primary": "ollama/$PRIMARY_MODEL",
        "subagent": "ollama/$SUBAGENT_MODEL"
      },
      "sandbox": { "mode": "off" }
    }
  }
}
EOF
fi

ok "openclaw.json written to $CONFIG_DIR"

# ─────────────────────────────────────────────────────────────
# STEP 7 — Linux: add extra-hosts entry so Docker can reach
#           Ollama on the host via 172.17.0.1
# ─────────────────────────────────────────────────────────────
if [[ "$OS" == "linux" ]]; then
    title "Linux: configuring host network access for Ollama"

    # Ensure Ollama listens on 0.0.0.0 (not just 127.0.0.1)
    OLLAMA_ENV_FILE="/etc/systemd/system/ollama.service.d/override.conf"
    if systemctl is-active --quiet ollama 2>/dev/null; then
        if ! grep -q "OLLAMA_HOST" "$OLLAMA_ENV_FILE" 2>/dev/null; then
            warn "Ollama may be bound to 127.0.0.1 only."
            warn "To allow Docker containers to reach it, run:"
            echo ""
            echo -e "${WHITE}  sudo mkdir -p /etc/systemd/system/ollama.service.d${NC}"
            echo -e "${WHITE}  sudo tee /etc/systemd/system/ollama.service.d/override.conf <<'CONF'${NC}"
            echo -e "${WHITE}  [Service]${NC}"
            echo -e "${WHITE}  Environment=\"OLLAMA_HOST=0.0.0.0\"${NC}"
            echo -e "${WHITE}  CONF${NC}"
            echo -e "${WHITE}  sudo systemctl daemon-reload && sudo systemctl restart ollama${NC}"
            echo ""
            warn "Then re-run this script, or start the gateway manually."
        else
            ok "Ollama systemd override already sets OLLAMA_HOST."
        fi
    else
        info "Ollama systemd service not detected — skipping bind check."
        info "If Ollama is running manually, export OLLAMA_HOST=0.0.0.0 before starting it."
    fi
fi

# ─────────────────────────────────────────────────────────────
# STEP 8 — Build Docker image
# ─────────────────────────────────────────────────────────────
title "Building Docker image (first build: 3-10 min)"

$COMPOSE_CMD build --progress=plain
ok "Docker image built."

# ─────────────────────────────────────────────────────────────
# STEP 9 — Start gateway
# ─────────────────────────────────────────────────────────────
title "Starting OpenClaw gateway"

$COMPOSE_CMD up -d openclaw-gateway
ok "Gateway container started."

# Wait for health check
info "Waiting for gateway to become healthy (up to 60s)..."
RETRIES=0
while [[ $RETRIES -lt 12 ]]; do
    HEALTH=$(docker inspect --format='{{.State.Health.Status}}' openclaw-gateway 2>/dev/null || echo "starting")
    if [[ "$HEALTH" == "healthy" ]]; then
        ok "Gateway is healthy!"
        break
    fi
    sleep 5
    (( RETRIES++ )) || true
done

if [[ "$HEALTH" != "healthy" ]]; then
    warn "Health check timed out — gateway may still be starting."
    warn "Check logs: $COMPOSE_CMD logs openclaw-gateway"
fi

# ─────────────────────────────────────────────────────────────
# DONE
# ─────────────────────────────────────────────────────────────
title "Setup complete! 🦞"

echo ""
echo -e "${WHITE}  Dashboard URL:${NC}"
echo -e "${GREEN}  http://localhost:18789/?token=${GATEWAY_TOKEN}${NC}"
echo ""
echo -e "${YELLOW}  ⚠  Save this URL — the token is required to log in.${NC}"
echo ""
echo -e "${WHITE}  Useful commands:${NC}"
echo "    Check status  :  $COMPOSE_CMD ps"
echo "    Live logs     :  $COMPOSE_CMD logs -f openclaw-gateway"
echo "    Stop          :  $COMPOSE_CMD down"
echo "    Restart       :  $COMPOSE_CMD restart openclaw-gateway"
echo "    List models   :  $COMPOSE_CMD exec openclaw-gateway node dist/index.js models list"
echo "    Switch model  :  $COMPOSE_CMD exec openclaw-gateway node dist/index.js config set \\"
echo "                         agents.defaults.model.primary ollama/mistral:latest"
echo ""
