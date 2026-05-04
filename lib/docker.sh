#!/usr/bin/env bash
# DESCRIPTION: Docker and docker-compose helpers

DOCKER_COMPOSE=""
DOCKER_CMD="docker"

# Check Docker is installed and running
check_docker() {
    if ! command -v docker &>/dev/null; then
        log_error "Docker is not installed."
        echo ""
        case "${LOGOS_OS:-}" in
            linux)
                log_info "Install Docker Engine: https://docs.docker.com/engine/install/"
                ;;
            macos)
                log_info "Install Docker Desktop: https://docs.docker.com/desktop/install/mac-install/"
                ;;
        esac
        if [[ "${LOGOS_WSL:-false}" == "true" ]]; then
            log_info "For WSL: enable Docker Desktop WSL 2 integration"
            log_info "https://docs.docker.com/desktop/wsl/"
        fi
        exit 1
    fi

    if ! docker info &>/dev/null 2>&1 && ! sudo docker info &>/dev/null 2>&1; then
        log_warn "Docker daemon is not running."
        case "${LOGOS_OS:-}" in
            linux)
                if confirm "Start Docker service now?"; then
                    log_info "Starting Docker..."
                    sudo systemctl start docker 2>/dev/null || sudo service docker start 2>/dev/null || true
                    sleep 3
                    local attempts=0
                    while [[ $attempts -lt 10 ]]; do
                        if docker info &>/dev/null 2>&1 || sudo docker info &>/dev/null 2>&1; then
                            log_success "Docker is running"
                            break
                        fi
                        sleep 2
                        attempts=$((attempts + 1))
                    done
                    if [[ $attempts -ge 10 ]]; then
                        die "Failed to start Docker. Please start it manually and try again."
                    fi
                else
                    die "Docker must be running. Start it and try again."
                fi
                ;;
            macos)
                log_info "Please open Docker Desktop from your Applications folder."
                die "Start Docker Desktop and try again."
                ;;
        esac
    fi

    # Determine if sudo is needed for docker daemon access
    if docker info &>/dev/null 2>&1; then
        DOCKER_CMD="docker"
    elif id -nG 2>/dev/null | grep -qw docker; then
        # User is in docker group but it's not active in this shell session.
        # Re-exec the entire logos-node command under the docker group.
        log_info "Activating docker group for this session..."
        exec sg docker -c "$(printf '%q ' "$LOGOS_NODE_ENTRY" "${LOGOS_NODE_ARGS[@]}")"
    elif sudo docker info &>/dev/null 2>&1; then
        DOCKER_CMD="sudo docker"
        log_warn "Docker requires sudo (user not in docker group)"
        log_dim "To fix permanently: ${BOLD}sudo usermod -aG docker \$USER${RESET}${DIM} then log out and back in"
    else
        die "Cannot connect to Docker daemon"
    fi

    # Detect docker compose command
    if $DOCKER_CMD compose version &>/dev/null 2>&1; then
        DOCKER_COMPOSE="$DOCKER_CMD compose"
    elif command -v docker-compose &>/dev/null; then
        if [[ "$DOCKER_CMD" == "sudo docker" ]]; then
            DOCKER_COMPOSE="sudo docker-compose"
        else
            DOCKER_COMPOSE="docker-compose"
        fi
    else
        log_error "Docker Compose is required but not found."
        log_info "Install: https://docs.docker.com/compose/install/"
        exit 1
    fi

    export DOCKER_COMPOSE DOCKER_CMD
}

# Generate docker-compose.yml from settings
generate_compose_file() {
    local compose_path
    compose_path="$(get_compose_path)"
    local dockerfile_dir
    dockerfile_dir="$(resolve_path "$(dirname "${BASH_SOURCE[0]}")/../docker")"

    local host_uid
    host_uid="$(id -u)"
    local host_gid
    host_gid="$(id -g)"

    cat > "$compose_path" << YAML
services:
  logos-node:
    build:
      context: ${dockerfile_dir}
      args:
        NODE_VERSION: "${LOGOS_NODE_VERSION}"
        CIRCUITS_VERSION: "${LOGOS_CIRCUITS_VERSION}"
    image: ${LOGOS_DOCKER_IMAGE}:${LOGOS_NODE_VERSION}
    container_name: ${LOGOS_CONTAINER_NAME}
    restart: unless-stopped
    user: "${host_uid}:${host_gid}"
    ports:
      - "${LOGOS_API_PORT}:8080"
      - "${LOGOS_UDP_PORT}:3000/udp"
    working_dir: /app/data
    volumes:
      - ${LOGOS_NODE_DIR}/user_config.yaml:/app/data/user_config.yaml:ro
      - ${LOGOS_NODE_DIR}/data:/app/data
    environment:
      - LOGOS_BLOCKCHAIN_CIRCUITS=/app/circuits
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:8080/cryptarchia/info"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 120s
    logging:
      driver: json-file
      options:
        max-size: "50m"
        max-file: "5"
    networks:
      - logosnode-net

networks:
  logosnode-net:
    name: logosnode-net
YAML

    log_success "Generated docker-compose.yml"
}

