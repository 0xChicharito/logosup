#!/usr/bin/env bash
# DESCRIPTION: Monitoring stack helpers (Prometheus, Grafana, exporter)

get_monitoring_compose_path() {
    echo "$LOGOS_NODE_DIR/docker-compose.monitoring.yml"
}

generate_monitoring_compose_file() {
    local compose_path
    compose_path="$(get_monitoring_compose_path)"

    # Resolve the monitoring directory in the CLI repo
    local monitoring_dir
    if [[ -n "${LOGOS_NODE_LIB:-}" ]]; then
        monitoring_dir="$(dirname "$LOGOS_NODE_LIB")/monitoring"
    elif [[ -d "$LOGOS_NODE_DIR/cli/monitoring" ]]; then
        monitoring_dir="$LOGOS_NODE_DIR/cli/monitoring"
    else
        log_error "Cannot find monitoring directory"
        return 1
    fi

    # Create data directories
    mkdir -p "$LOGOS_NODE_DIR/monitoring/prometheus-data"
    mkdir -p "$LOGOS_NODE_DIR/monitoring/grafana-data"
    # Grafana runs as UID 472 inside the container
    chmod 777 "$LOGOS_NODE_DIR/monitoring/grafana-data"

    local host_uid host_gid
    host_uid="$(id -u)"
    host_gid="$(id -g)"

    log_step "Generating monitoring compose file..."

    cat > "$compose_path" << COMPOSE
services:
  logos-exporter:
    build:
      context: ${monitoring_dir}/exporter
    container_name: logos-exporter
    restart: unless-stopped
    ports:
      - "9100:9100"
    environment:
      - NODE_API_URL=http://${LOGOS_CONTAINER_NAME}:8080
      - CONTAINER_NAME=${LOGOS_CONTAINER_NAME}
      - POLL_INTERVAL=15
    pid: host
    volumes:
      - /var/run/docker.sock:/var/run/docker.sock:ro
      - /proc:/host/proc:ro
      - ${LOGOS_NODE_DIR}/user_config.yaml:/app/user_config.yaml:ro
    networks:
      - logos-net

  logos-prometheus:
    image: prom/prometheus:latest
    container_name: logos-prometheus
    restart: unless-stopped
    user: "${host_uid}:${host_gid}"
    volumes:
      - ${monitoring_dir}/prometheus/prometheus.yml:/etc/prometheus/prometheus.yml:ro
      - ${LOGOS_NODE_DIR}/monitoring/prometheus-data:/prometheus
    command:
      - '--config.file=/etc/prometheus/prometheus.yml'
      - '--storage.tsdb.retention.time=30d'
      - '--storage.tsdb.retention.size=1GB'
      - '--web.console.libraries=/etc/prometheus/console_libraries'
      - '--web.console.templates=/etc/prometheus/consoles'
    networks:
      - logos-net

  logos-grafana:
    image: grafana/grafana:latest
    container_name: logos-grafana
    restart: unless-stopped
    ports:
      - "${LOGOS_GRAFANA_PORT}:3000"
    environment:
      - GF_SECURITY_ADMIN_USER=admin
      - GF_SECURITY_ADMIN_PASSWORD=logos
      - GF_AUTH_ANONYMOUS_ENABLED=true
      - GF_AUTH_ANONYMOUS_ORG_ROLE=Viewer
    volumes:
      - ${monitoring_dir}/grafana/provisioning/datasources:/etc/grafana/provisioning/datasources:ro
      - ${monitoring_dir}/grafana/provisioning/dashboards:/etc/grafana/provisioning/dashboards:ro
      - ${monitoring_dir}/grafana/dashboards:/var/lib/grafana/dashboards:ro
      - ${LOGOS_NODE_DIR}/monitoring/grafana-data:/var/lib/grafana
    networks:
      - logos-net

networks:
  logos-net:
    external: true
COMPOSE

    log_success "Monitoring compose file generated at $compose_path"
}

monitoring_build() {
    local compose_path
    compose_path="$(get_monitoring_compose_path)"

    log_step "Building monitoring containers..."
    COMPOSE_IGNORE_ORPHANS=true $DOCKER_COMPOSE -f "$compose_path" build 2>&1 | while IFS= read -r line; do
        echo -e "  ${DIM}${line}${RESET}"
    done

    if [[ ${PIPESTATUS[0]} -ne 0 ]]; then
        log_error "Monitoring build failed"
        return 1
    fi
    log_success "Monitoring containers built"
}

monitoring_up() {
    local compose_path
    compose_path="$(get_monitoring_compose_path)"
    COMPOSE_IGNORE_ORPHANS=true $DOCKER_COMPOSE -f "$compose_path" up -d
}

monitoring_down() {
    local compose_path
    compose_path="$(get_monitoring_compose_path)"
    COMPOSE_IGNORE_ORPHANS=true $DOCKER_COMPOSE -f "$compose_path" down
}

monitoring_is_running() {
    $DOCKER_CMD ps --filter "name=logos-grafana" --format '{{.Names}}' 2>/dev/null | grep -q "^logos-grafana$"
}
