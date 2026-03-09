# Logos Node

A CLI tool for installing, running, and managing a [Logos Blockchain](https://logos.co/) node. Handles Docker setup, configuration, updates, and monitoring — so you can go from zero to a running node in minutes.

> Built on the official [Logos Blockchain quickstart guide](https://github.com/logos-co/logos-docs/blob/main/docs/blockchain/quickstart-guide-for-the-logos-blockchain-node.md).

## Quick start

```sh
# Install the CLI
curl -sL https://raw.githubusercontent.com/shayanb/logos-node/main/install.sh | bash

# Set up and start your node
logos-node install
```

The installer checks prerequisites, fetches the latest release, builds a Docker image with the node binary and ZK circuits, generates your configuration and wallet keys, and optionally starts the node.

## Requirements

- **Docker** with Docker Compose v2
- **git**, **curl**
- **OS**: Linux (x86_64, aarch64), macOS (Intel, Apple Silicon), or WSL2 on Windows

The installer detects missing prerequisites and offers to install them automatically using your system's package manager (apt, dnf, pacman, brew, etc.). Docker can be installed via the official [get.docker.com](https://get.docker.com) script on Linux or Homebrew on macOS.

## Commands

| Command | Description |
|---------|-------------|
| `logos-node install` | Full setup — download, build, configure, generate keys |
| `logos-node start` | Start the node container |
| `logos-node stop` | Stop the node container |
| `logos-node status` | Show consensus state, peers, wallet balances |
| `logos-node logs` | Tail node logs (`-f`, `--tail=N`, `--since=1h`) |
| `logos-node update` | Update node and/or CLI (`update node`, `update cli`, `update all`, `-b BRANCH`) |
| `logos-node keys` | Show, backup, or restore wallet keys (`keys backup`, `keys restore`) |
| `logos-node faucet` | Show faucet URL and keys, open in browser |
| `logos-node inscribe` | Publish text inscriptions to the blockchain (interactive or piped) |
| `logos-node monitor` | Manage monitoring dashboard (`monitor start`, `monitor stop`, `monitor status`) |
| `logos-node help` | Show help |

Both `logos-node` and `logosnode` work as the command name.

## What it automates

`logos-node` automates the full [quickstart guide](https://github.com/logos-co/logos-docs/blob/main/docs/blockchain/quickstart-guide-for-the-logos-blockchain-node.md) flow:

| Quickstart step | What `logos-node` does |
|-----------------|----------------------|
| Download node binary | Docker image downloads it at build time |
| Download ZK circuits | Docker image downloads and installs them at build time |
| Install circuits to `~/.logos-blockchain-circuits` | Baked into the image at `/app/circuits`, set via `LOGOS_BLOCKCHAIN_CIRCUITS` env var |
| Run `logos-blockchain-node init` with bootstrap peers | `logos-node install` runs init inside the container, generates `user_config.yaml` with fresh keys |
| Run the node | `logos-node start` launches the container via Docker Compose |
| Find wallet keys | `logos-node keys` parses and displays them |
| Request faucet tokens | `logos-node faucet` shows keys + faucet URL, opens browser |
| Check consensus state (`/cryptarchia/info`) | `logos-node status` queries and displays it |
| Check peer connectivity (`/network/info`) | `logos-node status` queries and displays it |
| Check wallet balance | `logos-node status` shows balance for each key |
| Consensus participation | Automatic after UTXO ages ~3.5 hours |
| Inscribe text on-chain | `logos-node inscribe` runs the text sequencer inside the container |

## How it works

### Installation flow

1. **`install.sh`** — checks prerequisites (Docker, git, curl), offers to install anything missing, handles Docker group permissions, clones this repo to `~/.logos-node/cli/`, and creates `logos-node`/`logosnode` symlinks in your PATH.

2. **`logos-node install`** — fetches the latest release from the [Logos Blockchain releases](https://github.com/logos-blockchain/logos-blockchain/releases/), builds a Docker image containing the node binary and ZK circuit files, runs `logos-blockchain-node init` inside the container to generate `user_config.yaml` with fresh cryptographic keys and auto-detected public IP, then displays wallet keys with faucet instructions.

### Docker setup

The node runs inside a Docker container based on `debian:trixie-slim` (glibc 2.39+):

- **Node binary and ZK circuits** are downloaded from GitHub releases and baked into the image at build time — no manual download or extraction needed
- **`user_config.yaml`** is mounted read-only from `~/.logos-node/`
- **Data directory** (`~/.logos-node/data/`) is bind-mounted for RocksDB, logs, and other runtime state
- **Runs as your host user** (UID/GID) to avoid permission issues
- **Health check** polls the node's `/cryptarchia/info` API endpoint
- **Restart policy** `unless-stopped` keeps the node running across reboots
- **Ports**: `8080` (HTTP API), `3000/udp` (libp2p peer-to-peer)

### After install

1. **Get devnet tokens** — run `logos-node faucet` to see your wallet keys and the faucet URL. Visit the [devnet faucet](https://devnet.blockchain.logos.co/web/faucet/), paste one of your keys, and request funds.
2. **Wait for UTXO maturity** — tokens must age approximately 3.5 hours (two epochs) before your node can participate in the consensus lottery.
3. **Monitor** — use `logos-node status` to check consensus mode (Bootstrapping → Online), peer count, and wallet balances. Compare against the [devnet dashboard](https://devnet.blockchain.logos.co/web/).

### Inscribing text

Once your node is running and funded, you can publish text inscriptions to the blockchain using the built-in text sequencer:

```sh
# Interactive mode — type text and press Enter to inscribe each line
logos-node inscribe

# Pipe mode — inscribe text from stdin
echo "Hello World, from Lisbon Circle" | logos-node inscribe -

# From a file
logos-node inscribe - < message.txt
```

The sequencer creates a signing key (`sequencer.key`) and checkpoint file (`sequencer.checkpoint`) in the node data directory for crash recovery. These persist across restarts.

### Monitoring

Run a Grafana dashboard with Prometheus metrics for your node:

```sh
logos-node monitor start     # Start Grafana + Prometheus + metrics exporter
logos-node monitor status    # Show status and Grafana URL
logos-node monitor stop      # Stop the monitoring stack (node keeps running)
```

Grafana is available at `http://localhost:3001` (or your RPi's IP on port 3001). No login required to view — dashboards are pre-provisioned with panels for consensus state, peer count, wallet balance, and container resource usage.

The monitoring stack runs as separate Docker containers alongside the node. You can also opt in during `logos-node install`.

> **Upstream**: The Logos blockchain node is adding native Prometheus metrics ([#2012](https://github.com/logos-blockchain/logos-blockchain/pull/2012)) and Grafana dashboards ([#2227](https://github.com/logos-blockchain/logos-blockchain/pull/2227)). Once merged, our Prometheus config will automatically scrape the node's native `/metrics` endpoint alongside the custom exporter, unlocking deeper metrics for consensus, mempool, chainsync, and more.

## Configuration

All configuration lives in `~/.logos-node/` (override with `LOGOS_NODE_DIR` env var):

```
~/.logos-node/
├── settings.env          # User overrides (versions, image name)
├── user_config.yaml      # Node config with wallet keys (generated by install)
├── data/                 # Node runtime data (RocksDB, logs)
│   └── db/               # RocksDB blockchain state
└── cli/                  # Cloned CLI repository
```

### Network config (`network.yml`)

Network-specific settings (bootstrap peers, ports, URLs) are defined in `network.yml` in the repository root. To switch networks (e.g., from devnet to a future testnet), swap this file:

```yaml
network: devnet

bootstrap_peers:
  - /ip4/65.109.51.37/udp/3000/quic-v1/p2p/12D3KooW...
  - /ip4/65.109.51.37/udp/3001/quic-v1/p2p/12D3KooW...

api_port: 8080
udp_port: 3000
faucet_url: https://devnet.blockchain.logos.co/web/faucet/
dashboard_url: https://devnet.blockchain.logos.co/web/
```

### User settings (`settings.env`)

User-specific overrides go in `~/.logos-node/settings.env`. These take precedence over `network.yml`:

```sh
LOGOS_NODE_VERSION=latest       # Pin a specific version if needed
LOGOS_DOCKER_IMAGE=logos-node
LOGOS_CONTAINER_NAME=logos-node
```

Any value from `network.yml` can be overridden here (e.g., `LOGOS_API_PORT=9090`).

## Extending

Commands are modular bash scripts in `lib/`. To add a new command:

1. Create `lib/cmd_mycommand.sh`
2. Define a `cmd_mycommand()` function
3. Add a `# DESCRIPTION:` comment at the top

The command is immediately available as `logos-node mycommand`.

## Project structure

```
logos-node/
├── install.sh              # One-line installer (curl|bash)
├── logos-node               # CLI entry point
├── network.yml              # Network config (peers, ports, URLs)
├── docker/
│   └── Dockerfile           # Multi-arch node container (debian:trixie-slim)
├── monitoring/
│   ├── exporter/            # Python Prometheus exporter (polls node API + Docker stats)
│   ├── prometheus/          # Prometheus scrape config
│   └── grafana/             # Grafana provisioning + pre-built dashboard
└── lib/
    ├── common.sh            # Colors, logging, spinners, platform detection
    ├── config.sh            # Settings management (~/.logos-node/ + network.yml)
    ├── releases.sh          # GitHub release auto-detection
    ├── docker.sh            # Docker lifecycle helpers
    ├── monitoring.sh        # Monitoring stack helpers
    └── cmd_*.sh             # Individual command implementations
```

## Links

- [Logos Blockchain quickstart guide](https://github.com/logos-co/logos-docs/blob/main/docs/blockchain/quickstart-guide-for-the-logos-blockchain-node.md)
- [Logos Blockchain releases](https://github.com/logos-blockchain/logos-blockchain/releases/)
- [Devnet faucet](https://devnet.blockchain.logos.co/web/faucet/)
- [Devnet dashboard](https://devnet.blockchain.logos.co/web/)
- [Logos website](https://logos.co/)

## License

MIT
