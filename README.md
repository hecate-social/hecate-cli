# hecate-cli

Command-line interface for managing Hecate nodes, daemons, and plugins.

## Overview

The `hecate` CLI provides headless access to all Hecate node operations:
daemon lifecycle, plugin installation/removal, service management, and
plugin subcommand delegation. It talks to daemons via Unix domain sockets
and manages services through systemd.

## Installation

### Via hecate-install installer (recommended)

```bash
curl -sL https://install.hecate.social | bash
```

The installer downloads the CLI automatically.

### Manual install

```bash
# Download latest release
curl -sLO https://codeberg.org/hecate-social/hecate-cli/releases/latest/download/hecate
curl -sLO https://codeberg.org/hecate-social/hecate-cli/releases/latest/download/registry.json

# Install
chmod +x hecate
mkdir -p ~/.local/bin ~/.local/share/hecate
mv hecate ~/.local/bin/
mv registry.json ~/.local/share/hecate/

# Ensure ~/.local/bin is on PATH
```

## Commands

### Node Commands

| Command | Description |
|---------|-------------|
| `hecate status` | Show node status, installed plugins, and services |
| `hecate health` | Daemon health check (JSON response) |
| `hecate identity` | Show node identity (JSON response) |
| `hecate version` | Show CLI version |

### Service Commands

| Command | Description |
|---------|-------------|
| `hecate start [service]` | Start a service (default: daemon) |
| `hecate stop [service]` | Stop a service (default: daemon) |
| `hecate restart [service]` | Restart a service (default: daemon) |
| `hecate logs [service]` | View service logs (default: daemon) |
| `hecate update` | Pull latest container images via podman auto-update |

### Plugin Commands

| Command | Description |
|---------|-------------|
| `hecate plugins` | List available and installed plugins |
| `hecate install <plugin>` | Install a plugin from hecate-gitops |
| `hecate remove <plugin>` | Remove a plugin (preserves data directory) |

### System Commands

| Command | Description |
|---------|-------------|
| `hecate reconcile` | Run manual gitops reconciliation |
| `hecate help` | Show help |

### Plugin Delegation

Any unrecognized command is treated as a plugin name, with the rest
delegated to the plugin daemon via its Unix socket:

```bash
hecate trader health          # GET /health on traderd socket
hecate trader agents          # GET /api/agents on traderd socket
hecate martha status          # GET /api/status on marthad socket
```

## Service Names

The CLI resolves short names to systemd unit names:

| You type | Resolves to |
|----------|-------------|
| `daemon` | `hecate-daemon` |
| `reconciler` | `hecate-reconciler` |
| `trader` | `hecate-traderd` |
| `traderd` | `hecate-traderd` |
| `traderw` | `hecate-traderw` |

## Plugin Install Flow

When you run `hecate install trader`:

1. Checks if the plugin is already installed
2. Shallow-clones hecate-gitops to a temp directory
3. Copies Quadlet `.container` and `.env` files to `~/.hecate/gitops/apps/`
4. Creates the plugin data directory at `~/.hecate/hecate-traderd/`
5. Triggers the reconciler to symlink units and start services
6. Waits for the plugin daemon socket to appear

## Plugin Registry

The `plugins/registry.json` file describes known plugins:

```json
{
  "trader": {
    "description": "Trading agent",
    "files": ["hecate-traderd.container", "hecate-traderd.env", "hecate-traderw.container"],
    "data_dirs": ["hecate-traderd"],
    "frontend_port": 5174
  }
}
```

## Environment Variables

| Variable | Default | Description |
|----------|---------|-------------|
| `HECATE_DIR` | `~/.hecate` | Base data directory |
| `HECATE_GITOPS_REPO` | `https://codeberg.org/hecate-social/hecate-gitops.git` | GitOps repository URL |
| `HECATE_REGISTRY` | `<cli-dir>/plugins/registry.json` | Plugin registry file path |

## Dependencies

- `bash` 4.0+
- `curl` (for Unix socket communication)
- `python3` (for JSON parsing)
- `podman` (container runtime)
- `systemctl` (service management)
- `git` (for plugin installation)

## Architecture

```
hecate CLI
    |
    |-- systemctl --user    (service lifecycle)
    |-- journalctl --user   (logs)
    |-- podman auto-update  (image updates)
    |-- curl --unix-socket  (daemon/plugin API)
    |-- hecate-reconciler   (gitops sync)
    '-- git clone           (plugin manifest fetch)
```

## License

Apache License 2.0 - see [LICENSE](LICENSE) for details.
