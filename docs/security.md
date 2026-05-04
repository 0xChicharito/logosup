# Security hardening

Harden your server with one command:

```sh
logosup security          # Scan and report findings
logosup security apply    # Apply fixes interactively (confirms each step)
```

## What it checks and fixes

| Check | What it does |
|-------|--------------|
| **Firewall** | Install and enable UFW/firewalld with SSH + Node P2P ports. Optionally allow API and Grafana. |
| **SSH hardening** | Disable root login, offer key-only auth (only when SSH keys exist — won't lock you out) |
| **Auto security updates** | Enable unattended-upgrades (Debian/Ubuntu) or dnf-automatic (RHEL/Fedora) |
| **fail2ban** | Install with sshd jail — blocks IPs after 5 failed attempts for 1 hour |
| **File permissions** | Ensure node directory is restricted (700) |

## Supported distributions

- Debian / Ubuntu / Raspbian
- Fedora / RHEL / CentOS / Rocky
- Arch Linux

The hardening flow is also offered during `logosup install`.
