#!/usr/bin/env bash
# hecate — CLI for managing Hecate nodes, daemons, and plugins
#
# Usage:
#   hecate <command> [args...]
#   hecate <plugin> <subcommand> [args...]
#
# See: hecate help

set -euo pipefail

# --- Version ---
HECATE_CLI_VERSION="0.1.0"

# --- Configuration ---
HECATE_DIR="${HECATE_DIR:-${HOME}/.hecate}"
GITOPS_DIR="${HECATE_DIR}/gitops"
DAEMON_SOCKET="${HECATE_DIR}/hecate-daemon/sockets/api.sock"
GITOPS_REPO="${HECATE_GITOPS_REPO:-https://github.com/hecate-social/hecate-gitops.git}"
REGISTRY_FILE="${HECATE_REGISTRY:-$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)/plugins/registry.json}"

# --- Colors (disabled if not a terminal) ---
if [[ -t 1 ]]; then
    BOLD='\033[1m'
    DIM='\033[2m'
    GREEN='\033[32m'
    YELLOW='\033[33m'
    RED='\033[31m'
    CYAN='\033[36m'
    RESET='\033[0m'
else
    BOLD='' DIM='' GREEN='' YELLOW='' RED='' CYAN='' RESET=''
fi

# --- Output helpers ---
info()  { echo -e "${GREEN}>>>${RESET} $*"; }
warn()  { echo -e "${YELLOW}>>>${RESET} $*" >&2; }
err()   { echo -e "${RED}>>>${RESET} $*" >&2; }
die()   { err "$@"; exit 1; }
header() { echo -e "\n${BOLD}$*${RESET}"; }

# --- Socket helpers ---
socket_exists() { [[ -S "$1" ]]; }

socket_curl() {
    local socket="$1" path="$2"
    shift 2
    curl -sf --unix-socket "${socket}" "http://localhost${path}" "$@"
}

# --- Plugin helpers ---
plugin_socket() {
    local plugin="$1"
    echo "${HECATE_DIR}/hecate-${plugin}d/sockets/api.sock"
}

plugin_installed() {
    local plugin="$1"
    local container_file="${GITOPS_DIR}/apps/hecate-${plugin}d.container"
    [[ -f "${container_file}" ]]
}

# Read a field from registry.json for a given plugin
# Usage: registry_field <plugin> <field>
registry_field() {
    local plugin="$1" field="$2"
    if [[ ! -f "${REGISTRY_FILE}" ]]; then
        return 1
    fi
    # Use python for JSON parsing (available on most systems)
    python3 -c "
import json, sys
with open('${REGISTRY_FILE}') as f:
    reg = json.load(f)
if '${plugin}' not in reg:
    sys.exit(1)
val = reg['${plugin}'].get('${field}', '')
if isinstance(val, list):
    print('\n'.join(val))
else:
    print(val)
" 2>/dev/null
}

# List all known plugin names from registry
registry_plugins() {
    if [[ ! -f "${REGISTRY_FILE}" ]]; then
        return 1
    fi
    python3 -c "
import json
with open('${REGISTRY_FILE}') as f:
    reg = json.load(f)
for k in sorted(reg.keys()):
    print(k)
" 2>/dev/null
}

# --- Service name resolution ---
# Converts user-friendly names to systemd unit names
resolve_service() {
    local name="${1:-daemon}"
    case "${name}" in
        daemon)    echo "hecate-daemon" ;;
        reconciler) echo "hecate-reconciler" ;;
        *d)        echo "hecate-${name}" ;;       # traderd → hecate-traderd
        *w)        echo "hecate-${name}" ;;       # traderw → hecate-traderw
        *)         echo "hecate-${name}d" ;;      # trader → hecate-traderd
    esac
}

# ============================================================================
# Commands
# ============================================================================

cmd_version() {
    echo "hecate ${HECATE_CLI_VERSION}"
}

