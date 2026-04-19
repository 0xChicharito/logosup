#!/usr/bin/env bash
# DESCRIPTION: Open the faucet and display wallet keys

cmd_faucet() {
    local config_path
    config_path="$(get_user_config_path)"

    log_step "Logos Testnet Faucet"
    echo ""
    log_info "Faucet URL: ${BOLD}${LOGOS_FAUCET_URL}${RESET}"
    echo ""

    # Show keys if available
    if [[ -f "$config_path" ]]; then
        local keys
        keys="$(get_wallet_keys)"
        if [[ -n "$keys" ]]; then
            log_info "Your wallet keys (paste one into the faucet):"
            while IFS= read -r key; do
                echo -e "  ${BOLD}${key}${RESET}"
            done <<< "$keys"
            echo ""
        fi
    else
        log_warn "No node configuration found. Run 'logos-node install' first."
        echo ""
    fi

    log_info "Steps:"
    log_info "  1. Open the faucet URL above"
    log_info "  2. Paste one of your wallet keys into 'Destination Public Key (Hex)'"
    log_info "  3. Click 'Request Funds'"
    log_info "  4. Wait 1-2 minutes, then check balance with: ${BOLD}logos-node status${RESET}"
    echo ""
    log_info "Note: Your UTXO must age ~3.5 hours before you can participate in consensus."
    echo ""

    # Try to open in browser
    if confirm "Open faucet in browser?"; then
        case "${LOGOS_OS:-}" in
            macos)  open "$LOGOS_FAUCET_URL" 2>/dev/null ;;
            linux)
                if [[ "${LOGOS_WSL:-false}" == "true" ]]; then
                    cmd.exe /c start "$LOGOS_FAUCET_URL" 2>/dev/null || \
                        xdg-open "$LOGOS_FAUCET_URL" 2>/dev/null
                else
                    xdg-open "$LOGOS_FAUCET_URL" 2>/dev/null
                fi
                ;;
        esac || log_info "Could not open browser. Please visit the URL manually."
    fi
}
