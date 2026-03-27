#!/usr/bin/env bash
# DESCRIPTION: Configuration file management
# Compatible with bash 3+ (no associative arrays)

LOGOS_NODE_DIR="${LOGOS_NODE_DIR:-$HOME/.logos-node}"
LOGOS_SETTINGS_FILE="$LOGOS_NODE_DIR/settings.env"

# ── Parse network.yml ─────────────────────────────────────────────────
# Simple YAML parser for our flat config (no dependencies needed)

_parse_network_yml() {
    local yml_file="$1"
    [[ -f "$yml_file" ]] || return 1

    # Parse bootstrap_peers list into comma-separated string
    local peers=""
    local in_peers=false
    while IFS= read -r line; do
        if [[ "$line" =~ ^bootstrap_peers: ]]; then
            in_peers=true
            continue
        fi
        if [[ "$in_peers" == true ]]; then
            if [[ "$line" =~ ^[[:space:]]*-[[:space:]]*(.*) ]]; then
                local peer="${BASH_REMATCH[1]}"
                peer="${peer%%[[:space:]]*#*}"  # strip inline comments
                peer="${peer%%[[:space:]]}"     # strip trailing whitespace
                if [[ -n "$peers" ]]; then
                    peers="${peers},${peer}"
                else
                    peers="$peer"
                fi
            else
                in_peers=false
            fi
        fi
    done < "$yml_file"

    [[ -n "$peers" ]] && LOGOS_BOOTSTRAP_PEERS="$peers"

    # Parse simple key: value fields
    local val
    val="$(_yml_get "$yml_file" "network")"       && LOGOS_NETWORK="$val"
    val="$(_yml_get "$yml_file" "node_repo")"      && LOGOS_NODE_REPO="$val"
    val="$(_yml_get "$yml_file" "cli_repo")"       && LOGOS_CLI_REPO="$val"
    val="$(_yml_get "$yml_file" "api_port")"       && LOGOS_API_PORT="$val"
    val="$(_yml_get "$yml_file" "udp_port")"       && LOGOS_UDP_PORT="$val"
    val="$(_yml_get "$yml_file" "faucet_url")"     && LOGOS_FAUCET_URL="$val"
    val="$(_yml_get "$yml_file" "dashboard_url")"  && LOGOS_DASHBOARD_URL="$val"
}

# Get a simple top-level key from a YAML file
_yml_get() {
    local file="$1" key="$2"
    local val
    val="$(grep "^${key}:" "$file" 2>/dev/null | head -1 | sed "s/^${key}:[[:space:]]*//" | sed 's/[[:space:]]*#.*//' | sed 's/[[:space:]]*$//')"
    [[ -n "$val" ]] && echo "$val"
}

# ── Defaults ──────────────────────────────────────────────────────────

_set_defaults() {
    : "${LOGOS_NETWORK:=devnet}"
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
    : "${LOGOS_GRAFANA_PORT:=3001}"
    : "${LOGOS_GRAFANA_AUTH:=false}"
    : "${LOGOS_GRAFANA_PASSWORD:=logos}"

    export LOGOS_NETWORK LOGOS_NODE_VERSION LOGOS_CIRCUITS_VERSION LOGOS_API_PORT LOGOS_UDP_PORT
    export LOGOS_FAUCET_URL LOGOS_DASHBOARD_URL LOGOS_DOCKER_IMAGE LOGOS_CONTAINER_NAME
    export LOGOS_NODE_REPO LOGOS_CLI_REPO LOGOS_BOOTSTRAP_PEERS LOGOS_GRAFANA_PORT
    export LOGOS_GRAFANA_AUTH LOGOS_GRAFANA_PASSWORD
}

# ── Init & Load ───────────────────────────────────────────────────────

init_config() {
    mkdir -p "$LOGOS_NODE_DIR" && chmod 700 "$LOGOS_NODE_DIR"

    if [[ ! -f "$LOGOS_SETTINGS_FILE" ]]; then
        log_info "Creating default settings at $LOGOS_SETTINGS_FILE"
        cat > "$LOGOS_SETTINGS_FILE" << 'SETTINGS'
# Logos Node settings
# Network-specific values (peers, ports, URLs) come from network.yml.
# Override them here if needed.

LOGOS_NODE_VERSION=latest
LOGOS_CIRCUITS_VERSION=latest
LOGOS_DOCKER_IMAGE=logos-node
LOGOS_CONTAINER_NAME=logos-node
SETTINGS
        chmod 600 "$LOGOS_SETTINGS_FILE"
    fi
}

load_config() {
    # 1. Load network.yml from the CLI repo (source of truth for network config)
    local network_yml
    if [[ -n "${LOGOS_NODE_LIB:-}" ]]; then
        network_yml="$(dirname "$LOGOS_NODE_LIB")/network.yml"
    fi
    # Also check the installed CLI location
    if [[ ! -f "${network_yml:-}" ]] && [[ -f "$LOGOS_NODE_DIR/cli/network.yml" ]]; then
        network_yml="$LOGOS_NODE_DIR/cli/network.yml"
    fi
    if [[ -f "${network_yml:-}" ]]; then
        _parse_network_yml "$network_yml"
    fi

    # 2. Override with user settings (settings.env takes precedence)
    if [[ -f "$LOGOS_SETTINGS_FILE" ]]; then
        set -a
        # shellcheck disable=SC1090
        source "$LOGOS_SETTINGS_FILE"
        set +a
    fi

    # 3. Fill in any remaining defaults
    _set_defaults
}

# ── Settings helpers ──────────────────────────────────────────────────

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

get_user_config_path() {
    echo "$LOGOS_NODE_DIR/user_config.yaml"
}

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

    awk '/^[[:space:]]*known_keys:/{found=1; next} found && /^[[:space:]]+[a-f0-9]+:/{print $1; next} found{exit}' "$config" | tr -d ':'
}

# Extract the full known_keys block (public key: private key lines)
get_wallet_keys_full() {
    local config
    config="$(get_user_config_path)"

    if [[ ! -f "$config" ]]; then
        return 1
    fi

    awk '/^[[:space:]]*known_keys:/{found=1; print; next} found && /^[[:space:]]+[a-f0-9]+:/{print; next} found{exit}' "$config"
}
