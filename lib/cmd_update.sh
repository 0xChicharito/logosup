#!/usr/bin/env bash
# DESCRIPTION: Update the Logos Node and/or CLI tool

cmd_update() {
    detect_platform
    check_docker
    load_config

    local update_cli=false
    local update_node=false

    case "${1:-all}" in
        cli)  update_cli=true ;;
        node) update_node=true ;;
        all)  update_cli=true; update_node=true ;;
        *)
            log_error "Unknown update target: $1"
            log_info "Usage: logos-node update [cli|node|all]"
            return 1
            ;;
    esac

    print_banner

    # ── CLI update ────────────────────────────────────────────────────
    if [[ "$update_cli" == "true" ]]; then
        log_step "Checking for CLI updates..."

        local cli_dir="$LOGOS_NODE_DIR/cli"

        if [[ -d "$cli_dir/.git" ]]; then
            if ! check_cli_update; then
                log_info "CLI update available"
                if confirm "Update CLI tool?"; then
                    git -C "$cli_dir" pull --quiet
                    log_success "CLI updated"
                fi
            else
                log_success "CLI is up to date"
            fi
        else
            log_dim "CLI not installed via git (skipping auto-update)"
        fi
    fi

    # ── Node update ───────────────────────────────────────────────────
    if [[ "$update_node" == "true" ]]; then
        log_step "Checking for node updates..."

        local current_version="$LOGOS_NODE_VERSION"
        fetch_latest_versions || die "Failed to fetch release information"

        if [[ "$LOGOS_NODE_VERSION" == "$current_version" ]]; then
            log_success "Node is already at the latest version (${current_version})"
            return 0
        fi

        echo ""
        print_separator
        log_info "Update available:"
        log_info "  Current: ${BOLD}${current_version}${RESET}"
        log_info "  Latest:  ${BOLD}${LOGOS_NODE_VERSION}${RESET}"
        print_separator
        echo ""

        if ! confirm "Update to ${LOGOS_NODE_VERSION}?"; then
            log_info "Update cancelled"
            return 0
        fi

        # Stop running node
        local was_running=false
        if docker_is_running; then
            was_running=true
            log_step "Stopping current node..."
            docker_down
            log_success "Node stopped"
        fi

        # Save new versions
        save_setting "LOGOS_NODE_VERSION" "$LOGOS_NODE_VERSION"
        save_setting "LOGOS_CIRCUITS_VERSION" "$LOGOS_CIRCUITS_VERSION"

        # Regenerate compose file and rebuild
        generate_compose_file
        docker_build || die "Failed to build updated Docker image"

        log_success "Node updated to ${LOGOS_NODE_VERSION}"

        # Restart if it was running
        if [[ "$was_running" == "true" ]]; then
            if confirm "Restart the node?"; then
                # Source start command
                source "$LOGOS_NODE_LIB/cmd_start.sh"
                cmd_start
            else
                log_info "Node stopped. Start manually with: logos-node start"
            fi
        fi
    fi
}
