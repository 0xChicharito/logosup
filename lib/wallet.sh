#!/usr/bin/env bash
# DESCRIPTION: Base-layer wallet HTTP client helpers
#
# Thin wrappers around the node's /wallet/* and /cryptarchia/* endpoints. The
# node does all cryptography internally — we just shape JSON requests and
# parse responses. No external deps beyond curl + sed.
#
# IMPORTANT — bash subshell gotcha: helpers that need to expose BOTH a body
# and an HTTP code use globals (`WALLET_HTTP_CODE`, `WALLET_BODY`) instead
# of returning the body via stdout. If a caller did `body=$(wallet_get_X)`,
# the assignment to WALLET_HTTP_CODE would happen inside the `$(...)` subshell
# and be lost in the parent. Pattern: call the helper bare, then read both
# globals.

# Default timeout for any wallet API call. Configurable so operators can
# tighten it on slow networks or stretch it for the occasional 408 we've
# seen on /wallet/{pk}/balance.
: "${LOGOS_API_TIMEOUT:=10}"

# Initialize globals so referencing them under `set -u` before the first
# call doesn't crash.
WALLET_HTTP_CODE=""
WALLET_BODY=""

wallet_api_url() {
    echo "http://localhost:${LOGOS_API_PORT}"
}

# Fetch /wallet/{pk}/balance. Sets WALLET_HTTP_CODE + WALLET_BODY.
wallet_get_balance() {
    local pk="$1"
    local resp
    resp="$(curl -s -m "$LOGOS_API_TIMEOUT" -w '\n%{http_code}' \
        "$(wallet_api_url)/wallet/${pk}/balance" 2>/dev/null)" || true
    WALLET_HTTP_CODE="$(echo "$resp" | tail -1)"
    WALLET_BODY="$(echo "$resp" | sed '$d')"
}

# Fetch /cryptarchia/info and parse the tip HeaderId (hex). Echoes the tip,
# or empty on failure. Doesn't use the WALLET_* globals — caller checks empty.
wallet_get_tip() {
    local body
    body="$(curl -sf -m "$LOGOS_API_TIMEOUT" \
        "$(wallet_api_url)/cryptarchia/info" 2>/dev/null)" || return 1
    echo "$body" | sed -E 's/.*"tip":"([^"]+)".*/\1/'
}

# POST /wallet/transactions/transfer-funds. Sets WALLET_HTTP_CODE + WALLET_BODY.
# Args: tip change_pk funding_pks_csv recipient_pk amount
wallet_post_transfer() {
    local tip="$1" change_pk="$2" funding_csv="$3" recipient="$4" amount="$5"

    # Build the funding_public_keys JSON array from the CSV input.
    local funding_json="["
    local first=true
    local k
    IFS=',' read -ra _funding_keys <<< "$funding_csv"
    for k in "${_funding_keys[@]}"; do
        [[ -z "$k" ]] && continue
        if $first; then first=false; else funding_json+=","; fi
        funding_json+="\"${k}\""
    done
    funding_json+="]"

    local body
    body=$(cat <<JSON
{"tip":"${tip}","change_public_key":"${change_pk}","funding_public_keys":${funding_json},"recipient_public_key":"${recipient}","amount":${amount}}
JSON
)

    local resp
    resp="$(curl -s -m "$LOGOS_API_TIMEOUT" -w '\n%{http_code}' \
        -X POST \
        -H "Content-Type: application/json" \
        --data "$body" \
        "$(wallet_api_url)/wallet/transactions/transfer-funds" 2>/dev/null)" || true
    WALLET_HTTP_CODE="$(echo "$resp" | tail -1)"
    WALLET_BODY="$(echo "$resp" | sed '$d')"
}

# GET /cryptarchia/transaction/{id}. Sets WALLET_HTTP_CODE + WALLET_BODY.
wallet_get_tx() {
    local hash="$1"
    local resp
    resp="$(curl -s -m "$LOGOS_API_TIMEOUT" -w '\n%{http_code}' \
        "$(wallet_api_url)/cryptarchia/transaction/${hash}" 2>/dev/null)" || true
    WALLET_HTTP_CODE="$(echo "$resp" | tail -1)"
    WALLET_BODY="$(echo "$resp" | sed '$d')"
}

# Pick the first known_key whose balance >= amount. Echoes the key on
# success, empty on failure. (Internally calls wallet_get_balance, which
# updates WALLET_* globals — that's fine inside this loop.)
wallet_pick_funding_key() {
    local amount="$1"
    local keys
    keys="$(get_wallet_keys 2>/dev/null)" || return 1
    [[ -z "$keys" ]] && return 1

    local key bal
    while IFS= read -r key; do
        [[ -z "$key" ]] && continue
        wallet_get_balance "$key"
        if [[ "$WALLET_HTTP_CODE" == "200" && -n "$WALLET_BODY" ]]; then
            bal="$(echo "$WALLET_BODY" | sed -E 's/.*"balance":([0-9]+).*/\1/')"
            if [[ "$bal" =~ ^[0-9]+$ ]] && (( bal >= amount )); then
                echo "$key"
                return 0
            fi
        fi
    done <<< "$keys"
    return 1
}

# Squash a multi-line response body to a single trimmed line, capped to
# `cap` chars. Used for inline error display. If `code` is the special
# curl-ish "000" (no response received), surface a connection-failed
# explanation instead of an empty string.
# Args: body [cap] [code]
wallet_squash_body() {
    local body="${1:-}"
    local cap="${2:-120}"
    local code="${3:-}"
    local out
    out="$(echo "$body" | tr '\n' ' ' | sed 's/  */ /g' | cut -c"1-${cap}")"
    if [[ -z "$out" ]]; then
        if [[ "$code" == "000" ]]; then
            echo "(no response — connection refused, timed out, or node API not reachable)"
        else
            echo "(empty response)"
        fi
    else
        echo "$out"
    fi
}