# Build the Docker image
docker_build() {
    local compose_path
    compose_path="$(get_compose_path)"

    log_step "Building Logos Node Docker image..."
    log_dim "This may take a few minutes on first run (downloading node binary + circuits)"

    $DOCKER_COMPOSE -f "$compose_path" build 2>&1 | while IFS= read -r line; do
        echo -e "  ${DIM}${line}${RESET}"
    done

    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        log_error "Docker build failed"
        return 1
    fi
    log_success "Docker image built successfully"
}

# Run the node init command inside the container to generate user_config.yaml
docker_init_config() {
    local compose_path
    compose_path="$(get_compose_path)"
    local config_path
    config_path="$(get_user_config_path)"

    # Build peer args
    local peer_args=()
    IFS=',' read -ra peers <<< "$LOGOS_BOOTSTRAP_PEERS"
    for peer in "${peers[@]}"; do
        peer_args+=("-p" "$peer")
    done

    log_step "Generating node configuration..."
    log_dim "Running logos-blockchain-node init with bootstrap peers"

    # Run init as the host user so it can write to the mounted volume
    local host_uid
    host_uid="$(id -u)"
    local host_gid
    host_gid="$(id -g)"

    # Ensure data directory exists
    mkdir -p "${LOGOS_NODE_DIR}/data"

    # Run init in a temporary container, writing config to the mounted volume
    $DOCKER_CMD run --rm \
        --user "${host_uid}:${host_gid}" \
        -v "${LOGOS_NODE_DIR}:/app" \
        -w /app \
        "${LOGOS_DOCKER_IMAGE}:${LOGOS_NODE_VERSION}" \
        init "${peer_args[@]}" 2>&1 | while IFS= read -r line; do
            echo -e "  ${DIM}${line}${RESET}"
        done

    # Fallback: try with explicit --output flag
    if [[ ! -f "$config_path" ]]; then
        $DOCKER_CMD run --rm \
            --user "${host_uid}:${host_gid}" \
            -v "${LOGOS_NODE_DIR}:/app/config" \
            -w /app \
            "${LOGOS_DOCKER_IMAGE}:${LOGOS_NODE_VERSION}" \
            init "${peer_args[@]}" \
            --output /app/config/user_config.yaml 2>&1 | while IFS= read -r line; do
                echo -e "  ${DIM}${line}${RESET}"
            done
    fi

    if [[ -f "$config_path" ]]; then
        chmod 600 "$config_path"

        # Patch HTTP backend to bind to 0.0.0.0 so Docker port mapping works
        # (default is 127.0.0.1, which blocks access from outside the container)
        if grep -q '127\.0\.0\.1' "$config_path"; then
            if [[ "$(uname -s)" == "Darwin" ]]; then
                sed -i '' 's/127\.0\.0\.1/0.0.0.0/g' "$config_path"
            else
                sed -i 's/127\.0\.0\.1/0.0.0.0/g' "$config_path"
            fi
            log_dim "Patched HTTP backend to bind 0.0.0.0 (accessible from local network)"
        fi

        # Enable OTLP metrics push so the monitoring stack can scrape native
        # node metrics (mempool, consensus, blend, KMS, storage, etc.) via the
        # OTel collector. Idempotent — only patches `metrics: None`.
        patch_user_config_for_otlp "$config_path"

        # Disable redundant disk-based tracing logs. By default the node's
        # tracing module writes ~10GB/hour of DEBUG output to data/<prefix>.<hour>
        # files in the data dir, ON TOP OF streaming the same content to stdout
        # (which Docker captures with caps). Net effect: 100GB+ disk in a day,
        # the chain DB shares the same partition, operators get squeezed out.
        # Stdout via `logos-node logs` is sufficient for diagnostics. Idempotent.
        patch_user_config_for_log_files "$config_path"

        log_success "Node configuration generated at $config_path"
        return 0
    else
        log_error "Failed to generate node configuration"
        log_info "You may need to generate it manually. See: logos-node --help"
        return 1
    fi
}

