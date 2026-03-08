#!/usr/bin/env bash
# DESCRIPTION: Show wallet keys from node configuration

cmd_keys() {
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
}
