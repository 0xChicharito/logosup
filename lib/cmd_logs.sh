#!/usr/bin/env bash
# DESCRIPTION: View Logos Node logs

cmd_logs() {
    detect_platform
    check_docker

    if ! docker_is_running; then
        log_warn "Logos Node is not running"
        log_info "Showing last available logs..."
        echo ""
    fi

    # Pass through all args (e.g., --tail=50, --since=1h, -f)
    local args=("$@")
    if [[ ${#args[@]} -eq 0 ]]; then
        args=("-f" "--tail=100")
    fi

    docker_logs "${args[@]}"
}