# Enable OTLP metrics push in user_config.yaml so logos-otel can collect
# native node metrics. Idempotent: only rewrites `metrics: None`. If metrics
# is already configured (e.g. operator customized it) we leave it alone.
# If the otel-collector container is absent the node tolerates the missing
# endpoint — push retries quietly in the background.
patch_user_config_for_otlp() {
    local config_path="$1"
    [[ -f "$config_path" ]] || return 0
    grep -qE '^[[:space:]]+metrics: None$' "$config_path" || return 0

    awk '
      /^[[:space:]]+metrics: None$/ {
        match($0, /^[[:space:]]+/)
        indent = substr($0, 1, RLENGTH)
        print indent "metrics: !Otlp"
        print indent "  endpoint: \"http://logos-otel:4317\""
        print indent "  host_identifier: \"logos-node\""
        next
      }
      { print }
    ' "$config_path" > "${config_path}.tmp" && mv "${config_path}.tmp" "$config_path"
    chmod 600 "$config_path"
    log_dim "Enabled OTLP metrics push to logos-otel (for monitoring stack)"
}

# Disable the tracing module's disk-based file output. The default config
# emits the SAME log lines to both stdout (which Docker captures, capped via
# our compose `logging:` block) AND to per-hour files in the data dir, which
# are NOT capped — DEBUG-level logs hit ~10GB/hour and fill any operator's
# disk in <a day. Stdout suffices; remove the file output.
#
# Replaces:
#     logger:
#       file:
#         directory: .
#         prefix: '...'
#       stdout: true
#       ...
# with:
#     logger:
#       file: null
#       stdout: true
#       ...
#
# Idempotent: only fires when the file: block has child fields.
patch_user_config_for_log_files() {
    local config_path="$1"
    [[ -f "$config_path" ]] || return 0
    # Detect the multi-line file: block. If file: is already null (or absent)
    # we don't need to patch.
    grep -qE '^[[:space:]]+file:[[:space:]]*$' "$config_path" || return 0

    awk '
      /^[[:space:]]+file:[[:space:]]*$/ {
        match($0, /^[[:space:]]+/)
        parent_indent = RLENGTH
        print substr($0, 1, parent_indent) "file: null"
        in_file_block = 1
        next
      }
      in_file_block {
        match($0, /^[[:space:]]+/)
        if (RLENGTH > parent_indent) {
          next   # skip indented children of file:
        }
        in_file_block = 0
      }
      { print }
    ' "$config_path" > "${config_path}.tmp" && mv "${config_path}.tmp" "$config_path"
    chmod 600 "$config_path"
    log_dim "Disabled disk-based tracing logs (redundant with stdout/Docker)"
}

# Remove the legacy `logos-net` network if it's orphaned (no containers attached).
# Pre-0.4.2 used `logos-net` which collided with any other Docker workload using
# that generic name. We renamed to `logosnode-net`; this cleans up the stale one
# on installs that have been migrated. Idempotent; never removes a network that
# still has containers attached.
docker_cleanup_legacy_network() {
    $DOCKER_CMD network inspect logos-net &>/dev/null || return 0
    local attached
    attached="$($DOCKER_CMD network inspect logos-net --format '{{range .Containers}}x{{end}}' 2>/dev/null)"
    [[ -n "$attached" ]] && return 0
    $DOCKER_CMD network rm logos-net &>/dev/null || true
}

# Start the node
docker_up() {
    local compose_path
    compose_path="$(get_compose_path)"
    $DOCKER_COMPOSE -f "$compose_path" up -d
    docker_cleanup_legacy_network
}

# Stop the node
docker_down() {
    local compose_path
    compose_path="$(get_compose_path)"
    $DOCKER_COMPOSE -f "$compose_path" down
}

# Check if the node container is running
docker_is_running() {
    $DOCKER_CMD ps --filter "name=${LOGOS_CONTAINER_NAME}" --format '{{.Names}}' 2>/dev/null | grep -q "^${LOGOS_CONTAINER_NAME}$"
}

# Wait for the node to become healthy
docker_health_wait() {
    local timeout="${1:-120}"
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        local status
        status="$($DOCKER_CMD inspect --format='{{.State.Health.Status}}' "$LOGOS_CONTAINER_NAME" 2>/dev/null)" || true

        case "$status" in
            healthy)
                return 0
                ;;
            unhealthy)
                return 1
                ;;
        esac

        echo -en "\r${CYAN}⠼${RESET} Waiting for node to start... (${elapsed}s)"
        sleep 2
        elapsed=$((elapsed + 2))
    done

    echo -en "\r\033[K"
    return 1
}

# Tail logs
docker_logs() {
    local compose_path
    compose_path="$(get_compose_path)"
    $DOCKER_COMPOSE -f "$compose_path" logs "$@"
}
