#!/usr/bin/env bash
# DESCRIPTION: Stop the Logos Blockchain node

cmd_stop() {
    detect_platform
    check_docker

    if ! docker_is_running; then
        log_info "Logos Node is not running"
        return 0
    fi

    log_step "Stopping Logos Node..."
    docker_down

    if [[ $? -eq 0 ]]; then
        log_success "Logos Node stopped"
    else
        log_error "Failed to stop Logos Node"
        return 1
    fi
}
