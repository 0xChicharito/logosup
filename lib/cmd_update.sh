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

    local cli_updated=false
    local cli_changed_files=""

    # ── CLI update ────────────────────────────────────────────────────
    if [[ "$update_cli" == "true" ]]; then
        log_step "Checking for CLI updates..."

        local cli_dir="$LOGOS_NODE_DIR/cli"

        if [[ -d "$cli_dir/.git" ]]; then
            # Fix single-branch refspec from older installs (--depth 1 without --no-single-branch)
            local current_refspec
            current_refspec="$(git -C "$cli_dir" config remote.origin.fetch 2>/dev/null)" || true
            if [[ "$current_refspec" != "+refs/heads/*:refs/remotes/origin/*" ]]; then
                git -C "$cli_dir" config remote.origin.fetch '+refs/heads/*:refs/remotes/origin/*'
            fi

            local before_sha
            before_sha="$(git -C "$cli_dir" rev-parse HEAD 2>/dev/null)"

            if [[ -n "$branch" ]]; then
                # Branch switch
                log_info "Switching to branch: ${BOLD}${branch}${RESET}"
                git -C "$cli_dir" fetch --all --quiet 2>/dev/null
                if git -C "$cli_dir" checkout "$branch" --quiet 2>/dev/null; then
                    git -C "$cli_dir" pull 2>/dev/null || true
                    log_success "CLI switched to branch ${BOLD}${branch}${RESET}"
                    cli_updated=true
                else
                    die "Branch '${branch}' not found"
                fi
            elif ! check_cli_update; then
                log_info "CLI update available"
                echo ""
                if confirm "Update CLI tool?"; then
                    git -C "$cli_dir" pull
                    log_success "CLI updated"
                    cli_updated=true
                fi
            else
                log_success "CLI is up to date"
            fi

            # Track what changed
            if [[ "$cli_updated" == "true" ]]; then
                cli_changed_files="$(git -C "$cli_dir" diff --name-only "$before_sha" HEAD 2>/dev/null)" || true
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

        if [[ "$LOGOS_NODE_VERSION" != "$current_version" ]]; then
            echo ""
            print_separator
            log_info "Update available:"
            log_info "  Current: ${BOLD}${current_version}${RESET}"
            log_info "  Latest:  ${BOLD}${LOGOS_NODE_VERSION}${RESET}"
            print_separator
            echo ""

            if confirm "Update to ${LOGOS_NODE_VERSION}?"; then
                local was_running=false
                if docker_is_running; then
                    was_running=true
                    log_step "Stopping current node..."
                    docker_down
                    log_success "Node stopped"
                fi

                save_setting "LOGOS_NODE_VERSION" "$LOGOS_NODE_VERSION"
                save_setting "LOGOS_CIRCUITS_VERSION" "$LOGOS_CIRCUITS_VERSION"

                generate_compose_file
                docker_build || die "Failed to build updated Docker image"

                log_success "Node updated to ${LOGOS_NODE_VERSION}"

                if [[ "$was_running" == "true" ]]; then
                    if confirm "Restart the node?"; then
                        source "$LOGOS_NODE_LIB/cmd_start.sh"
                        cmd_start
                    else
                        log_info "Node stopped. Start manually with: logos-node start"
                    fi
                fi
            else
                log_info "Update cancelled"
            fi
        else
            log_success "Node is already at the latest version (${current_version})"
        fi
    fi

    # ── Post-update: check if monitoring needs a rebuild ─────────────
    if [[ "$cli_updated" == "true" ]]; then
        local monitoring_compose="$LOGOS_NODE_DIR/docker-compose.monitoring.yml"

        if [[ -f "$monitoring_compose" ]] && echo "$cli_changed_files" | grep -qE '^(monitoring/|lib/monitoring\.sh)'; then
            source "$LOGOS_NODE_LIB/monitoring.sh"

            echo ""
            log_info "Monitoring files were updated:"
            echo "$cli_changed_files" | grep -E '^(monitoring/|lib/monitoring\.sh)' | while IFS= read -r f; do
                echo -e "  ${DIM}$f${RESET}"
            done
            echo ""

            if confirm "Rebuild monitoring stack?"; then
                generate_monitoring_compose_file
                if monitoring_is_running; then
                    monitoring_build || log_warn "Monitoring build failed"
                    monitoring_up
                    log_success "Monitoring stack updated"
                else
                    log_success "Monitoring compose regenerated (start with: logos-node monitor start)"
                fi
            fi
        fi

        if docker_is_running; then
            log_info "Restart the node to apply changes: ${BOLD}logos-node stop && logos-node start${RESET}"
        fi
    fi
}
