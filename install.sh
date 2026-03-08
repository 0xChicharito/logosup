#!/usr/bin/env bash
set -euo pipefail

# ── Logos Node Installer ─────────────────────────────────────────────
# Usage: curl -sL https://raw.githubusercontent.com/shayanb/logos-node/main/install.sh | bash
# Or:    wget -qO- https://raw.githubusercontent.com/shayanb/logos-node/main/install.sh | bash

LOGOS_NODE_REPO="shayanb/logos-node"
LOGOS_NODE_DIR="${LOGOS_NODE_DIR:-$HOME/.logos-node}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"

# ── Colors ────────────────────────────────────────────────────────────
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    RED='\033[0;31m' GREEN='\033[0;32m' YELLOW='\033[1;33m'
    BLUE='\033[0;34m' CYAN='\033[0;36m' BOLD='\033[1m'
    DIM='\033[2m' RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' RESET=''
fi

info()    { echo -e "${BLUE}ℹ${RESET}  $*"; }
success() { echo -e "${GREEN}✔${RESET}  $*"; }
warn()    { echo -e "${YELLOW}⚠${RESET}  $*"; }
error()   { echo -e "${RED}✖${RESET}  $*" >&2; }
die()     { error "$@"; exit 1; }

# ── Banner ────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
cat << 'BANNER'
  _                           _   _           _
 | |    ___   __ _  ___  ___ | \ | | ___   __| | ___
 | |   / _ \ / _` |/ _ \/ __||  \| |/ _ \ / _` |/ _ \
 | |__| (_) | (_| | (_) \__ \| |\  | (_) | (_| |  __/
 |_____\___/ \__, |\___/|___/|_| \_|\___/ \__,_|\___|
             |___/
BANNER
echo -e "${RESET}"
echo -e "${BOLD}Logos Node Installer${RESET}"
echo -e "${DIM}────────────────────────────────────────────────────${RESET}"
echo ""

# ── Platform detection ────────────────────────────────────────────────
OS="$(uname -s | tr '[:upper:]' '[:lower:]')"
ARCH="$(uname -m)"

case "$OS" in
    linux)   PLATFORM="Linux" ;;
    darwin)  PLATFORM="macOS" ;;
    msys*|mingw*|cygwin*)
        die "Native Windows is not supported. Please use WSL2:\nhttps://learn.microsoft.com/en-us/windows/wsl/install"
        ;;
    *)       die "Unsupported OS: $OS" ;;
esac

WSL=false
if [[ -f /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null; then
    WSL=true
    PLATFORM="WSL (Windows)"
fi

case "$ARCH" in
    x86_64|amd64)   ARCH_NAME="x86_64" ;;
    aarch64|arm64)  ARCH_NAME="aarch64" ;;
    *)              die "Unsupported architecture: $ARCH" ;;
esac

info "Platform: ${BOLD}${PLATFORM} / ${ARCH_NAME}${RESET}"

# ── Check prerequisites ──────────────────────────────────────────────
info "Checking prerequisites..."

# Git
if ! command -v git &>/dev/null; then
    die "git is required.\nInstall: https://git-scm.com/downloads"
fi
success "git $(git --version | awk '{print $3}')"

# curl or wget
if command -v curl &>/dev/null; then
    success "curl available"
elif command -v wget &>/dev/null; then
    success "wget available"
else
    die "curl or wget is required"
fi

# Docker
if ! command -v docker &>/dev/null; then
    error "Docker is not installed."
    echo ""
    case "$OS" in
        linux)
            info "Install Docker Engine:"
            info "  ${BOLD}https://docs.docker.com/engine/install/${RESET}"
            ;;
        darwin)
            info "Install Docker Desktop for Mac:"
            info "  ${BOLD}https://docs.docker.com/desktop/install/mac-install/${RESET}"
            ;;
    esac
    if [[ "$WSL" == "true" ]]; then
        info "For WSL, enable Docker Desktop WSL 2 integration:"
        info "  ${BOLD}https://docs.docker.com/desktop/wsl/${RESET}"
    fi
    echo ""
    die "Please install Docker and re-run this script."
fi

if ! docker info &>/dev/null; then
    error "Docker daemon is not running."
    case "$OS" in
        linux)  info "Start with: ${BOLD}sudo systemctl start docker${RESET}" ;;
        darwin) info "Start Docker Desktop from your Applications folder" ;;
    esac
    die "Please start Docker and re-run this script."
fi
success "Docker $(docker --version | awk '{print $3}' | tr -d ',')"

