#!/usr/bin/env bash
# DESCRIPTION: Docker and docker-compose helpers

DOCKER_COMPOSE=""

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

    if ! docker info &>/dev/null; then
        log_error "Docker daemon is not running."
        case "${LOGOS_OS:-}" in
            linux)  log_info "Start with: sudo systemctl start docker" ;;
            macos)  log_info "Start Docker Desktop from your Applications folder" ;;
        esac
        exit 1
    fi

    # Detect docker compose command
    if docker compose version &>/dev/null 2>&1; then
        DOCKER_COMPOSE="docker compose"
    elif command -v docker-compose &>/dev/null; then
        DOCKER_COMPOSE="docker-compose"
    else
        log_error "Docker Compose is required but not found."
        log_info "Install: https://docs.docker.com/compose/install/"
        exit 1
    fi

    export DOCKER_COMPOSE
}

# Generate docker-compose.yml from settings
generate_compose_file() {
    local compose_path
    compose_path="$(get_compose_path)"
    local dockerfile_dir
    dockerfile_dir="$(resolve_path "$(dirname "${BASH_SOURCE[0]}")/../docker")"

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
    ports:
      - "${LOGOS_API_PORT}:8080"
      - "${LOGOS_UDP_PORT}:3000/udp"
    volumes:
      - ${LOGOS_NODE_DIR}/user_config.yaml:/home/logos/user_config.yaml:ro
      - logos-data:/home/logos/data
    environment:
      - LOGOS_BLOCKCHAIN_CIRCUITS=/home/logos/.logos-blockchain-circuits
    healthcheck:
      test: ["CMD", "curl", "-sf", "http://localhost:8080/cryptarchia/info"]
      interval: 30s
      timeout: 5s
      retries: 3
      start_period: 120s

volumes:
  logos-data:
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

    # Run init in a temporary container with writable config mount
    docker run --rm \
        -v "${LOGOS_NODE_DIR}:/home/logos/config" \
        "${LOGOS_DOCKER_IMAGE}:${LOGOS_NODE_VERSION}" \
        init "${peer_args[@]}" \
        --output /home/logos/config/user_config.yaml 2>&1 | while IFS= read -r line; do
            echo -e "  ${DIM}${line}${RESET}"
        done

    # Fallback: if the node binary doesn't support --output, try without it
    if [[ ! -f "$config_path" ]]; then
        docker run --rm \
            -v "${LOGOS_NODE_DIR}:/home/logos" \
            -w /home/logos \
            "${LOGOS_DOCKER_IMAGE}:${LOGOS_NODE_VERSION}" \
            init "${peer_args[@]}" 2>&1 | while IFS= read -r line; do
                echo -e "  ${DIM}${line}${RESET}"
            done
    fi

    if [[ -f "$config_path" ]]; then
        chmod 600 "$config_path"
        log_success "Node configuration generated at $config_path"
        return 0
    else
        log_error "Failed to generate node configuration"
        log_info "You may need to generate it manually. See: logos-node --help"
        return 1
    fi
}

# Start the node
docker_up() {
    local compose_path
    compose_path="$(get_compose_path)"
    $DOCKER_COMPOSE -f "$compose_path" up -d
}

# Stop the node
docker_down() {
    local compose_path
    compose_path="$(get_compose_path)"
    $DOCKER_COMPOSE -f "$compose_path" down
}

# Check if the node container is running
docker_is_running() {
    docker ps --filter "name=${LOGOS_CONTAINER_NAME}" --format '{{.Names}}' 2>/dev/null | grep -q "^${LOGOS_CONTAINER_NAME}$"
}

# Wait for the node to become healthy
docker_health_wait() {
    local timeout="${1:-120}"
    local elapsed=0

    while [[ $elapsed -lt $timeout ]]; do
        local status
        status="$(docker inspect --format='{{.State.Health.Status}}' "$LOGOS_CONTAINER_NAME" 2>/dev/null)" || true

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
