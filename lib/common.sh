#!/usr/bin/env bash
# DESCRIPTION: Shared utilities — colors, logging, platform detection, portability shims

# ── Colors & formatting ──────────────────────────────────────────────
if [[ -t 1 ]] && [[ "${TERM:-}" != "dumb" ]]; then
    RED='\033[0;31m'
    GREEN='\033[0;32m'
    YELLOW='\033[1;33m'
    BLUE='\033[0;34m'
    CYAN='\033[0;36m'
    BOLD='\033[1m'
    DIM='\033[2m'
    RESET='\033[0m'
else
    RED='' GREEN='' YELLOW='' BLUE='' CYAN='' BOLD='' DIM='' RESET=''
fi

# ── Logging ───────────────────────────────────────────────────────────
log_info()    { echo -e "${BLUE}ℹ${RESET}  $*"; }
log_success() { echo -e "${GREEN}✔${RESET}  $*"; }
log_warn()    { echo -e "${YELLOW}⚠${RESET}  $*"; }
log_error()   { echo -e "${RED}✖${RESET}  $*" >&2; }
log_step()    { echo -e "\n${BOLD}${CYAN}▸ $*${RESET}"; }
log_dim()     { echo -e "${DIM}  $*${RESET}"; }

die() {
    log_error "$@"
    exit 1
}

# ── Confirmation prompt ───────────────────────────────────────────────
# Usage: confirm "Do something?" [y|n]   (default answer)
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
    read -r yn
    yn="${yn:-$default}"

    case "$yn" in
        [Yy]*) return 0 ;;
        *)     return 1 ;;
    esac
}

# ── Spinner ───────────────────────────────────────────────────────────
# Usage: spinner <pid> "message"
spinner() {
    local pid="$1"
    local msg="$2"
    local frames=('⠋' '⠙' '⠹' '⠸' '⠼' '⠴' '⠦' '⠧' '⠇' '⠏')
    local i=0

    while kill -0 "$pid" 2>/dev/null; do
        echo -en "\r${CYAN}${frames[$i]}${RESET} ${msg}"
        i=$(( (i + 1) % ${#frames[@]} ))
        sleep 0.1
    done

    wait "$pid"
    local exit_code=$?
    echo -en "\r\033[K"  # clear line
    return $exit_code
}

# Run a command with a spinner. Returns the command's exit code.
# Usage: run_with_spinner "Building image..." docker build .
run_with_spinner() {
    local msg="$1"
    shift

    "$@" &>/dev/null &
    local pid=$!
    spinner "$pid" "$msg"
    local exit_code=$?

    if [[ $exit_code -eq 0 ]]; then
        log_success "$msg done"
    else
        log_error "$msg failed (exit code $exit_code)"
    fi
    return $exit_code
}

# ── Platform detection ────────────────────────────────────────────────
detect_platform() {
    local os arch
    os="$(uname -s | tr '[:upper:]' '[:lower:]')"
    arch="$(uname -m)"

    case "$os" in
        linux)   LOGOS_OS="linux" ;;
        darwin)  LOGOS_OS="macos" ;;
        msys*|mingw*|cygwin*)
            die "Native Windows is not supported. Please use WSL2: https://learn.microsoft.com/en-us/windows/wsl/install"
            ;;
        *)       die "Unsupported OS: $os" ;;
    esac

    case "$arch" in
        x86_64|amd64)   LOGOS_ARCH="x86_64"; DOCKER_ARCH="amd64" ;;
        aarch64|arm64)  LOGOS_ARCH="aarch64"; DOCKER_ARCH="arm64" ;;
        *)              die "Unsupported architecture: $arch" ;;
    esac

    # WSL detection
    LOGOS_WSL=false
    if [[ -f /proc/version ]] && grep -qi microsoft /proc/version 2>/dev/null; then
        LOGOS_WSL=true
    fi

    export LOGOS_OS LOGOS_ARCH DOCKER_ARCH LOGOS_WSL
}

# ── Portability shims ────────────────────────────────────────────────

# readlink -f replacement for macOS
resolve_path() {
    local target="$1"
    cd "$(dirname "$target")" 2>/dev/null || return 1
    target="$(basename "$target")"
    while [[ -L "$target" ]]; do
        target="$(readlink "$target")"
        cd "$(dirname "$target")" 2>/dev/null || return 1
        target="$(basename "$target")"
    done
    echo "$(pwd -P)/$target"
}

# Portable sed in-place
sed_inplace() {
    if [[ "$LOGOS_OS" == "macos" ]]; then
        sed -i '' "$@"
    else
        sed -i "$@"
    fi
}

# ── Requirement checks ───────────────────────────────────────────────
require_cmd() {
    local cmd="$1"
    local install_hint="${2:-}"

    if ! command -v "$cmd" &>/dev/null; then
        log_error "'$cmd' is required but not installed."
        [[ -n "$install_hint" ]] && log_info "$install_hint"
        exit 1
    fi
}

# ── Header / banner ──────────────────────────────────────────────────
print_banner() {
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
}

print_separator() {
    echo -e "${DIM}────────────────────────────────────────────────────${RESET}"
}
