#!/usr/bin/env bash
# DESCRIPTION: Manage the monitoring dashboard (Grafana + Prometheus)

cmd_monitor() {
    detect_platform
    check_docker

    source "$LOGOS_NODE_LIB/monitoring.sh"

    local subcmd="${1:-start}"
    shift 2>/dev/null || true

    case "$subcmd" in
        start)
            _monitor_start
            ;;
        stop)
            _monitor_stop
            ;;
        status)
            _monitor_status
            ;;
        -h|--help|help)
            _monitor_help
            ;;
        *)
            log_error "Unknown monitor subcommand: $subcmd"
            _monitor_help
            return 1
            ;;
    esac
}

_monitor_help() {
    echo ""
    log_step "Monitoring dashboard management"
    echo ""
    log_info "${BOLD}Usage:${RESET}"
    log_info "  logos-node monitor [start|stop|status]"
    echo ""
    log_info "${BOLD}Commands:${RESET}"
    log_info "  start    Start the monitoring stack (Grafana + Prometheus + exporter)"
    log_info "  stop     Stop the monitoring stack"
    log_info "  status   Show monitoring status and Grafana URL"
    echo ""
    log_info "Grafana will be available at ${BOLD}http://localhost:${LOGOS_GRAFANA_PORT}${RESET}"
    log_info "Default credentials: admin / logos"
    echo ""
}

_monitor_start() {
    local compose_path
    compose_path="$(get_monitoring_compose_path)"

    # Ensure the node network exists
    $DOCKER_CMD network create logos-net 2>/dev/null || true

    # Generate compose file if it doesn't exist
    if [[ ! -f "$compose_path" ]]; then
        generate_monitoring_compose_file
    fi

    # Build and start
    monitoring_build || die "Failed to build monitoring containers"
    monitoring_up

    echo ""
    log_success "Monitoring stack started"
    echo ""
    log_info "Grafana: ${BOLD}http://localhost:${LOGOS_GRAFANA_PORT}${RESET}"
    log_info "No login required to view dashboards"
    echo ""
    log_info "Stop with: ${BOLD}logos-node monitor stop${RESET}"
    echo ""
}

_monitor_stop() {
    if ! monitoring_is_running; then
        log_info "Monitoring stack is not running"
        return 0
    fi

    log_step "Stopping monitoring stack..."
    monitoring_down
    log_success "Monitoring stack stopped"
}

_monitor_status() {
    print_banner

    log_step "Monitoring"

    local containers=("logos-exporter" "logos-prometheus" "logos-grafana")
    local all_running=true

    for name in "${containers[@]}"; do
        local status
        status="$($DOCKER_CMD ps --filter "name=${name}" --format '{{.Status}}' 2>/dev/null)"
        if [[ -n "$status" ]]; then
            log_success "${name}: ${status}"
        else
            log_error "${name}: not running"
            all_running=false
        fi
    done

    echo ""
    if [[ "$all_running" == "true" ]]; then
        log_info "Grafana: ${BOLD}http://localhost:${LOGOS_GRAFANA_PORT}${RESET}"
    else
        log_info "Start with: ${BOLD}logos-node monitor start${RESET}"
    fi
    echo ""
}