# Docker Compose
if docker compose version &>/dev/null 2>&1; then
    success "Docker Compose $(docker compose version --short 2>/dev/null)"
elif command -v docker-compose &>/dev/null; then
    success "docker-compose $(docker-compose --version | awk '{print $NF}')"
else
    die "Docker Compose is required.\nInstall: https://docs.docker.com/compose/install/"
fi

echo ""

# ── Install CLI ───────────────────────────────────────────────────────
info "Installing Logos Node CLI..."

CLI_DIR="$LOGOS_NODE_DIR/cli"

mkdir -p "$LOGOS_NODE_DIR" && chmod 700 "$LOGOS_NODE_DIR"

if [[ -d "$CLI_DIR/.git" ]]; then
    info "Updating existing installation..."
    git -C "$CLI_DIR" pull --quiet 2>/dev/null || {
        warn "Could not update. Reinstalling..."
        rm -rf "$CLI_DIR"
        git clone --depth 1 "https://github.com/${LOGOS_NODE_REPO}.git" "$CLI_DIR"
    }
else
    if [[ -d "$CLI_DIR" ]]; then
        rm -rf "$CLI_DIR"
    fi
    git clone --depth 1 "https://github.com/${LOGOS_NODE_REPO}.git" "$CLI_DIR"
fi

chmod +x "$CLI_DIR/logos-node"
success "CLI installed to $CLI_DIR"

# ── Create symlinks ──────────────────────────────────────────────────
info "Setting up command aliases..."

create_symlink() {
    local target="$1"
    local link_name="$2"
    local link_path="$INSTALL_DIR/$link_name"

    if [[ -L "$link_path" ]] || [[ -e "$link_path" ]]; then
        rm -f "$link_path" 2>/dev/null || {
            sudo rm -f "$link_path"
        }
    fi

    ln -sf "$target" "$link_path" 2>/dev/null || {
        info "Need sudo to create symlink in $INSTALL_DIR"
        sudo ln -sf "$target" "$link_path"
    }
}

FALLBACK_TO_PATH=false

if [[ -d "$INSTALL_DIR" ]] && [[ -w "$INSTALL_DIR" ]]; then
    create_symlink "$CLI_DIR/logos-node" "logos-node"
    create_symlink "$CLI_DIR/logos-node" "logosnode"
    success "Commands available: ${BOLD}logos-node${RESET} and ${BOLD}logosnode${RESET}"
else
    # Try with sudo
    if command -v sudo &>/dev/null; then
        info "Need sudo to install to $INSTALL_DIR"
        if sudo ln -sf "$CLI_DIR/logos-node" "$INSTALL_DIR/logos-node" 2>/dev/null && \
           sudo ln -sf "$CLI_DIR/logos-node" "$INSTALL_DIR/logosnode" 2>/dev/null; then
            success "Commands available: ${BOLD}logos-node${RESET} and ${BOLD}logosnode${RESET}"
        else
            FALLBACK_TO_PATH=true
        fi
    else
        FALLBACK_TO_PATH=true
    fi
fi

if [[ "$FALLBACK_TO_PATH" == "true" ]]; then
    # Fallback: use ~/.local/bin
    LOCAL_BIN="$HOME/.local/bin"
    mkdir -p "$LOCAL_BIN"
    ln -sf "$CLI_DIR/logos-node" "$LOCAL_BIN/logos-node"
    ln -sf "$CLI_DIR/logos-node" "$LOCAL_BIN/logosnode"
    warn "Installed to $LOCAL_BIN (add to PATH if needed)"

    if [[ ":$PATH:" != *":$LOCAL_BIN:"* ]]; then
        echo ""
        warn "Add this to your shell profile (~/.bashrc or ~/.zshrc):"
        echo -e "  ${BOLD}export PATH=\"\$HOME/.local/bin:\$PATH\"${RESET}"
        echo ""
    fi
fi

# ── Done ──────────────────────────────────────────────────────────────
echo ""
echo -e "${DIM}────────────────────────────────────────────────────${RESET}"
success "${BOLD}Logos Node CLI installed successfully!${RESET}"
echo ""
info "Next step: run the installer to set up your node:"
echo ""
echo -e "  ${BOLD}${CYAN}logos-node install${RESET}"
echo ""
info "This will:"
info "  1. Download the latest Logos Blockchain node"
info "  2. Build the Docker image with ZK circuits"
info "  3. Generate your node configuration and wallet keys"
info "  4. Show you how to get devnet tokens"
echo ""
