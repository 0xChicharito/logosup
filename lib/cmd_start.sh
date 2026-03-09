#!/usr/bin/env bash
# DESCRIPTION: Start the Logos Blockchain node

cmd_start() {
    detect_platform
    check_docker

    local config_path
    config_path="$(get_user_config_path)"
    local compose_path
    compose_path="$(get_compose_path)"

    if [[ ! -f "$config_path" ]]; then
        die "Node configuration not found at $config_path\nRun 'logos-node install' first."
    fi

    if [[ ! -f "$compose_path" ]]; then
        die "Docker compose file not found. Run 'logos-node install' first."
    fi

    if docker_is_running; then
        log_warn "Logos Node is already running"
        log_info "Use 'logos-node status' to check node status"
        log_info "Use 'logos-node stop' to stop, then 'logos-node start' to restart"
        return 0
    fi

    log_step "Starting Logos Node..."
    docker_up

    if [[ $? -ne 0 ]]; then
        die "Failed to start node. Check 'logos-node logs' for details."
    fi

    log_success "Logos Node container started"
    log_info "Waiting for node to initialize..."

    if docker_health_wait 120; then
        echo ""
        log_success "Node is running and healthy!"
        echo ""
        # Show brief status
        _show_brief_status
    else
        echo ""
        log_warn "Node started but health check hasn't passed yet"
        log_info "This is normal during initial sync. The node may take a few minutes."
        log_info "Check progress with: ${BOLD}logos-node status${RESET}"
        log_info "View logs with:      ${BOLD}logos-node logs${RESET}"
    fi

    # Start monitoring if compose file exists
    local monitoring_compose
    monitoring_compose="$LOGOS_NODE_DIR/docker-compose.monitoring.yml"
    if [[ -f "$monitoring_compose" ]]; then
        source "$LOGOS_NODE_LIB/monitoring.sh"
        if ! monitoring_is_running; then
            log_step "Starting monitoring stack..."
            monitoring_up
            log_success "Monitoring running at ${BOLD}http://localhost:${LOGOS_GRAFANA_PORT}${RESET}"
        fi
    fi
}

_show_brief_status() {
    local api_url="http://localhost:${LOGOS_API_PORT}"

    local consensus
    consensus="$(curl -sf "${api_url}/cryptarchia/info" 2>/dev/null)" || true

    local network
    network="$(curl -sf "${api_url}/network/info" 2>/dev/null)" || true

    if [[ -n "$consensus" ]]; then
        local mode slot height
        mode="$(echo "$consensus" | sed -E 's/.*"mode":"([^"]+)".*/\1/')"
        slot="$(echo "$consensus" | sed -E 's/.*"slot":([0-9]+).*/\1/')"
        height="$(echo "$consensus" | sed -E 's/.*"height":([0-9]+).*/\1/')"

        log_info "Consensus mode: ${BOLD}${mode}${RESET}"
        log_info "Slot: ${slot}  |  Height: ${height}"
    fi

    if [[ -n "$network" ]]; then
        local peers
        peers="$(echo "$network" | sed -E 's/.*"n_peers":([0-9]+).*/\1/')"
        log_info "Connected peers: ${BOLD}${peers}${RESET}"
    fi
}
