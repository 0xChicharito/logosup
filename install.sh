#!/usr/bin/env bash
set -euo pipefail

# ── Logos Node Installer ─────────────────────────────────────────────
# Usage: curl -sL https://raw.githubusercontent.com/shayanb/logos-node/main/install.sh | bash
# Or:    wget -qO- https://raw.githubusercontent.com/shayanb/logos-node/main/install.sh | bash

LOGOS_NODE_REPO="shayanb/logos-node"
LOGOS_NODE_DIR="${LOGOS_NODE_DIR:-$HOME/.logos-node}"
INSTALL_DIR="${INSTALL_DIR:-/usr/local/bin}"
DOCKER_JUST_INSTALLED=false

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

confirm() {
    local prompt="$1"
    local default="${2:-y}"
    local yn
    if [[ "$default" == "y" ]]; then
        prompt="$prompt [Y/n] "
    else
        prompt="$prompt [y/N] "
    fi
    echo -en "${BOLD}?${RESET} ${prompt}"
    # Read from /dev/tty so prompts work even when script is piped (curl | bash)
    read -r yn < /dev/tty || yn=""
    yn="${yn:-$default}"
    case "$yn" in
        [Yy]*) return 0 ;;
        *)     return 1 ;;
    esac
}

# ── Banner ────────────────────────────────────────────────────────────
echo -e "${BOLD}${CYAN}"
cat << 'BANNER'
  _                              _   _           _
 | |    ___   __ _  ___  ___   | \ | | ___   __| | ___
 | |   / _ \ / _` |/ _ \/ __|  |  \| |/ _ \ / _` |/ _ \
 | |__| (_) | (_| | (_) \__ \  | |\  | (_) | (_| |  __/
 |_____\___/ \__, |\___/|___/  |_| \_|\___/ \__,_|\___|
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

# ── Detect package manager ───────────────────────────────────────────
PKG_MANAGER=""
PKG_INSTALL=""
PKG_UPDATE=""

detect_pkg_manager() {
    if [[ "$OS" == "darwin" ]]; then
        if command -v brew &>/dev/null; then
            PKG_MANAGER="brew"
            PKG_INSTALL="brew install"
            PKG_UPDATE=""
        fi
    elif [[ "$OS" == "linux" ]]; then
        if command -v apt-get &>/dev/null; then
            PKG_MANAGER="apt"
            PKG_INSTALL="sudo apt-get install -y"
            PKG_UPDATE="sudo apt-get update -qq"
        elif command -v dnf &>/dev/null; then
            PKG_MANAGER="dnf"
            PKG_INSTALL="sudo dnf install -y"
            PKG_UPDATE=""
        elif command -v yum &>/dev/null; then
            PKG_MANAGER="yum"
            PKG_INSTALL="sudo yum install -y"
            PKG_UPDATE=""
        elif command -v pacman &>/dev/null; then
            PKG_MANAGER="pacman"
            PKG_INSTALL="sudo pacman -S --noconfirm"
            PKG_UPDATE="sudo pacman -Sy"
        elif command -v apk &>/dev/null; then
            PKG_MANAGER="apk"
            PKG_INSTALL="sudo apk add"
            PKG_UPDATE="sudo apk update"
        elif command -v zypper &>/dev/null; then
            PKG_MANAGER="zypper"
            PKG_INSTALL="sudo zypper install -y"
            PKG_UPDATE=""
        fi
    fi
}

detect_pkg_manager

# Run package manager update (once, lazily)
PKG_UPDATED=false
ensure_pkg_updated() {
    if [[ "$PKG_UPDATED" == "false" ]] && [[ -n "$PKG_UPDATE" ]]; then
        info "Updating package index..."
        $PKG_UPDATE &>/dev/null || true
        PKG_UPDATED=true
    fi
}

# Install a package via the detected package manager
# Usage: install_pkg <display_name> <pkg_name> [alt_pkg_name_for_brew]
install_pkg() {
    local name="$1"
    local pkg="$2"
    local brew_pkg="${3:-$pkg}"

    if [[ -z "$PKG_MANAGER" ]]; then
        return 1
    fi

    ensure_pkg_updated

    local install_cmd="$PKG_INSTALL"
    local install_pkg="$pkg"
    if [[ "$PKG_MANAGER" == "brew" ]]; then
        install_pkg="$brew_pkg"
    fi

    info "Installing ${name}..."
    if $install_cmd "$install_pkg" 2>&1 | while IFS= read -r line; do
        echo -e "  ${DIM}${line}${RESET}"
    done; then
        success "${name} installed"
        return 0
    else
        error "Failed to install ${name}"
        return 1
    fi
}

# ── Check prerequisites ──────────────────────────────────────────────
info "Checking prerequisites..."
echo ""

MISSING=()

# ── Git ───────────────────────────────────────────────────────────────
if command -v git &>/dev/null; then
    success "git $(git --version | awk '{print $3}')"
else
    warn "git is not installed"
    MISSING+=("git")
fi

# ── curl ──────────────────────────────────────────────────────────────
if command -v curl &>/dev/null; then
    success "curl available"
elif command -v wget &>/dev/null; then
    success "wget available"
else
    warn "curl is not installed"
    MISSING+=("curl")
fi

# ── Docker ────────────────────────────────────────────────────────────
DOCKER_MISSING=false
DOCKER_NOT_RUNNING=false

if ! command -v docker &>/dev/null; then
    warn "Docker is not installed"
    DOCKER_MISSING=true
    MISSING+=("docker")
elif ! docker info &>/dev/null 2>&1; then
    warn "Docker is installed but not running"
    DOCKER_NOT_RUNNING=true
else
    success "Docker $(docker --version | awk '{print $3}' | tr -d ',')"
fi

# ── Docker Compose ───────────────────────────────────────────────────
if [[ "$DOCKER_MISSING" == "false" ]] && [[ "$DOCKER_NOT_RUNNING" == "false" ]]; then
    if docker compose version &>/dev/null 2>&1; then
        success "Docker Compose $(docker compose version --short 2>/dev/null)"
    elif command -v docker-compose &>/dev/null; then
        success "docker-compose $(docker-compose --version | awk '{print $NF}')"
    else
        warn "Docker Compose is not installed"
        MISSING+=("docker-compose")
    fi
fi

echo ""

# ── Offer to install missing prerequisites ───────────────────────────
if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo -e "${DIM}────────────────────────────────────────────────────${RESET}"
    echo ""
    info "Missing prerequisites: ${BOLD}${MISSING[*]}${RESET}"
    echo ""

    # Check if we can auto-install
    CAN_AUTO_INSTALL=true
    for pkg in "${MISSING[@]}"; do
        if [[ "$pkg" == "docker" ]]; then
            CAN_AUTO_INSTALL=false
        fi
    done

    # Handle non-Docker packages first
    NON_DOCKER_MISSING=()
    for pkg in "${MISSING[@]}"; do
        if [[ "$pkg" != "docker" ]]; then
            NON_DOCKER_MISSING+=("$pkg")
        fi
    done

    if [[ ${#NON_DOCKER_MISSING[@]} -gt 0 ]] && [[ -n "$PKG_MANAGER" ]]; then
        if confirm "Install ${NON_DOCKER_MISSING[*]} using ${PKG_MANAGER}?"; then
            for pkg in "${NON_DOCKER_MISSING[@]}"; do
                install_pkg "$pkg" "$pkg" || die "Failed to install $pkg. Please install it manually."
            done
            echo ""
        else
            die "Please install the missing prerequisites and re-run this script."
        fi
    elif [[ ${#NON_DOCKER_MISSING[@]} -gt 0 ]]; then
        error "No supported package manager found to auto-install ${NON_DOCKER_MISSING[*]}."
        info "Please install them manually and re-run this script."
        exit 1
    fi

    # Handle Docker separately (complex install)
    if [[ "$DOCKER_MISSING" == "true" ]]; then
        echo ""
        echo -e "${DIM}────────────────────────────────────────────────────${RESET}"
        info "Docker requires a more involved installation."
        echo ""

        case "$OS" in
            linux)
                info "Option 1 — Official install script (recommended):"
                echo -e "  ${BOLD}curl -fsSL https://get.docker.com | sh${RESET}"
                echo ""
                info "Option 2 — Manual install:"
                echo -e "  ${BOLD}https://docs.docker.com/engine/install/${RESET}"
                echo ""
                if confirm "Install Docker using the official script (get.docker.com)?"; then
                    info "Running Docker install script..."
                    if curl -fsSL https://get.docker.com | sh 2>&1 | while IFS= read -r line; do
                        echo -e "  ${DIM}${line}${RESET}"
                    done; then
                        success "Docker installed"

                        # Add user to docker group if not root
                        if [[ "$(id -u)" -ne 0 ]]; then
                            info "Adding current user to the docker group..."
                            sudo usermod -aG docker "$USER" 2>/dev/null || true
                        fi

                        # Start Docker
                        info "Starting Docker service..."
                        sudo systemctl enable docker 2>/dev/null || true
                        sudo systemctl start docker 2>/dev/null || true
                        sleep 3

                        DOCKER_JUST_INSTALLED=true

                        # Wait for daemon
                        local attempts=0
                        while [[ $attempts -lt 10 ]]; do
                            if docker info &>/dev/null 2>&1 || sudo docker info &>/dev/null 2>&1; then
                                break
                            fi
                            sleep 2
                            attempts=$((attempts + 1))
                        done

                        if docker info &>/dev/null 2>&1; then
                            success "Docker is running"
                        elif sg docker -c "docker info" &>/dev/null 2>&1; then
                            success "Docker is running (group activated)"
                        elif sudo docker info &>/dev/null 2>&1; then
                            success "Docker is running"
                            warn "Docker requires sudo until you log out and back in."
                        else
                            warn "Docker installed but daemon may still be starting."
                            info "Try: ${BOLD}sudo docker info${RESET} to verify."
                        fi
                    else
                        die "Docker installation failed. Please install manually and re-run."
                    fi
                else
                    die "Docker is required. Please install it and re-run this script."
                fi
                ;;
            darwin)
                info "Install Docker Desktop for Mac:"
                echo -e "  ${BOLD}https://docs.docker.com/desktop/install/mac-install/${RESET}"
                echo ""
                if command -v brew &>/dev/null; then
                    if confirm "Install Docker Desktop using Homebrew?"; then
                        info "Installing Docker Desktop via Homebrew..."
                        if brew install --cask docker 2>&1 | while IFS= read -r line; do
                            echo -e "  ${DIM}${line}${RESET}"
                        done; then
                            success "Docker Desktop installed"
                            info "Please open Docker Desktop from Applications to start it."
                            echo ""
                            info "Once Docker Desktop is running, re-run this script:"
                            echo -e "  ${BOLD}${CYAN}curl -sL https://raw.githubusercontent.com/shayanb/logos-node/main/install.sh | bash${RESET}"
                            exit 0
                        else
                            die "Docker Desktop installation failed. Please install manually."
                        fi
                    else
                        die "Docker is required. Please install Docker Desktop and re-run."
                    fi
                else
                    die "Docker is required. Please install Docker Desktop and re-run."
                fi
                ;;
        esac

        if [[ "$WSL" == "true" ]]; then
            echo ""
            info "For WSL, make sure Docker Desktop WSL 2 integration is enabled:"
            echo -e "  ${BOLD}https://docs.docker.com/desktop/wsl/${RESET}"
        fi
    fi

    # Re-verify Docker Compose after Docker install
    if [[ "$DOCKER_MISSING" == "true" ]] || [[ "${MISSING[*]}" == *"docker-compose"* ]]; then
        if docker compose version &>/dev/null 2>&1; then
            success "Docker Compose $(docker compose version --short 2>/dev/null)"
        elif sudo docker compose version &>/dev/null 2>&1; then
            success "Docker Compose $(sudo docker compose version --short 2>/dev/null)"
        elif command -v docker-compose &>/dev/null; then
            success "docker-compose available"
        else
            warn "Docker Compose not found. It usually comes with Docker."
            info "Install: ${BOLD}https://docs.docker.com/compose/install/${RESET}"
        fi
    fi

    echo ""
fi

# Handle Docker not running (installed but stopped)
if [[ "$DOCKER_NOT_RUNNING" == "true" ]]; then
    echo -e "${DIM}────────────────────────────────────────────────────${RESET}"
    echo ""
    warn "Docker is installed but the daemon is not running."
    echo ""
    case "$OS" in
        linux)
            if confirm "Start Docker service now?"; then
                info "Starting Docker..."
                sudo systemctl start docker 2>/dev/null || sudo service docker start 2>/dev/null || true
                sleep 3
                if docker info &>/dev/null 2>&1; then
                    success "Docker is running"
                elif sudo docker info &>/dev/null 2>&1; then
                    success "Docker is running (via sudo)"
                else
                    # Daemon may need more time to start
                    info "Waiting for Docker daemon to start..."
                    local attempts=0
                    while [[ $attempts -lt 10 ]]; do
                        sleep 2
                        if docker info &>/dev/null 2>&1 || sudo docker info &>/dev/null 2>&1; then
                            success "Docker is running"
                            break
                        fi
                        attempts=$((attempts + 1))
                    done
                    if [[ $attempts -ge 10 ]]; then
                        die "Failed to start Docker. Please start it manually and re-run."
                    fi
                fi
            else
                die "Docker must be running. Please start it and re-run."
            fi
            ;;
        darwin)
            info "Please open Docker Desktop from Applications to start it."
            info "Once running, re-run this script."
            exit 1
            ;;
    esac
    echo ""
fi

# ── Final prerequisite verification ──────────────────────────────────
READY=true

if ! command -v git &>/dev/null; then
    error "git is still missing"
    READY=false
fi

if ! command -v curl &>/dev/null && ! command -v wget &>/dev/null; then
    error "curl is still missing"
    READY=false
fi

if ! command -v docker &>/dev/null; then
    error "Docker is still missing"
    READY=false
elif ! docker info &>/dev/null 2>&1; then
    # Try activating docker group, then fall back to sudo
    if sg docker -c "docker info" &>/dev/null 2>&1; then
        success "Docker is running"
    elif sudo docker info &>/dev/null 2>&1; then
        success "Docker is running (via sudo)"
    else
        error "Docker is still not running"
        READY=false
    fi
fi

if [[ "$READY" == "false" ]]; then
    die "Not all prerequisites are met. Please fix the above issues and re-run."
fi

echo -e "${DIM}────────────────────────────────────────────────────${RESET}"
success "All prerequisites met"
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
info "Next step: set up your node. This will:"
info "  1. Download the latest Logos Blockchain node"
info "  2. Build the Docker image with ZK circuits"
info "  3. Generate your node configuration and wallet keys"
info "  4. Show you how to get devnet tokens"
echo ""

if confirm "Run logos-node install now?"; then
    echo ""
    # If docker group is available but not active, launch under sg
    if ! docker info &>/dev/null 2>&1 && id -nG 2>/dev/null | grep -qw docker; then
        exec sg docker -c "$CLI_DIR/logos-node install"
    else
        exec "$CLI_DIR/logos-node" install
    fi
fi

echo ""
info "You can run it later with:"
echo -e "  ${BOLD}${CYAN}logos-node install${RESET}"
echo ""
