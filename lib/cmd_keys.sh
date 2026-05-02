#!/usr/bin/env bash
# DESCRIPTION: Show, backup, and restore wallet keys

cmd_keys() {
    local subcmd="${1:-show}"
    shift 2>/dev/null || true

    case "$subcmd" in
        show|"")           _keys_show ;;
        backup|export)     _keys_backup "$@" ;;
        restore|import)    _keys_restore "$@" ;;
        -h|--help|help)    _keys_help ;;
        *)
            log_error "Unknown subcommand: ${subcmd}"
            _keys_help
            return 1
            ;;
    esac
}

_keys_help() {
    echo ""
    log_step "Wallet key management"
    echo ""
    log_info "${BOLD}Usage:${RESET}"
    log_info "  logos-node keys                          Show public keys"
    log_info "  logos-node keys backup|export [FILE]     Export full wallet config to a file"
    log_info "  logos-node keys restore|import <FILE>    Restore wallet config from a file"
    echo ""
    log_info "${BOLD}What's in a backup file:${RESET}"
    log_info "  A copy of ${BOLD}user_config.yaml${RESET} — all wallet identities (the KMS section"
    log_info "  holds the actual signing keys). Anyone with this file can spend your funds."
    log_info "  Keep it safe (offline backup, encrypted disk, etc)."
    echo ""
    log_info "${BOLD}Note:${RESET} restore overwrites the entire node config, not just keys."
    log_info "If you've customized network settings since the backup, those revert too."
    log_info "The previous config is saved to ${DIM}user_config.yaml.pre-restore-<timestamp>${RESET}."
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
    log_info "Use these keys with the faucet to receive testnet tokens."
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

    local backup_file="${1:-logos-node-keys.backup.yaml}"

    if [[ -f "$backup_file" ]]; then
        log_warn "File already exists: $backup_file"
        if ! confirm "Overwrite?"; then
            log_info "Backup cancelled"
            return 0
        fi
    fi

    # Save the entire user_config.yaml. The wallet's signing material lives in
    # the kms.backend.keys section (mapping the same KeyIds that show up in
    # wallet.known_keys to the actual !Zk / !Ed25519 secret bytes), plus
    # references in cryptarchia.leader.wallet.funding_pk, sdp.wallet.funding_pk,
    # blend.*.kms_id, etc. A partial backup of just wallet.known_keys can't be
    # restored to anything functional — restoring those public IDs against a
    # freshly-regenerated KMS section produces unsignable keys. So we save the
    # whole config and restore it whole.
    cp "$config_path" "$backup_file"
    chmod 600 "$backup_file"

    echo ""
    log_success "Wallet config backed up to ${BOLD}${backup_file}${RESET}"
    echo ""

    # Show the public keys in the backup
    local count=0
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        count=$((count + 1))
        log_info "  Key ${count}: ${DIM}${key:0:16}...${RESET}"
    done <<< "$(get_wallet_keys)"

    echo ""
    log_warn "This file contains your KMS private keys (full signing material)."
    log_warn "Store it securely — anyone with this file controls your wallet."
    log_dim "Restore with: ${BOLD}logos-node keys restore $backup_file${RESET}"
    echo ""
}

_keys_restore() {
    local backup_file="${1:-}"

    if [[ -z "$backup_file" ]]; then
        log_error "Missing file argument."
        log_info "Usage:   logos-node keys import <FILE>     (or: keys restore <FILE>)"
        log_info "Example: logos-node keys import logos-node-keys.backup.yaml"
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

    # Sanity-check the backup looks like a user_config.yaml. The full backup is
    # a copy of user_config.yaml — should have a top-level wallet: + kms: section.
    if ! grep -qE "^wallet:" "$backup_file" || ! grep -qE "^kms:" "$backup_file"; then
        log_error "Backup file doesn't look like a full Logos node config."
        log_info "It must contain top-level ${BOLD}wallet:${RESET} and ${BOLD}kms:${RESET} sections."
        log_dim "Backups created by older logos-node versions (only the known_keys block) cannot be restored — they don't include KMS signing material."
        return 1
    fi

    # Show what's about to change — known_keys and KMS key ids
    echo ""
    log_step "Restore wallet configuration from $backup_file"
    echo ""

    log_info "Backup contains keys:"
    awk '/^[[:space:]]*known_keys:/{found=1; next} found && /^[[:space:]]+[0-9a-f]{64}:/{print "  " substr($1, 1, 17) "..."; next} found{exit}' "$backup_file"
    echo ""

    local current_keys
    current_keys="$(get_wallet_keys 2>/dev/null)"
    if [[ -n "$current_keys" ]]; then
        log_info "Current config has keys:"
        while IFS= read -r key; do
            [[ -z "$key" ]] && continue
            log_info "  ${DIM}${key:0:16}...${RESET}"
        done <<< "$current_keys"
        echo ""
    fi

    log_warn "${BOLD}This will replace your ENTIRE node config${RESET} with the backup."
    log_warn "Includes wallet, kms, network, monitoring — not just wallet keys."
    log_dim "Previous config will be saved to ${BOLD}user_config.yaml.pre-restore-<timestamp>${RESET} for rollback."
    echo ""
    if ! confirm "Proceed with restore?" "n"; then
        log_info "Restore cancelled"
        return 0
    fi

    # Save current config with timestamp for unambiguous rollback
    local rollback="${config_path}.pre-restore-$(date +%Y%m%d-%H%M%S)"
    cp "$config_path" "$rollback"
    chmod 600 "$rollback"

    cp "$backup_file" "$config_path"
    chmod 600 "$config_path"

    echo ""
    log_success "Wallet configuration restored"
    log_info "Previous config saved to ${DIM}${rollback}${RESET}"
    echo ""

    if docker_is_running 2>/dev/null; then
        log_warn "Restart the node to use the restored keys:"
        log_info "  ${BOLD}logos-node stop && logos-node start${RESET}"
    fi
    echo ""
}
