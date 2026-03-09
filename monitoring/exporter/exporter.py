#!/usr/bin/env python3
"""Prometheus metrics exporter for Logos Blockchain Node.

Polls the node's JSON HTTP API and Docker stats, exposing metrics
in Prometheus format on port 9100.
"""

import os
import re
import time
import threading
import logging
import shutil

import requests
import docker
import yaml
from prometheus_client import start_http_server, Gauge, Counter, Info

logging.basicConfig(level=logging.INFO, format="%(asctime)s %(levelname)s %(message)s")
log = logging.getLogger("logos-exporter")

# ── Configuration ────────────────────────────────────────────────────
NODE_API_URL = os.environ.get("NODE_API_URL", "http://logos-node:8080")
CONTAINER_NAME = os.environ.get("CONTAINER_NAME", "logos-node")
POLL_INTERVAL = int(os.environ.get("POLL_INTERVAL", "15"))
CONFIG_PATH = os.environ.get("CONFIG_PATH", "/app/user_config.yaml")
EXPORTER_PORT = int(os.environ.get("EXPORTER_PORT", "9100"))

# ── Prometheus Metrics ───────────────────────────────────────────────

# Node availability
node_up = Gauge("logos_node_up", "Whether the node API is reachable (1=up, 0=down)")

# Consensus (/cryptarchia/info)
consensus_mode = Gauge("logos_node_consensus_mode", "Consensus mode (labeled)", ["mode"])
node_slot = Gauge("logos_node_slot", "Current consensus slot")
node_height = Gauge("logos_node_height", "Current blockchain height")

# Network (/network/info)
node_peers = Gauge("logos_node_peers", "Number of connected peers")
node_connections = Gauge("logos_node_connections", "Number of active connections")
node_pending_connections = Gauge("logos_node_pending_connections", "Number of pending connections")

# Wallet balance (/wallet/{key}/balance)
wallet_balance = Gauge("logos_node_wallet_balance", "Wallet balance", ["key"])

# Docker container stats
container_cpu = Gauge("logos_container_cpu_percent", "Container CPU usage percentage")
container_memory = Gauge("logos_container_memory_bytes", "Container memory usage in bytes")
container_memory_limit = Gauge("logos_container_memory_limit_bytes", "Container memory limit in bytes")
container_net_rx = Gauge("logos_container_network_rx_bytes", "Container network received bytes")
container_net_tx = Gauge("logos_container_network_tx_bytes", "Container network transmitted bytes")
container_running = Gauge("logos_container_running", "Whether the container is running (1=yes, 0=no)")

# Host system metrics
host_memory_total = Gauge("logos_host_memory_total_bytes", "Host total memory in bytes")
host_memory_used = Gauge("logos_host_memory_used_bytes", "Host used memory in bytes")
host_disk_usage = Gauge("logos_host_disk_usage_percent", "Host disk usage percentage")
host_load_1m = Gauge("logos_host_load_1m", "Host 1-minute load average")
host_load_5m = Gauge("logos_host_load_5m", "Host 5-minute load average")
host_load_15m = Gauge("logos_host_load_15m", "Host 15-minute load average")


def parse_wallet_keys(config_path):
    """Parse known_keys from user_config.yaml."""
    try:
        with open(config_path, "r") as f:
            config = yaml.safe_load(f)

        # Navigate to cl.backend.keys
        keys = (
            config.get("cl", {})
            .get("backend", {})
            .get("keys", {})
        )
        if keys:
            return list(keys.keys())
    except Exception:
        pass

    # Fallback: regex parse (same approach as the bash get_wallet_keys)
    try:
        with open(config_path, "r") as f:
            content = f.read()
        return re.findall(r"^\s+([a-f0-9]{64}):", content, re.MULTILINE)
    except Exception:
        return []


def poll_node_api():
    """Poll node JSON API endpoints and update Prometheus metrics."""
    try:
        resp = requests.get(f"{NODE_API_URL}/cryptarchia/info", timeout=5)
        resp.raise_for_status()
        data = resp.json()

        node_up.set(1)

        mode = data.get("mode", "Unknown")
        # Reset all mode labels, set the active one
        for m in ("Online", "Bootstrapping"):
            consensus_mode.labels(mode=m).set(1 if m == mode else 0)

        slot = data.get("slot", 0)
        height = data.get("height", 0)
        node_slot.set(slot)
        node_height.set(height)

        log.debug("Polled node: mode=%s slot=%s height=%s", mode, slot, height)

    except Exception as e:
        log.debug("Node API unreachable: %s", e)
        node_up.set(0)
        return  # Skip other endpoints if node is down

    # Network info
    try:
        resp = requests.get(f"{NODE_API_URL}/network/info", timeout=5)
        resp.raise_for_status()
        data = resp.json()

        node_peers.set(data.get("n_peers", 0))
        node_connections.set(data.get("n_connections", 0))
        node_pending_connections.set(data.get("n_pending_connections", 0))
    except Exception:
        pass

    # Wallet balances
    keys = parse_wallet_keys(CONFIG_PATH)
    for key in keys:
        try:
            resp = requests.get(f"{NODE_API_URL}/wallet/{key}/balance", timeout=5)
            resp.raise_for_status()
            data = resp.json()
            wallet_balance.labels(key=key[:16]).set(data.get("balance", 0))
        except Exception:
            pass