cmd_status() {
    header "Hecate Node Status"

    # Daemon
    echo ""
    echo -e "${BOLD}Daemon${RESET}"
    if socket_exists "${DAEMON_SOCKET}"; then
        local health
        health=$(socket_curl "${DAEMON_SOCKET}" "/health" 2>/dev/null || echo '{"status":"unreachable"}')
        echo -e "  Socket:  ${GREEN}ready${RESET} (${DAEMON_SOCKET})"
        echo -e "  Health:  ${health}"
    else
        echo -e "  Socket:  ${RED}not found${RESET} (${DAEMON_SOCKET})"
    fi

    # Reconciler
    echo ""
    echo -e "${BOLD}Reconciler${RESET}"
    local recon_status
    recon_status=$(systemctl --user is-active hecate-reconciler.service 2>/dev/null || echo "inactive")
    if [[ "${recon_status}" == "active" ]]; then
        echo -e "  Status:  ${GREEN}${recon_status}${RESET}"
    else
        echo -e "  Status:  ${DIM}${recon_status}${RESET}"
    fi

    # Installed plugins
    echo ""
    echo -e "${BOLD}Plugins${RESET}"
    local found_any=false
    if [[ -d "${GITOPS_DIR}/apps" ]]; then
        for container_file in "${GITOPS_DIR}/apps"/*.container; do
            [[ -f "${container_file}" ]] || continue
            local name
            name=$(basename "${container_file}" .container)
            local unit_name="${name}.service"
            local unit_status
            unit_status=$(systemctl --user is-active "${unit_name}" 2>/dev/null || echo "inactive")
            if [[ "${unit_status}" == "active" ]]; then
                echo -e "  ${name}:  ${GREEN}${unit_status}${RESET}"
            else
                echo -e "  ${name}:  ${DIM}${unit_status}${RESET}"
            fi
            found_any=true
        done
    fi
    if [[ "${found_any}" == "false" ]]; then
        echo -e "  ${DIM}(none installed)${RESET}"
    fi

    # Services overview
    echo ""
    echo -e "${BOLD}All Hecate Services${RESET}"
    systemctl --user list-units 'hecate-*' --no-pager --no-legend 2>/dev/null | while read -r line; do
        echo "  ${line}"
    done
    echo ""
}

cmd_start() {
    local service
    service=$(resolve_service "${1:-daemon}")
    info "Starting ${service}..."
    systemctl --user start "${service}.service"
    info "Started ${service}"
}

cmd_stop() {
    local service
    service=$(resolve_service "${1:-daemon}")
    info "Stopping ${service}..."
    systemctl --user stop "${service}.service"
    info "Stopped ${service}"
}

cmd_restart() {
    local service
    service=$(resolve_service "${1:-daemon}")
    info "Restarting ${service}..."
    systemctl --user restart "${service}.service"
    info "Restarted ${service}"
}

cmd_logs() {
    local service
    service=$(resolve_service "${1:-daemon}")
    shift || true
    journalctl --user -u "${service}" --no-pager "$@"
}

cmd_health() {
    if ! socket_exists "${DAEMON_SOCKET}"; then
        die "Daemon socket not found: ${DAEMON_SOCKET}"
    fi
    socket_curl "${DAEMON_SOCKET}" "/health"
    echo ""
}

cmd_identity() {
    if ! socket_exists "${DAEMON_SOCKET}"; then
        die "Daemon socket not found: ${DAEMON_SOCKET}"
    fi
    socket_curl "${DAEMON_SOCKET}" "/identity"
    echo ""
}

cmd_update() {
    info "Pulling latest container images..."
    podman auto-update 2>/dev/null || warn "podman auto-update returned non-zero"
    info "Done"
}

cmd_reconcile() {
    info "Running reconciliation..."
    if command -v hecate-reconciler &>/dev/null; then
        hecate-reconciler --once
    elif [[ -x "${HOME}/.local/bin/hecate-reconciler" ]]; then
        "${HOME}/.local/bin/hecate-reconciler" --once
    else
        die "hecate-reconciler not found. Install it from hecate-gitops/reconciler/"
    fi
}

cmd_plugins() {
    header "Available Plugins"
    echo ""

    local known_plugins
    known_plugins=$(registry_plugins 2>/dev/null || true)

    if [[ -z "${known_plugins}" ]]; then
        echo -e "  ${DIM}(no registry found at ${REGISTRY_FILE})${RESET}"
        echo ""
        echo "Installed plugins (from gitops):"
        if [[ -d "${GITOPS_DIR}/apps" ]]; then
            for f in "${GITOPS_DIR}/apps"/*.container; do
                [[ -f "${f}" ]] || continue
                echo "  $(basename "${f}" .container)"
            done
        fi
        return
    fi

    printf "  ${BOLD}%-12s %-30s %-10s${RESET}\n" "Plugin" "Description" "Status"
    printf "  %-12s %-30s %-10s\n" "------" "-----------" "------"

    while IFS= read -r plugin; do
        local desc
        desc=$(registry_field "${plugin}" "description" 2>/dev/null || echo "")
        local status
        if plugin_installed "${plugin}"; then
            status="${GREEN}installed${RESET}"
        else
            status="${DIM}available${RESET}"
        fi
        printf "  %-12s %-30s %b\n" "${plugin}" "${desc}" "${status}"
    done <<< "${known_plugins}"
    echo ""
}

cmd_install() {
    local plugin="${1:-}"
    if [[ -z "${plugin}" ]]; then
        echo "Usage: hecate install <plugin>"
        echo ""
        echo "Run 'hecate plugins' to see available plugins."
        exit 1
    fi

    # Check if already installed
    if plugin_installed "${plugin}"; then
        warn "Plugin '${plugin}' is already installed"
        echo "Run 'hecate restart ${plugin}' to restart it."
        return 0
    fi

    # Get the files list from registry
    local files
    files=$(registry_field "${plugin}" "files" 2>/dev/null || true)
    if [[ -z "${files}" ]]; then
        die "Unknown plugin '${plugin}'. Run 'hecate plugins' to see available plugins."
    fi

    local data_dirs
    data_dirs=$(registry_field "${plugin}" "data_dirs" 2>/dev/null || true)

    info "Installing plugin '${plugin}'..."

    # Clone hecate-gitops to get Quadlet files
    local tmp_dir
    tmp_dir=$(mktemp -d)
    trap "rm -rf '${tmp_dir}'" EXIT

    info "Fetching plugin manifests from hecate-gitops..."
    git clone --depth 1 --filter=blob:none --sparse "${GITOPS_REPO}" "${tmp_dir}/gitops" 2>/dev/null
    (cd "${tmp_dir}/gitops" && git sparse-checkout set quadlet/apps 2>/dev/null)

    # Copy Quadlet files to gitops/apps/
    mkdir -p "${GITOPS_DIR}/apps"
    while IFS= read -r file; do
        [[ -z "${file}" ]] && continue
        local src="${tmp_dir}/gitops/quadlet/apps/${file}"
        local dest="${GITOPS_DIR}/apps/${file}"
        if [[ -f "${src}" ]]; then
            cp "${src}" "${dest}"
            info "  Installed: ${file}"
        else
            warn "  Not found in gitops: ${file}"
        fi
    done <<< "${files}"

    # Also copy .env files that match the daemon container name
    for env_file in "${tmp_dir}/gitops/quadlet/apps/hecate-${plugin}"*.env; do
        if [[ -f "${env_file}" ]]; then
            local env_name
            env_name=$(basename "${env_file}")
            cp "${env_file}" "${GITOPS_DIR}/apps/${env_name}"
            info "  Installed: ${env_name}"
        fi
    done

    # Create plugin data directories
    while IFS= read -r dir; do
        [[ -z "${dir}" ]] && continue
        local data_path="${HECATE_DIR}/${dir}"
        if [[ ! -d "${data_path}" ]]; then
            mkdir -p "${data_path}/sqlite" "${data_path}/reckon-db" "${data_path}/sockets" "${data_path}/run" "${data_path}/connectors"
            info "  Created data dir: ${data_path}"
        fi
    done <<< "${data_dirs}"

    # Trigger reconciliation
    info "Triggering reconciliation..."
    cmd_reconcile 2>/dev/null || true

    # Wait for daemon socket (if plugin has a daemon component)
    local plugin_sock
    plugin_sock=$(plugin_socket "${plugin}")
    if [[ -n "${data_dirs}" ]]; then
        info "Waiting for ${plugin} daemon socket..."
        local attempts=0
        while [[ ${attempts} -lt 30 ]]; do
            if socket_exists "${plugin_sock}"; then
                info "Plugin '${plugin}' is ready!"
                echo ""
                echo "  Socket: ${plugin_sock}"
                echo "  Status: hecate status"
                echo "  Logs:   hecate logs ${plugin}"
                echo ""
                return 0
            fi
            sleep 1
            attempts=$((attempts + 1))
        done
        warn "Plugin '${plugin}' installed but socket not yet available."
        echo "Check logs: hecate logs ${plugin}"
    fi
}

cmd_remove() {
    local plugin="${1:-}"
    if [[ -z "${plugin}" ]]; then
        echo "Usage: hecate remove <plugin>"
        exit 1
    fi

    if ! plugin_installed "${plugin}"; then
        warn "Plugin '${plugin}' is not installed"
        return 0
    fi

    info "Removing plugin '${plugin}'..."

    # Stop services before removing files
    for container_file in "${GITOPS_DIR}/apps/hecate-${plugin}"*.container; do
        [[ -f "${container_file}" ]] || continue
        local name
        name=$(basename "${container_file}" .container)
        local unit_name="${name}.service"
        info "  Stopping ${unit_name}..."
        systemctl --user stop "${unit_name}" 2>/dev/null || true
    done

    # Remove Quadlet files from gitops/apps/
    for f in "${GITOPS_DIR}/apps/hecate-${plugin}"*.container "${GITOPS_DIR}/apps/hecate-${plugin}"*.env; do
        if [[ -f "${f}" ]]; then
            local fname
            fname=$(basename "${f}")
            rm "${f}"
            info "  Removed: ${fname}"
        fi
    done

    # Trigger reconciliation to clean up symlinks
    info "Triggering reconciliation..."
    cmd_reconcile 2>/dev/null || true

    info "Plugin '${plugin}' removed"
    echo ""
    echo "  Data directory preserved at: ${HECATE_DIR}/hecate-${plugin}d/"
    echo "  To delete data: rm -rf ${HECATE_DIR}/hecate-${plugin}d/"
    echo ""
}

# Delegate a subcommand to a plugin daemon via its Unix socket
cmd_plugin_delegate() {
    local plugin="$1"
    shift
    local subcommand="${1:-health}"
    shift || true

    local sock
    sock=$(plugin_socket "${plugin}")

    if ! socket_exists "${sock}"; then
        die "Plugin '${plugin}' socket not found: ${sock}"
    fi

    case "${subcommand}" in
        health)
            socket_curl "${sock}" "/health"
            echo ""
            ;;
        *)
            local path="/api/${subcommand}"
            if [[ $# -gt 0 ]]; then
                path="${path}/$*"
            fi
            local response
            response=$(socket_curl "${sock}" "${path}" 2>/dev/null || true)
            if [[ -n "${response}" ]]; then
                echo "${response}"
            else
                die "No response from ${plugin} daemon at ${path}"
            fi
            ;;
    esac
}

cmd_help() {
    cat <<EOF
${BOLD}Hecate${RESET} — Powered by Macula

${BOLD}Usage:${RESET}
  hecate <command> [args...]
  hecate <plugin> <subcommand> [args...]

${BOLD}Node Commands:${RESET}
  status              Show node status, plugins, and services
  health              Daemon health check (JSON)
  identity            Show node identity (JSON)
  version             Show CLI version

${BOLD}Service Commands:${RESET}
  start [service]     Start a service (default: daemon)
  stop [service]      Stop a service (default: daemon)
  restart [service]   Restart a service (default: daemon)
  logs [service]      View service logs (default: daemon)
  update              Pull latest container images

${BOLD}Plugin Commands:${RESET}
  plugins             List available and installed plugins
  install <plugin>    Install a plugin
  remove <plugin>     Remove a plugin (preserves data)

${BOLD}System Commands:${RESET}
  reconcile           Run manual gitops reconciliation
  help                Show this help
  version             Show CLI version

${BOLD}Plugin Delegation:${RESET}
  hecate <plugin> health       Health check on plugin daemon
  hecate <plugin> <command>    Delegate command to plugin daemon

${BOLD}Service Names:${RESET}
  daemon              hecate-daemon (core)
  reconciler          hecate-reconciler
  trader              hecate-traderd (plugin daemon)
  traderd             hecate-traderd (explicit)
  traderw             hecate-traderw (plugin frontend)

${BOLD}Examples:${RESET}
  hecate status                 Show everything
  hecate install trader         Install the trader plugin
  hecate trader health          Check trader daemon health
  hecate logs trader            View trader daemon logs
  hecate logs traderw           View trader frontend logs
  hecate remove trader          Remove trader plugin

${BOLD}Paths:${RESET}
  Data:     ${HECATE_DIR}
  GitOps:   ${GITOPS_DIR}
  Registry: ${REGISTRY_FILE}

EOF
}

# ============================================================================
# Main dispatch
# ============================================================================

main() {
    local cmd="${1:-help}"
    shift || true

    case "${cmd}" in
        # Node commands
        status)     cmd_status ;;
        health)     cmd_health ;;
        identity)   cmd_identity ;;
        version|--version|-v) cmd_version ;;

        # Service commands
        start)      cmd_start "$@" ;;
        stop)       cmd_stop "$@" ;;
        restart)    cmd_restart "$@" ;;
        logs)       cmd_logs "$@" ;;
        update)     cmd_update ;;

        # Plugin commands
        plugins)    cmd_plugins ;;
        install)    cmd_install "$@" ;;
        remove)     cmd_remove "$@" ;;

        # System commands
        reconcile)  cmd_reconcile ;;
        help|--help|-h) cmd_help ;;

        # Plugin delegation: hecate <plugin> <subcommand>
        *)
            # Check if this is a known or installed plugin
            if plugin_installed "${cmd}" || registry_field "${cmd}" "description" &>/dev/null; then
                cmd_plugin_delegate "${cmd}" "$@"
            else
                err "Unknown command: ${cmd}"
                echo ""
                cmd_help
                exit 1
            fi
            ;;
    esac
}

main "$@"
