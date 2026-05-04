# logosup

A CLI tool for installing, running, and managing a [Logos Blockchain](https://logos.co/) node. Handles Docker setup, configuration, updates, and monitoring — so you can go from zero to a running node in minutes.

> Previously `logos-node`. The CLI command was renamed to `logosup` in v0.4.0; the old `logos-node` and `logosnode` commands still work as aliases.

> Built on the official [Logos Blockchain quickstart guide](https://github.com/logos-co/logos-docs/blob/main/docs/blockchain/quickstart-guide-for-the-logos-blockchain-node.md).

## Quick start

```sh
# Install the CLI
curl -sL https://raw.githubusercontent.com/logosnode/logosup/main/install.sh | bash

# Set up and start your node
logosup install
```

The installer checks prerequisites, fetches the latest release, builds a Docker image with the node binary and ZK circuits, generates your configuration and wallet keys, and optionally sets up security hardening, monitoring, and starts the node.

## Requirements

- **Docker** with Docker Compose v2
- **git**, **curl**
- **OS**: Linux (x86_64, aarch64), macOS (Intel, Apple Silicon), or WSL2 on Windows

The installer detects missing prerequisites and offers to install them automatically using your system's package manager (apt, dnf, pacman, brew, etc.). Docker can be installed via the official [get.docker.com](https://get.docker.com) script on Linux or Homebrew on macOS.

## Commands

| Command | Description |
|---------|-------------|
| `logosup install` | Full setup — download, build, configure, generate keys |
| `logosup start` | Start the node (+ monitoring if enabled) |
| `logosup stop` | Stop the node and monitoring |
| `logosup status` | Show consensus state, peers, wallet balances |
| `logosup logs` | Tail node logs (`-f`, `--tail=N`, `--since=1h`) |
| `logosup update` | Update node and/or CLI (`update node`, `update cli`, `update all`, `-b BRANCH`) |
| `logosup reset` | Wipe local data and regenerate config — use after a breaking release (`-y` for non-interactive) |
| `logosup keys` | Show, backup, or restore wallet keys (`keys backup`, `keys restore`) |
| `logosup wallet` | Send transfers, check balance, look up transactions (`wallet balance`, `wallet transfer`, `wallet tx`) |
| `logosup faucet` | Show faucet URL and keys, open in browser |
| `logosup inscribe` | Publish text inscriptions to the blockchain (interactive or piped) |
| `logosup monitor` | Manage monitoring dashboard (`monitor start`, `monitor stop`, `monitor status`, `monitor auth on/off`) |
| `logosup security` | Scan and harden server security (firewall, SSH, auto-updates, fail2ban) |
| `logosup version` | Show CLI and node versions |
| `logosup help` | Show help |

The primary command is `logosup`. Aliases `logos-node` and `logosnode` are kept for backwards compatibility.

## What it automates

`logosup` automates the full [quickstart guide](https://github.com/logos-co/logos-docs/blob/main/docs/blockchain/quickstart-guide-for-the-logos-blockchain-node.md) flow:

| Quickstart step | What `logosup` does |
|-----------------|----------------------|
| Download node binary | Docker image downloads it at build time |
| Download ZK circuits | Docker image downloads and installs them at build time |
| Install circuits to `~/.logos-blockchain-circuits` | Baked into the image at `/app/circuits`, set via `LOGOS_BLOCKCHAIN_CIRCUITS` env var |
| Run `logos-blockchain-node init` with bootstrap peers | `logosup install` runs init inside the container, generates `user_config.yaml` with fresh keys |
| Run the node | `logosup start` launches the container via Docker Compose |
| Find wallet keys | `logosup keys` parses and displays them |
| Request faucet tokens | `logosup faucet` shows keys + faucet URL, opens browser |
| Check consensus state (`/cryptarchia/info`) | `logosup status` queries and displays it |
| Check peer connectivity (`/network/info`) | `logosup status` queries and displays it |
| Check wallet balance | `logosup status` shows balance for each key |
| Consensus participation | Automatic after UTXO ages ~3.5 hours |
| Inscribe text on-chain | `logosup inscribe` runs the text sequencer inside the container |

## Breaking-change migrations

Some Logos Blockchain releases reset the genesis block or otherwise make existing local chain state incompatible. When that happens, you must wipe `~/.logos-node/data/` and regenerate `user_config.yaml`.

The CLI handles this for you:

- **Auto-detected during update** — `logosup update` checks the target version against a list of known breaking releases (maintained in `lib/releases.sh` as `LOGOS_BREAKING_VERSIONS`). If detected, it prompts for a one-step migration instead of the standard update.
- **Manual** — run `logosup reset` (or `logosup reset -y` for non-interactive) at any time to wipe local data and regenerate config against the currently-installed node version.

What the migration does:

1. Stops the node and monitoring stack
2. Backs up `~/.logos-node/user_config.yaml` to `user_config.yaml.pre-migration-<timestamp>`
3. Deletes `~/.logos-node/data/` (chain DB + logs)
4. Rebuilds the Docker image
5. Regenerates `user_config.yaml` with fresh wallet keys
6. Restarts the node (and monitoring, if it was running)

After migration you must re-claim faucet funds — the new chain starts from zero, so previous balances do not carry over. The pre-migration backup is preserved if you want to recover the old keys; see [Discord guidance](https://github.com/logos-blockchain/logos-blockchain/releases/tag/0.1.2) on which sections are portable.

## How it works

### Installation flow

1. **`install.sh`** — checks prerequisites (Docker, git, curl), offers to install anything missing, handles Docker group permissions, clones this repo to `~/.logos-node/cli/`, and creates `logosup`/`logosnode` symlinks in your PATH.

2. **`logosup install`** — fetches the latest release from the [Logos Blockchain releases](https://github.com/logos-blockchain/logos-blockchain/releases/), builds a Docker image containing the node binary and ZK circuit files, runs `logos-blockchain-node init` inside the container to generate `user_config.yaml` with fresh cryptographic keys and auto-detected public IP, displays wallet keys with faucet instructions, then optionally runs security hardening (firewall, SSH, auto-updates, fail2ban), monitoring setup, and starts the node.

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

1. **Get testnet tokens** — run `logosup faucet` to see your wallet keys and the faucet URL. Visit the [testnet faucet](https://testnet.blockchain.logos.co/web/faucet/), paste one of your keys, and request funds.
2. **Wait for UTXO maturity** — tokens must age approximately 3.5 hours (two epochs) before your node can participate in the consensus lottery.
3. **Monitor** — use `logosup status` to check consensus mode (Bootstrapping → Online), peer count, and wallet balances. Compare against the [testnet dashboard](https://testnet.blockchain.logos.co/web/).

### Wallet (transfers, balance, tx lookup)

Once your node is funded, the `wallet` command sends transfers and inspects state via the node's built-in wallet API. All cryptography (signing, proof generation) happens inside the node — the CLI is a thin HTTP client, no extra dependencies.

```sh
# Show balance + note count for every known_key, with total
logosup wallet balance

# Per-note breakdown for one key
logosup wallet balance 793055d1...

# Send 100 to a recipient (auto-picks a funding key with sufficient balance)
logosup wallet transfer 8a3b7f...c2d1 100

# Explicit funding/change keys, skip the confirmation prompt
logosup wallet send 8a3b7f...c2d1 100 --from 793055d1... --change 62156fa0... --yes

# Look up a transaction by hash (0x prefix optional)
logosup wallet tx 4d8e2a...
```

This is the **base-layer wallet** — the keys in `wallet.known_keys` of `user_config.yaml`, queried against `/wallet/{pk}/balance` and `/wallet/transactions/transfer-funds` on the node. The Logos Execution Zone (LEZ) wallet is a separate layer-2 wallet with its own account model, faucet, and binary — tracked separately ([#9](https://github.com/logosnode/logosup/issues/9)).

A note on errors: if the wallet endpoint times out (HTTP 408), the CLI surfaces the API's response inline so you can see why. Retry the same command — don't auto-script retries since each transfer attempt is its own HTTP submission.

### Inscribing text

Once your node is running and funded, you can publish text inscriptions to the blockchain using the built-in text sequencer:

```sh
# Interactive mode — type text and press Enter to inscribe each line
logosup inscribe

# Pipe mode — inscribe text from stdin
echo "Hello World, from Lisbon Circle" | logosup inscribe -

# From a file
logosup inscribe - < message.txt
```

The sequencer creates a signing key (`sequencer.key`) and checkpoint file (`sequencer.checkpoint`) in the node data directory for crash recovery. These persist across restarts.

### Monitoring

Run a Grafana dashboard with Prometheus metrics for your node:

```sh
logosup monitor start     # Start Grafana + Prometheus + metrics exporter
logosup monitor status    # Show status and Grafana URL
logosup monitor stop      # Stop the monitoring stack (node keeps running)
```

Grafana is available at `https://localhost:3001` (or your server's IP on port 3001). A self-signed SSL certificate is generated automatically on first run (valid for 10 years) and stored at:

```
~/.logos-node/monitoring/certs/
├── grafana.crt    # Self-signed certificate
└── grafana.key    # Private key
```

Your browser will show a security warning on the first visit — this is expected, just accept it to proceed. To regenerate the certificate, delete the files above and restart monitoring.

Two dashboards are provisioned:

- **Logos Node** (Overview) — at-a-glance status: consensus mode, slot/height, peers, container health, wallet balances.
- **Logos Node — Deep Dive** — native node metrics organized by service: consensus (block apply latency, proposals, fork count, finalized height), mempool (pending/added/removed), chainsync (request latency, downloads), orphans, blend (peers, message rates), KMS (sign requests/successes/failures), SDP (declarations, withdrawals), HTTP API and storage latency.

Use the "Deep Dive" link in the top-right of the Overview dashboard to switch between them. No login required by default — enable with `logosup monitor auth on`.

#### Architecture

The monitoring stack runs as separate Docker containers alongside the node:

```
logosup ──OTLP/4317──▶ logos-otel ──:8889──▶ logos-prometheus ──▶ logos-grafana
                                                       ▲
logos-exporter (Python: container/host stats, wallet balances) ─────┘
```

- **logos-otel** (OpenTelemetry Collector) receives native metrics the node pushes via OTLP and re-exposes them in Prometheus format.
- **logos-exporter** (Python) covers what the node doesn't emit natively: container CPU/memory/network, host stats, wallet balances.
- **logos-prometheus** scrapes both, **logos-grafana** visualizes.

Native OTLP push is enabled automatically in `user_config.yaml` (`tracing.metrics: !Otlp`) by `logosup install` / `logosup reset`. If you've customized that field, your value is preserved.

#### Troubleshooting: memory shows 0 B on Raspberry Pi

If the System & Containers dashboard shows **Memory: 0 B** and `docker stats` reports `0B / 0B` for MEM USAGE, the kernel doesn't have memory cgroups enabled. Pi OS doesn't enable them by default.

Fix on the Pi:

```sh
sudo nano /boot/firmware/cmdline.txt    # or /boot/cmdline.txt on older Pi OS
# Append (on the same single line):  cgroup_enable=memory cgroup_memory=1
sudo reboot
```

After reboot, `docker stats` should show real memory usage and the dashboard panels populate. Affects only memory; CPU and network metrics work without this flag.

### Security hardening

Harden your server with one command:

```sh
logosup security          # Scan and report findings
logosup security apply    # Apply fixes interactively (confirms each step)
```

Checks and fixes:

| Check | What it does |
|-------|-------------|
| **Firewall** | Install and enable UFW/firewalld with SSH + Node P2P ports. Optionally allow API and Grafana. |
| **SSH hardening** | Disable root login, offer key-only auth (only when SSH keys exist — won't lock you out) |
| **Auto security updates** | Enable unattended-upgrades (Debian/Ubuntu) or dnf-automatic (RHEL/Fedora) |
| **fail2ban** | Install with sshd jail — blocks IPs after 5 failed attempts for 1 hour |
| **File permissions** | Ensure node directory is restricted (700) |

Supports Debian/Ubuntu/Raspbian, Fedora/RHEL/CentOS/Rocky, and Arch Linux. Also offered during `logosup install`.

## Configuration

All configuration lives in `~/.logos-node/` (override with `LOGOS_NODE_DIR` env var):

```
~/.logos-node/
├── settings.env          # User overrides (versions, image name)
├── user_config.yaml      # Node config with wallet keys (generated by install)
├── data/                 # Node runtime data (RocksDB, logs)
│   └── db/               # RocksDB blockchain state
├── monitoring/
│   ├── certs/            # Self-signed SSL cert for Grafana (auto-generated)
│   ├── grafana-data/     # Grafana persistent data
│   └── prometheus-data/  # Prometheus time-series data
└── cli/                  # Cloned CLI repository
```

### Network config (`network.yml`)

Network-specific settings (bootstrap peers, ports, URLs) are defined in `network.yml` in the repository root. To switch networks (e.g., from testnet to mainnet), swap this file:

```yaml
network: testnet

bootstrap_peers:
  - /ip4/65.109.51.37/udp/3000/quic-v1/p2p/12D3KooW...
  - /ip4/65.109.51.37/udp/3001/quic-v1/p2p/12D3KooW...

api_port: 8080
udp_port: 3000
faucet_url: https://testnet.blockchain.logos.co/web/faucet/
dashboard_url: https://testnet.blockchain.logos.co/web/
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

The command is immediately available as `logosup mycommand`.

## Project structure

```
logosup/
├── install.sh              # One-line installer (curl|bash)
├── logosup                 # CLI entry point
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
- [Testnet faucet](https://testnet.blockchain.logos.co/web/faucet/)
- [Testnet dashboard](https://testnet.blockchain.logos.co/web/)
- [Logos website](https://logos.co/)

## License

MIT