def calculate_cpu_percent(stats):
    """Calculate CPU percentage from Docker stats, matching `docker stats` output."""
    cpu = stats.get("cpu_stats", {})
    precpu = stats.get("precpu_stats", {})

    cpu_delta = cpu.get("cpu_usage", {}).get("total_usage", 0) - \
                precpu.get("cpu_usage", {}).get("total_usage", 0)
    system_delta = cpu.get("system_cpu_usage", 0) - \
                   precpu.get("system_cpu_usage", 0)

    if system_delta > 0 and cpu_delta > 0:
        num_cpus = len(cpu.get("cpu_usage", {}).get("percpu_usage", [])) or \
                   cpu.get("online_cpus", 1)
        return (cpu_delta / system_delta) * num_cpus * 100.0
    return 0.0


def poll_docker_stats():
    """Poll Docker stats API for the node container."""
    try:
        client = docker.DockerClient.from_env()
        container = client.containers.get(CONTAINER_NAME)

        if container.status != "running":
            container_running.set(0)
            return

        container_running.set(1)

        stats = container.stats(stream=False)

        # CPU
        container_cpu.set(calculate_cpu_percent(stats))

        # Memory
        mem = stats.get("memory_stats", {})
        container_memory.set(mem.get("usage", 0))
        container_memory_limit.set(mem.get("limit", 0))

        # Network I/O (sum all interfaces)
        networks = stats.get("networks", {})
        rx_total = sum(net.get("rx_bytes", 0) for net in networks.values())
        tx_total = sum(net.get("tx_bytes", 0) for net in networks.values())
        container_net_rx.set(rx_total)
        container_net_tx.set(tx_total)

    except docker.errors.NotFound:
        container_running.set(0)
    except Exception as e:
        log.warning("Docker stats error: %s", e)
        container_running.set(0)


def poll_host_metrics():
    """Poll host system metrics (memory, disk, load)."""
    try:
        # Memory from host's /proc/meminfo (mounted at /host/proc)
        meminfo_path = "/host/proc/meminfo" if os.path.exists("/host/proc/meminfo") else "/proc/meminfo"
        with open(meminfo_path, "r") as f:
            meminfo = {}
            for line in f:
                parts = line.split()
                if len(parts) >= 2:
                    meminfo[parts[0].rstrip(":")] = int(parts[1]) * 1024  # kB to bytes

        total = meminfo.get("MemTotal", 0)
        available = meminfo.get("MemAvailable", 0)
        host_memory_total.set(total)
        host_memory_used.set(total - available)
    except Exception as e:
        log.debug("Host memory error: %s", e)

    try:
        # Load average
        load1, load5, load15 = os.getloadavg()
        host_load_1m.set(load1)
        host_load_5m.set(load5)
        host_load_15m.set(load15)
    except Exception as e:
        log.debug("Host load error: %s", e)

    try:
        # Disk usage for the data directory
        usage = shutil.disk_usage("/")
        host_disk_usage.set((usage.used / usage.total) * 100.0)
    except Exception as e:
        log.debug("Host disk error: %s", e)


def poll_loop():
    """Main polling loop running in a background thread."""
    log.info("Poll loop started")
    first_run = True
    while True:
        try:
            poll_node_api()
            poll_docker_stats()
            poll_host_metrics()
            if first_run:
                log.info("First poll completed successfully")
                first_run = False
        except Exception as e:
            log.error("Poll error: %s", e)
        time.sleep(POLL_INTERVAL)


def main():
    log.info(
        "Starting Logos Node exporter on :%d (polling %s every %ds)",
        EXPORTER_PORT, NODE_API_URL, POLL_INTERVAL,
    )

    # Start Prometheus HTTP server
    start_http_server(EXPORTER_PORT)

    # Run polling in background thread
    t = threading.Thread(target=poll_loop, daemon=True)
    t.start()

    # Keep main thread alive
    try:
        while True:
            time.sleep(60)
    except KeyboardInterrupt:
        log.info("Shutting down")


if __name__ == "__main__":
    main()
