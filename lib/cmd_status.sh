#!/usr/bin/env bash
# DESCRIPTION: Show Logos Node status and health

cmd_status() {
    detect_platform
    check_docker

    print_banner

    local api_url="http://localhost:${LOGOS_API_PORT}"

    # Container status
    log_step "Container"
    if docker_is_running; then
        local container_status
        container_status="$(docker inspect --format='{{.State.Status}} (up since {{.State.StartedAt}})' "$LOGOS_CONTAINER_NAME" 2>/dev/null)" || true
        log_success "Running: ${container_status}"

        local health
        health="$(docker inspect --format='{{.State.Health.Status}}' "$LOGOS_CONTAINER_NAME" 2>/dev/null)" || true
        if [[ -n "$health" ]]; then
            case "$health" in
                healthy)   log_success "Health: ${GREEN}healthy${RESET}" ;;
                unhealthy) log_warn "Health: ${RED}unhealthy${RESET}" ;;
                starting)  log_info "Health: ${YELLOW}starting${RESET}" ;;
            esac
        fi
    else
        log_error "Not running"
        log_info "Start with: ${BOLD}logos-node start${RESET}"
        return 1
    fi

    # Consensus info
    log_step "Consensus"
    local consensus
    consensus="$(curl -sf "${api_url}/cryptarchia/info" 2>/dev/null)" || true

    if [[ -n "$consensus" ]]; then
        local mode slot height lib tip
        mode="$(echo "$consensus" | sed -E 's/.*"mode":"([^"]+)".*/\1/')"
        slot="$(echo "$consensus" | sed -E 's/.*"slot":([0-9]+).*/\1/')"
        height="$(echo "$consensus" | sed -E 's/.*"height":([0-9]+).*/\1/')"

        case "$mode" in
            Online)        log_success "Mode: ${GREEN}${mode}${RESET}" ;;
            Bootstrapping) log_info "Mode: ${YELLOW}${mode}${RESET} (syncing...)" ;;
            *)             log_info "Mode: ${mode}" ;;
        esac

        log_info "Slot:   ${BOLD}${slot}${RESET}"
        log_info "Height: ${BOLD}${height}${RESET}"
    else
        log_warn "Could not reach consensus API"
    fi

    # Network info
    log_step "Network"
    local network
    network="$(curl -sf "${api_url}/network/info" 2>/dev/null)" || true

    if [[ -n "$network" ]]; then
        local peers connections peer_id
        peers="$(echo "$network" | sed -E 's/.*"n_peers":([0-9]+).*/\1/')"
        connections="$(echo "$network" | sed -E 's/.*"n_connections":([0-9]+).*/\1/')"
        peer_id="$(echo "$network" | sed -E 's/.*"peer_id":"([^"]+)".*/\1/')"

        log_info "Peer ID:     ${DIM}${peer_id}${RESET}"
        log_info "Peers:       ${BOLD}${peers}${RESET}"
        log_info "Connections: ${BOLD}${connections}${RESET}"
    else
        log_warn "Could not reach network API"
    fi

    # Wallet balance (if keys are available)
    local keys
    keys="$(get_wallet_keys 2>/dev/null)"

    if [[ -n "$keys" ]]; then
        source "$LOGOS_NODE_LIB/wallet.sh"
        log_step "Wallet"
        while IFS= read -r key; do
            # Bare call, then read WALLET_HTTP_CODE / WALLET_BODY globals.
            # Don't use $(wallet_get_balance ...) — subshells lose the globals.
            wallet_get_balance "$key"

            if [[ "$WALLET_HTTP_CODE" == "200" && -n "$WALLET_BODY" ]]; then
                local balance
                balance="$(echo "$WALLET_BODY" | sed -E 's/.*"balance":([0-9]+).*/\1/')"
                log_info "${DIM}${key}${RESET}  balance: ${BOLD}${balance}${RESET}"
            elif [[ "$WALLET_HTTP_CODE" == "200" ]]; then
                log_info "${DIM}${key}${RESET}  balance: ${BOLD}0${RESET}"
            elif echo "$WALLET_BODY" | grep -qi "not found"; then
                log_info "${DIM}${key}${RESET}  balance: ${BOLD}0${RESET} ${DIM}(no funds received yet)${RESET}"
            else
                log_info "${DIM}${key}${RESET}  balance: ${DIM}error (HTTP ${WALLET_HTTP_CODE}): $(wallet_squash_body "$WALLET_BODY" 120 "$WALLET_HTTP_CODE")${RESET}"
            fi
        done <<< "$keys"
    fi

    # Useful links
    echo ""
    print_separator
    log_info "Dashboard: ${BOLD}${LOGOS_DASHBOARD_URL}${RESET}"
    log_info "Faucet:    ${BOLD}${LOGOS_FAUCET_URL}${RESET}"
    if [[ -f "$LOGOS_NODE_DIR/docker-compose.monitoring.yml" ]]; then
        local grafana_host
        grafana_host="$(hostname -I 2>/dev/null | awk '{print $1}')" || true
        grafana_host="${grafana_host:-localhost}"
        log_info "Grafana:   ${BOLD}https://${grafana_host}:${LOGOS_GRAFANA_PORT}${RESET}"
        log_dim "Self-signed cert — accept the browser warning on first visit"
    fi
    echo ""
}
