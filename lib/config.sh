#!/usr/bin/env bash
# DESCRIPTION: Configuration file management
# Compatible with bash 3+ (no associative arrays)

LOGOS_NODE_DIR="${LOGOS_NODE_DIR:-$HOME/.logos-node}"
LOGOS_SETTINGS_FILE="$LOGOS_NODE_DIR/settings.env"

# Set default values (bash 3 compatible)
_set_defaults() {
    : "${LOGOS_NODE_VERSION:=latest}"
    : "${LOGOS_CIRCUITS_VERSION:=latest}"
    : "${LOGOS_API_PORT:=8080}"
    : "${LOGOS_UDP_PORT:=3000}"
    : "${LOGOS_FAUCET_URL:=https://devnet.blockchain.logos.co/web/faucet/}"
    : "${LOGOS_DASHBOARD_URL:=https://devnet.blockchain.logos.co/web/}"
    : "${LOGOS_DOCKER_IMAGE:=logos-node}"
    : "${LOGOS_CONTAINER_NAME:=logos-node}"
    : "${LOGOS_NODE_REPO:=logos-blockchain/logos-blockchain}"
    : "${LOGOS_CLI_REPO:=shayanb/logos-node}"
    : "${LOGOS_BOOTSTRAP_PEERS:=/ip4/65.109.51.37/udp/3000/quic-v1/p2p/12D3KooWL7a8LBbLRYnabptHPFBCmAs49Y7cVMqvzuSdd43tAJk8,/ip4/65.109.51.37/udp/3001/quic-v1/p2p/12D3KooWPLeAcachoUm68NXGD7tmNziZkVeMmeBS5NofyukuMRJh,/ip4/65.109.51.37/udp/3002/quic-v1/p2p/12D3KooWKFNe4gS5DcCcRUVGdMjZp3fUWu6q6gG5R846Ui1pccHD,/ip4/65.109.51.37/udp/3003/quic-v1/p2p/12D3KooWAnriLgXyQnGTYz1zPWPkQL3rthTKYLzuAP7MMnbgsxzR}"

    export LOGOS_NODE_VERSION LOGOS_CIRCUITS_VERSION LOGOS_API_PORT LOGOS_UDP_PORT
    export LOGOS_FAUCET_URL LOGOS_DASHBOARD_URL LOGOS_DOCKER_IMAGE LOGOS_CONTAINER_NAME
    export LOGOS_NODE_REPO LOGOS_CLI_REPO LOGOS_BOOTSTRAP_PEERS
}

# Initialize config directory and settings file
init_config() {
    mkdir -p "$LOGOS_NODE_DIR" && chmod 700 "$LOGOS_NODE_DIR"

    if [[ ! -f "$LOGOS_SETTINGS_FILE" ]]; then
        log_info "Creating default settings at $LOGOS_SETTINGS_FILE"
        cat > "$LOGOS_SETTINGS_FILE" << 'SETTINGS'
# Logos Node settings
# Edit these values or use 'logos-node' commands to manage

LOGOS_NODE_VERSION=latest
LOGOS_CIRCUITS_VERSION=latest
LOGOS_API_PORT=8080
LOGOS_UDP_PORT=3000
LOGOS_FAUCET_URL=https://devnet.blockchain.logos.co/web/faucet/
LOGOS_DASHBOARD_URL=https://devnet.blockchain.logos.co/web/
LOGOS_DOCKER_IMAGE=logos-node
LOGOS_CONTAINER_NAME=logos-node
LOGOS_NODE_REPO=logos-blockchain/logos-blockchain
LOGOS_CLI_REPO=shayanb/logos-node
LOGOS_BOOTSTRAP_PEERS=/ip4/65.109.51.37/udp/3000/quic-v1/p2p/12D3KooWL7a8LBbLRYnabptHPFBCmAs49Y7cVMqvzuSdd43tAJk8,/ip4/65.109.51.37/udp/3001/quic-v1/p2p/12D3KooWPLeAcachoUm68NXGD7tmNziZkVeMmeBS5NofyukuMRJh,/ip4/65.109.51.37/udp/3002/quic-v1/p2p/12D3KooWKFNe4gS5DcCcRUVGdMjZp3fUWu6q6gG5R846Ui1pccHD,/ip4/65.109.51.37/udp/3003/quic-v1/p2p/12D3KooWAnriLgXyQnGTYz1zPWPkQL3rthTKYLzuAP7MMnbgsxzR
SETTINGS
        chmod 600 "$LOGOS_SETTINGS_FILE"
    fi
}

# Load settings from file, falling back to defaults
load_config() {
    # Override with saved settings first (if file exists)
    if [[ -f "$LOGOS_SETTINGS_FILE" ]]; then
        set -a
        # shellcheck disable=SC1090
        source "$LOGOS_SETTINGS_FILE"
        set +a
    fi

    # Then fill in any missing defaults
    _set_defaults
}

# Update a single setting
save_setting() {
    local key="$1"
    local value="$2"

    if grep -q "^${key}=" "$LOGOS_SETTINGS_FILE" 2>/dev/null; then
        if [[ "$(uname -s)" == "Darwin" ]]; then
            sed -i '' "s|^${key}=.*|${key}=${value}|" "$LOGOS_SETTINGS_FILE"
        else
            sed -i "s|^${key}=.*|${key}=${value}|" "$LOGOS_SETTINGS_FILE"
        fi
    else
        echo "${key}=${value}" >> "$LOGOS_SETTINGS_FILE"
    fi
    export "$key=$value"
}

# Get user_config.yaml path
get_user_config_path() {
    echo "$LOGOS_NODE_DIR/user_config.yaml"
}

# Get compose file path
get_compose_path() {
    echo "$LOGOS_NODE_DIR/docker-compose.yml"
}

# Parse known_keys from user_config.yaml
get_wallet_keys() {
    local config
    config="$(get_user_config_path)"

    if [[ ! -f "$config" ]]; then
        return 1
    fi

    # Extract keys from the known_keys section
    awk '/^[[:space:]]*known_keys:/{found=1; next} found && /^[[:space:]]+[a-f0-9]+:/{print $1; next} found{exit}' "$config" | tr -d ':'
}
