#!/usr/bin/env bash
# DESCRIPTION: Show, backup, and restore wallet keys

cmd_keys() {
    local subcmd="${1:-show}"
    shift 2>/dev/null || true

    case "$subcmd" in
        show|"")    _keys_show ;;
        backup)     _keys_backup "$@" ;;
        restore)    _keys_restore "$@" ;;
        -h|--help|help) _keys_help ;;
        *)
            # If it doesn't match a subcommand, treat as "show" (backwards compat)
            _keys_show
            ;;
    esac
}

_keys_help() {
    echo ""
    log_step "Wallet key management"
    echo ""
    log_info "${BOLD}Usage:${RESET}"
    log_info "  logos-node keys                       Show public keys"
    log_info "  logos-node keys backup [FILE]          Export keys to a file"
    log_info "  logos-node keys restore <FILE>         Import keys into current config"
    echo ""
    log_info "${BOLD}Backup file contains:${RESET}"
    log_info "  Public keys and their corresponding private keys."
    log_info "  Keep this file safe — anyone with it can access your wallet."
    echo ""
}

_keys_show() {
    local config_path
    config_path="$(get_user_config_path)"

    if [[ ! -f "$config_path" ]]; then
        die "Node configuration not found at $config_path\nRun 'logos-node install' first."
    fi

    log_step "Wallet keys"

    local keys
    keys="$(get_wallet_keys)"

    if [[ -z "$keys" ]]; then
        log_warn "No keys found in $config_path"
        return 1
    fi

    echo ""
    local i=1
    while IFS= read -r key; do
        log_info "  Key ${i}: ${BOLD}${key}${RESET}"
        i=$((i + 1))
    done <<< "$keys"

    echo ""
    log_info "Use these keys with the faucet to receive devnet tokens."
    log_info "Faucet: ${BOLD}${LOGOS_FAUCET_URL}${RESET}"
    echo ""
    log_dim "Backup your keys: ${BOLD}logos-node keys backup${RESET}"
    echo ""
}

_keys_backup() {
    local config_path
    config_path="$(get_user_config_path)"

    if [[ ! -f "$config_path" ]]; then
        die "Node configuration not found at $config_path\nRun 'logos-node install' first."
    fi

    local backup_file="${1:-logos-node-keys.backup}"

    # Extract the full keys block
    local keys_block
    keys_block="$(get_wallet_keys_full)"

    if [[ -z "$keys_block" ]]; then
        die "No keys found in configuration"
    fi

    if [[ -f "$backup_file" ]]; then
        log_warn "File already exists: $backup_file"
        if ! confirm "Overwrite?"; then
            log_info "Backup cancelled"
            return 0
        fi
    fi

    # Write backup with header
    cat > "$backup_file" << BACKUP
# Logos Node wallet keys backup
# Created: $(date -u '+%Y-%m-%d %H:%M:%S UTC')
# WARNING: This file contains private keys. Keep it safe!
#
# Restore with: logos-node keys restore $backup_file
#
${keys_block}
BACKUP
    chmod 600 "$backup_file"

    echo ""
    log_success "Keys backed up to ${BOLD}${backup_file}${RESET}"
    echo ""

    # Show what was backed up
    local count=0
    while IFS= read -r key; do
        count=$((count + 1))
        log_info "  Key ${count}: ${DIM}${key:0:16}...${RESET}"
    done <<< "$(get_wallet_keys)"

    echo ""
    log_warn "This file contains your private keys. Store it securely!"
    echo ""
}

_keys_restore() {
    local backup_file="${1:-}"

    if [[ -z "$backup_file" ]]; then
        log_error "Usage: logos-node keys restore <FILE>"
        log_info "Example: logos-node keys restore logos-node-keys.backup"
        return 1
    fi

    if [[ ! -f "$backup_file" ]]; then
        die "Backup file not found: $backup_file"
    fi

    local config_path
    config_path="$(get_user_config_path)"

    if [[ ! -f "$config_path" ]]; then
        die "Node configuration not found at $config_path\nRun 'logos-node install' first, then restore keys."
    fi

    # Parse keys from backup file (skip comments, find known_keys block)
    local new_keys
    new_keys="$(awk '/^[[:space:]]*known_keys:/{found=1; print; next} found && /^[[:space:]]+[a-f0-9]+:/{print; next} found{exit}' "$backup_file")"

    if [[ -z "$new_keys" ]]; then
        die "No valid keys found in backup file"
    fi

    # Count keys being restored
    local count
    count="$(echo "$new_keys" | grep -c '[a-f0-9]\{64\}' || true)"

    echo ""
    log_step "Restoring ${count} key(s) from backup"
    echo ""

    # Show current vs new
    local current_keys
    current_keys="$(get_wallet_keys 2>/dev/null)"
    if [[ -n "$current_keys" ]]; then
        log_info "Current keys in config:"
        while IFS= read -r key; do
            log_info "  ${DIM}${key:0:16}...${RESET}"
        done <<< "$current_keys"
        echo ""
    fi

    log_info "Keys from backup:"
    echo "$new_keys" | awk '/[a-f0-9]{64}:/{gsub(/^[[:space:]]+/, ""); split($0, a, ":"); printf "  %s...\n", substr(a[1], 1, 16)}'
    echo ""

    log_warn "This will replace the keys in your node configuration."
    if ! confirm "Proceed with restore?"; then
        log_info "Restore cancelled"
        return 0
    fi

    # Replace known_keys block in config
    # Strategy: use awk to replace the known_keys section
    local tmp_config="${config_path}.tmp"

    awk -v new_keys="$new_keys" '
    /^[[:space:]]*known_keys:/ {
        # Print the new keys block
        print new_keys
        # Skip old known_keys entries
        found=1
        next
    }
    found && /^[[:space:]]+[a-f0-9]+:/ { next }
    found { found=0 }
    { print }
    ' "$config_path" > "$tmp_config"

    # Verify the temp file looks sane
    if [[ ! -s "$tmp_config" ]]; then
        rm -f "$tmp_config"
        die "Failed to generate updated config. Original config is unchanged."
    fi

    # Swap files
    cp "$config_path" "${config_path}.pre-restore"
    mv "$tmp_config" "$config_path"
    chmod 600 "$config_path"

    echo ""
    log_success "Keys restored successfully"
    log_info "Previous config saved to ${DIM}${config_path}.pre-restore${RESET}"
    echo ""

    if docker_is_running 2>/dev/null; then
        log_info "Restart the node to use the restored keys:"
        log_info "  ${BOLD}logos-node stop && logos-node start${RESET}"
    fi
    echo ""
}
