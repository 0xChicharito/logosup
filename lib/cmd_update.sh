#!/usr/bin/env bash
# DESCRIPTION: Update the Logos Node and/or CLI tool

cmd_update() {
    detect_platform
    check_docker
    load_config

    local update_cli=false
    local update_node=false
    local branch=""

    # Parse arguments
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -b|--branch)
                branch="${2:-}"
                [[ -z "$branch" ]] && die "Missing branch name after $1"
                shift 2
                ;;
            cli)  update_cli=true; shift ;;
            node) update_node=true; shift ;;
            all)  update_cli=true; update_node=true; shift ;;
            -h|--help|help)
                log_info "Usage: logos-node update [cli|node|all] [-b BRANCH]"
                log_info ""
                log_info "Options:"
                log_info "  -b, --branch BRANCH   Switch CLI to a specific git branch"
                return 0
                ;;
            *)
                log_error "Unknown option: $1"
                log_info "Usage: logos-node update [cli|node|all] [-b BRANCH]"
                return 1
                ;;
        esac
    done

    # Default to updating everything
    if [[ "$update_cli" == "false" && "$update_node" == "false" ]]; then
        update_cli=true
        update_node=true
    fi

    print_banner

    # ── CLI update ────────────────────────────────────────────────────
    if [[ "$update_cli" == "true" ]]; then
        log_step "Checking for CLI updates..."

        local cli_dir="$LOGOS_NODE_DIR/cli"

        if [[ -d "$cli_dir/.git" ]]; then
            # Switch branch if requested
            if [[ -n "$branch" ]]; then
                log_info "Switching to branch: ${BOLD}${branch}${RESET}"
                git -C "$cli_dir" fetch --all --quiet 2>/dev/null
                if git -C "$cli_dir" checkout "$branch" --quiet 2>/dev/null; then
                    git -C "$cli_dir" pull --quiet 2>/dev/null || true
                    log_success "CLI switched to branch ${BOLD}${branch}${RESET}"
                    if docker_is_running; then
                        log_info "Restart the node to apply changes: ${BOLD}logos-node stop && logos-node start${RESET}"
                    fi
                else
                    die "Branch '${branch}' not found"
                fi
            elif ! check_cli_update; then
                log_info "CLI update available"
                # Show what changed since current HEAD
                echo ""
                git -C "$cli_dir" log --oneline HEAD..@{u} 2>/dev/null | while IFS= read -r line; do
                    echo -e "  ${GREEN}+${RESET} $line"
                done
                git -C "$cli_dir" diff --stat HEAD..@{u} 2>/dev/null | while IFS= read -r line; do
                    echo -e "  ${DIM}$line${RESET}"
                done
                echo ""
                if confirm "Update CLI tool?"; then
                    git -C "$cli_dir" pull --quiet
                    log_success "CLI updated"
                    if docker_is_running; then
                        log_info "Restart the node to apply changes: ${BOLD}logos-node stop && logos-node start${RESET}"
                    fi
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
