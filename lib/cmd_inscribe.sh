#!/usr/bin/env bash
# DESCRIPTION: Inscribe (publish) text to the Logos blockchain

cmd_inscribe() {
    detect_platform
    check_docker

    if ! docker_is_running; then
        die "Logos Node is not running. Start it first with: logosup start"
    fi

    local mode="${1:-}"

    case "$mode" in
        -h|--help|help|"")
            echo ""
            log_step "Inscribe text to the Logos blockchain"
            echo ""
            log_info "Publish text inscriptions as zone blocks using the built-in text sequencer."
            log_info "The sequencer reads text from stdin and publishes it on-chain."
            echo ""
            log_info "${BOLD}Usage:${RESET}"
            log_info "  logosup inscribe                       # Interactive: type and publish"
            log_info "  echo \"hello\" | logosup inscribe -       # Pipe text to inscribe"
            log_info "  logosup inscribe < message.txt          # Inscribe from a file"
            echo ""
            log_info "${BOLD}Options:${RESET}"
            log_info "  The sequencer creates a signing key (sequencer.key) and checkpoint"
            log_info "  file (sequencer.checkpoint) in the node data directory for crash recovery."
            echo ""

            if [[ -z "$mode" ]]; then
                if confirm "Start interactive inscription?"; then
                    _run_inscribe
                fi
            fi
            return 0
            ;;
        -)
            # Pipe mode: read from stdin
            _run_inscribe
            ;;
        *)
            # Any other arg: show help
            log_error "Unknown option: $mode"
            log_info "Run 'logosup inscribe --help' for usage"
            return 1
            ;;
    esac
}

_run_inscribe() {
    log_step "Starting text sequencer..."
    log_info "Type text and press Enter to inscribe. Press Ctrl+C to stop."
    echo ""

    # Run inscribe inside the container, connecting to the local node API.
    # The sequencer key and checkpoint are stored in the data volume.
    $DOCKER_CMD exec -it \
        -w /app/data \
        "$LOGOS_CONTAINER_NAME" \
        logos-blockchain-node inscribe \
            --node-url "http://localhost:8080" \
            --key-path /app/data/sequencer.key \
            --checkpoint-path /app/data/sequencer.checkpoint

    echo ""
    log_info "Sequencer stopped"
}
