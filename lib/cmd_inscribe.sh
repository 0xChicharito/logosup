#!/usr/bin/env bash
# DESCRIPTION: Inscribe (publish) messages to the Logos blockchain

cmd_inscribe() {
    detect_platform
    check_docker

    if ! docker_is_running; then
        die "Logos Node is not running. Start it first with: logos-node start"
    fi

    local message="${1:-}"

    if [[ -z "$message" ]]; then
        echo ""
        log_step "Inscribe a message to the Logos blockchain"
        echo ""
        log_info "Publish text messages on-chain using the built-in text sequencer."
        log_info "Messages are inscribed as transactions on the Logos blockchain."
        echo ""
        log_info "${BOLD}Usage:${RESET}"
        log_info "  logos-node inscribe \"your message here\""
        log_info "  logos-node inscribe --interactive"
        echo ""
        log_info "${BOLD}Options:${RESET}"
        log_info "  --interactive, -i    Enter interactive mode for multiple messages"
        echo ""
        return 0
    fi

    # Interactive mode
    if [[ "$message" == "--interactive" ]] || [[ "$message" == "-i" ]]; then
        _inscribe_interactive
        return $?
    fi

    _inscribe_message "$message"
}

_inscribe_message() {
    local message="$1"

    log_step "Inscribing message..."

    # Run the inscribe command inside the running container
    local output
    output="$($DOCKER_CMD exec "$LOGOS_CONTAINER_NAME" \
        logos-blockchain-node inscribe "$message" 2>&1)" || true

    if [[ $? -eq 0 ]] && [[ -n "$output" ]]; then
        echo -e "  ${DIM}${output}${RESET}"
        log_success "Message inscribed"
    else
        # If the container exec approach doesn't work, try via API
        # The inscribe subcommand may need to run as a separate process
        output="$($DOCKER_CMD run --rm \
            --network container:"${LOGOS_CONTAINER_NAME}" \
            "${LOGOS_DOCKER_IMAGE}:${LOGOS_NODE_VERSION}" \
            inscribe "$message" 2>&1)" || true

        if [[ -n "$output" ]]; then
            echo -e "  ${DIM}${output}${RESET}"
        fi

        if echo "$output" | grep -qi "error\|failed\|panic"; then
            log_error "Failed to inscribe message"
            return 1
        else
            log_success "Message inscribed"
        fi
    fi
}

_inscribe_interactive() {
    log_step "Interactive inscription mode"
    log_info "Type a message and press Enter to inscribe. Type 'exit' or Ctrl+C to quit."
    echo ""

    while true; do
        echo -en "${BOLD}inscribe>${RESET} "
        local msg
        read -r msg < /dev/tty 2>/dev/null || break

        if [[ -z "$msg" ]]; then
            continue
        fi

        if [[ "$msg" == "exit" ]] || [[ "$msg" == "quit" ]]; then
            break
        fi

        _inscribe_message "$msg"
        echo ""
    done

    log_info "Exiting interactive mode"
}
