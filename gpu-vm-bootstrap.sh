#!/usr/bin/env bash
# shellcheck disable=SC2034
# SPDX-License-Identifier: MIT OR Apache-2.0
# gpu-vm-bootstrap.sh — One-liner bootstrap for Ubuntu 24.04 GPU VM hosts
# Transforms a fresh Ubuntu 24.04 installation into a fully GPU-capable
# virtualisation host with KVM, VFIO passthrough, and bridge networking.
#
# Usage:
#   curl -fsSL https://github.com/XMV-Solutions-GmbH/ubuntu-24.04-gpu-vm-bootstrap/releases/latest/download/gpu-vm-bootstrap.sh | sudo bash
#
# Copyright (c) 2024-2026 XMV Solutions GmbH
# See LICENCE files for details.

set -euo pipefail

# =============================================================================
# Constants
# =============================================================================

readonly SCRIPT_NAME="gpu-vm-bootstrap"
readonly SCRIPT_VERSION="0.1.0-dev"
LOG_FILE="${LOG_FILE:-/var/log/${SCRIPT_NAME}.log}"
CONFIG_DIR="${CONFIG_DIR:-/etc/vmctl}"

# Exit codes
readonly EXIT_SUCCESS=0
readonly EXIT_GENERAL_ERROR=1
readonly EXIT_INVALID_ARGS=2
readonly EXIT_MISSING_DEPS=3
readonly EXIT_NOT_ROOT=4
readonly EXIT_UNSUPPORTED_OS=5
readonly EXIT_NO_NETWORK=6

# Colour codes (disabled when stdout is not a terminal)
if [[ -t 1 ]]; then
    readonly CLR_RED='\033[0;31m'
    readonly CLR_GREEN='\033[0;32m'
    readonly CLR_YELLOW='\033[1;33m'
    readonly CLR_BLUE='\033[0;34m'
    readonly CLR_CYAN='\033[0;36m'
    readonly CLR_BOLD='\033[1m'
    readonly CLR_RESET='\033[0m'
else
    readonly CLR_RED=''
    readonly CLR_GREEN=''
    readonly CLR_YELLOW=''
    readonly CLR_BLUE=''
    readonly CLR_CYAN=''
    readonly CLR_BOLD=''
    readonly CLR_RESET=''
fi

# =============================================================================
# Default Configuration
# =============================================================================

# Phase skip flags
SKIP_NVIDIA=false
SKIP_KVM=false
SKIP_VFIO=false
SKIP_BRIDGE=false

# GPU mode: "exclusive" (always VFIO) or "flexible" (on-demand passthrough)
GPU_MODE="flexible"

# Bridge configuration
BRIDGE_NAME="br0"
BRIDGE_SUBNET=""

# Behaviour flags
DRY_RUN=false
YES_MODE=false
REBOOT_ALLOWED=false
VERBOSE=false

# Internal state
_LOG_INITIALISED=false

# =============================================================================
# Logging Framework
# =============================================================================

# Initialise the log file with appropriate permissions
log_init() {
    if [[ "${_LOG_INITIALISED}" == "true" ]]; then
        return 0
    fi

    local log_dir
    log_dir="$(dirname "${LOG_FILE}")"

    if [[ ! -d "${log_dir}" ]]; then
        mkdir -p "${log_dir}" 2>/dev/null || true
    fi

    if touch "${LOG_FILE}" 2>/dev/null; then
        chmod 644 "${LOG_FILE}" 2>/dev/null || true
        _LOG_INITIALISED=true
    fi
}

# Write a timestamped message to the log file (if initialised)
_log_to_file() {
    local level="$1"
    shift
    local message="$*"
    local timestamp
    timestamp="$(date '+%Y-%m-%d %H:%M:%S')"

    if [[ "${_LOG_INITIALISED}" == "true" ]]; then
        printf '%s [%-5s] %s\n' "${timestamp}" "${level}" "${message}" >> "${LOG_FILE}" 2>/dev/null || true
    fi
}

# Print a formatted message to stdout and log file
_log() {
    local colour="$1"
    local prefix="$2"
    local level="$3"
    shift 3
    local message="$*"

    printf '%b[%s]%b %s\n' "${colour}" "${prefix}" "${CLR_RESET}" "${message}" >&2
    _log_to_file "${level}" "${message}"
}

log_info() {
    _log "${CLR_CYAN}" "INFO" "INFO" "$@"
}

log_success() {
    _log "${CLR_GREEN}" " OK " "OK" "$@"
}

log_warn() {
    _log "${CLR_YELLOW}" "WARN" "WARN" "$@"
}

log_error() {
    _log "${CLR_RED}" "FAIL" "ERROR" "$@"
}

log_debug() {
    if [[ "${VERBOSE}" == "true" ]]; then
        _log "${CLR_BLUE}" "DBUG" "DEBUG" "$@"
    else
        _log_to_file "DEBUG" "$@"
    fi
}

log_phase() {
    local phase_num="$1"
    local phase_name="$2"
    echo "" >&2
    printf '%b══════════════════════════════════════════════════════════════%b\n' "${CLR_BOLD}" "${CLR_RESET}" >&2
    printf '%b  Phase %s: %s%b\n' "${CLR_BOLD}" "${phase_num}" "${phase_name}" "${CLR_RESET}" >&2
    printf '%b══════════════════════════════════════════════════════════════%b\n' "${CLR_BOLD}" "${CLR_RESET}" >&2
    echo "" >&2
    _log_to_file "PHASE" "Phase ${phase_num}: ${phase_name}"
}

log_step() {
    local step="$1"
    shift
    printf '  %b→%b %s\n' "${CLR_CYAN}" "${CLR_RESET}" "$*" >&2
    _log_to_file "STEP" "[${step}] $*"
}

log_dry_run() {
    printf '  %b[DRY-RUN]%b %s\n' "${CLR_YELLOW}" "${CLR_RESET}" "$*" >&2
    _log_to_file "DRY" "$*"
}

# =============================================================================
# Argument Parsing
# =============================================================================

show_banner() {
    cat >&2 << 'EOF'

    ╔═══════════════════════════════════════════════════════╗
    ║       Ubuntu 24.04 GPU VM Bootstrap                  ║
    ║       GPU-accelerated virtualisation host setup       ║
    ╚═══════════════════════════════════════════════════════╝

EOF
}

show_usage() {
    cat >&2 << EOF
Usage: ${0##*/} [OPTIONS]

Bootstrap an Ubuntu 24.04 host for GPU-accelerated virtual machines.

Options:
  --skip-nvidia         Skip NVIDIA driver and CUDA installation
  --skip-kvm            Skip KVM/libvirt setup
  --skip-vfio           Skip IOMMU/VFIO configuration
  --skip-bridge         Skip bridge network setup
  --bridge-name NAME    Bridge interface name (default: br0)
  --bridge-subnet CIDR  Bridge subnet (auto-detected if omitted)
  --gpu-mode MODE       GPU mode: "exclusive" or "flexible" (default: flexible)
  --dry-run             Show what would be done without executing
  --yes                 Non-interactive mode, accept all defaults
  --reboot              Allow automatic reboot if required
  --verbose             Enable verbose/debug output
  --version             Show version and exit
  -h, --help            Show this help and exit

GPU Modes:
  exclusive   GPU is always bound to VFIO (dedicated to VMs)
  flexible    GPU stays on host driver; bind/unbind on demand via vmctl

Examples:
  # Full bootstrap with defaults
  sudo ./gpu-vm-bootstrap.sh

  # Non-interactive, skip bridge setup
  sudo ./gpu-vm-bootstrap.sh --yes --skip-bridge

  # Dry run to preview actions
  sudo ./gpu-vm-bootstrap.sh --dry-run

  # Exclusive GPU passthrough mode
  sudo ./gpu-vm-bootstrap.sh --gpu-mode exclusive --yes

EOF
}

parse_args() {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --skip-nvidia)
                SKIP_NVIDIA=true
                shift
                ;;
            --skip-kvm)
                SKIP_KVM=true
                shift
                ;;
            --skip-vfio)
                SKIP_VFIO=true
                shift
                ;;
            --skip-bridge)
                SKIP_BRIDGE=true
                shift
                ;;
            --bridge-name)
                if [[ -z "${2:-}" ]]; then
                    log_error "--bridge-name requires a value"
                    return "${EXIT_INVALID_ARGS}"
                fi
                BRIDGE_NAME="$2"
                shift 2
                ;;
            --bridge-subnet)
                if [[ -z "${2:-}" ]]; then
                    log_error "--bridge-subnet requires a value"
                    return "${EXIT_INVALID_ARGS}"
                fi
                BRIDGE_SUBNET="$2"
                shift 2
                ;;
            --gpu-mode)
                if [[ -z "${2:-}" ]]; then
                    log_error "--gpu-mode requires a value"
                    return "${EXIT_INVALID_ARGS}"
                fi
                if [[ "$2" != "exclusive" && "$2" != "flexible" ]]; then
                    log_error "Invalid GPU mode: '$2' (must be 'exclusive' or 'flexible')"
                    return "${EXIT_INVALID_ARGS}"
                fi
                GPU_MODE="$2"
                shift 2
                ;;
            --dry-run)
                DRY_RUN=true
                shift
                ;;
            --yes|-y)
                YES_MODE=true
                shift
                ;;
            --reboot)
                REBOOT_ALLOWED=true
                shift
                ;;
            --verbose|-v)
                VERBOSE=true
                shift
                ;;
            --version)
                echo "${SCRIPT_NAME} v${SCRIPT_VERSION}"
                exit "${EXIT_SUCCESS}"
                ;;
            -h|--help)
                show_usage
                exit "${EXIT_SUCCESS}"
                ;;
            *)
                log_error "Unknown option: '$1'"
                echo "Run '${0##*/} --help' for usage information." >&2
                return "${EXIT_INVALID_ARGS}"
                ;;
        esac
    done
}

# =============================================================================
# Pre-flight Checks
# =============================================================================

# Check that we are running on Ubuntu 24.04
check_ubuntu_version() {
    local os_release_file="${OS_RELEASE_FILE:-/etc/os-release}"

    if [[ ! -f "${os_release_file}" ]]; then
        log_error "Cannot detect OS: ${os_release_file} not found"
        return "${EXIT_UNSUPPORTED_OS}"
    fi

    local version_id=""
    local id=""

    # shellcheck disable=SC1090
    source "${os_release_file}"
    version_id="${VERSION_ID:-}"
    id="${ID:-}"

    if [[ "${id}" != "ubuntu" ]]; then
        log_error "Unsupported OS: '${id}' (only Ubuntu is supported)"
        return "${EXIT_UNSUPPORTED_OS}"
    fi

    if [[ "${version_id}" != "24.04" ]]; then
        log_error "Unsupported Ubuntu version: '${version_id}' (only 24.04 is supported)"
        return "${EXIT_UNSUPPORTED_OS}"
    fi

    log_success "Ubuntu 24.04 detected"
    return "${EXIT_SUCCESS}"
}

# Check that we are running as root or with sudo
check_root() {
    if [[ "$(id -u)" -ne 0 ]]; then
        log_error "This script must be run as root (use sudo)"
        return "${EXIT_NOT_ROOT}"
    fi

    log_success "Running as root"
    return "${EXIT_SUCCESS}"
}

# Check internet connectivity
check_network() {
    log_step "network" "Checking internet connectivity..."

    local test_hosts=("archive.ubuntu.com" "github.com" "developer.download.nvidia.com")
    local reachable=false

    for host in "${test_hosts[@]}"; do
        if ping -c 1 -W 3 "${host}" &>/dev/null; then
            reachable=true
            log_debug "Host reachable: ${host}"
            break
        fi
        log_debug "Host unreachable: ${host}"
    done

    if [[ "${reachable}" != "true" ]]; then
        log_error "No internet connectivity detected"
        log_error "Tried: ${test_hosts[*]}"
        return "${EXIT_NO_NETWORK}"
    fi

    log_success "Internet connectivity confirmed"
    return "${EXIT_SUCCESS}"
}

# Run all pre-flight checks
run_preflight_checks() {
    log_phase "0" "Pre-flight Checks"

    log_step "os" "Checking operating system..."
    check_ubuntu_version

    log_step "root" "Checking privileges..."
    check_root

    check_network

    log_success "All pre-flight checks passed"
}

# =============================================================================
# Idempotency Helpers
# =============================================================================

# Check if a Debian/Ubuntu package is installed
is_pkg_installed() {
    local pkg="$1"
    dpkg-query -W -f='${Status}' "${pkg}" 2>/dev/null | grep -q "install ok installed"
}

# Check if a systemd service is active
is_service_active() {
    local service="$1"
    systemctl is-active --quiet "${service}" 2>/dev/null
}

# Check if a systemd service is enabled
is_service_enabled() {
    local service="$1"
    systemctl is-enabled --quiet "${service}" 2>/dev/null
}

# Check if a kernel module is loaded
is_module_loaded() {
    local module="$1"
    lsmod | grep -qw "${module}" 2>/dev/null
}

# Check if a command/binary exists in PATH
is_command_available() {
    local cmd="$1"
    command -v "${cmd}" &>/dev/null
}

# Check if a file exists and is non-empty
is_file_present() {
    local filepath="$1"
    [[ -f "${filepath}" && -s "${filepath}" ]]
}

# Check if a line exists in a file
is_line_in_file() {
    local filepath="$1"
    local line="$2"
    grep -qF "${line}" "${filepath}" 2>/dev/null
}

# Check if a GRUB parameter is already set
is_grub_param_set() {
    local param="$1"
    local grub_file="${GRUB_DEFAULT_FILE:-/etc/default/grub}"

    if [[ -f "${grub_file}" ]]; then
        grep -q "GRUB_CMDLINE_LINUX_DEFAULT=.*${param}" "${grub_file}" 2>/dev/null
    else
        return 1
    fi
}

# Install a package if not already installed (with dry-run support)
ensure_pkg_installed() {
    local pkg="$1"

    if is_pkg_installed "${pkg}"; then
        log_debug "Package already installed: ${pkg}"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "Would install package: ${pkg}"
        return 0
    fi

    log_info "Installing package: ${pkg}"
    DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${pkg}" >> "${LOG_FILE}" 2>&1
    log_success "Installed: ${pkg}"
}

# Enable and start a systemd service if not already active
ensure_service_running() {
    local service="$1"

    if is_service_active "${service}"; then
        log_debug "Service already active: ${service}"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "Would enable and start service: ${service}"
        return 0
    fi

    log_info "Enabling and starting service: ${service}"
    systemctl enable --now "${service}" >> "${LOG_FILE}" 2>&1
    log_success "Service started: ${service}"
}

# =============================================================================
# Phase Runner
# =============================================================================

# Execute a phase function if not skipped
run_phase() {
    local phase_num="$1"
    local phase_name="$2"
    local phase_fn="$3"
    local skip_flag="${4:-false}"

    if [[ "${skip_flag}" == "true" ]]; then
        log_info "Skipping Phase ${phase_num}: ${phase_name} (--skip flag set)"
        _log_to_file "SKIP" "Phase ${phase_num}: ${phase_name}"
        return 0
    fi

    log_phase "${phase_num}" "${phase_name}"

    if "${phase_fn}"; then
        log_success "Phase ${phase_num} complete: ${phase_name}"
        return 0
    else
        local rc=$?
        log_error "Phase ${phase_num} failed: ${phase_name}"
        return "${rc}"
    fi
}

# =============================================================================
# Phase Stubs (to be implemented in subsequent phases)
# =============================================================================

phase_nvidia_setup() {
    log_info "NVIDIA driver and CUDA setup — not yet implemented"
    return 0
}

phase_kvm_setup() {
    log_info "KVM/libvirt setup — not yet implemented"
    return 0
}

phase_vfio_setup() {
    log_info "IOMMU/VFIO configuration — not yet implemented"
    return 0
}

phase_bridge_setup() {
    log_info "Bridge network setup — not yet implemented"
    return 0
}

phase_vmctl_install() {
    log_info "vmctl installation — not yet implemented"
    return 0
}

# =============================================================================
# Summary
# =============================================================================

print_summary() {
    echo "" >&2
    printf '%b══════════════════════════════════════════════════════════════%b\n' "${CLR_BOLD}" "${CLR_RESET}" >&2
    printf '%b  Bootstrap Complete%b\n' "${CLR_GREEN}" "${CLR_RESET}" >&2
    printf '%b══════════════════════════════════════════════════════════════%b\n' "${CLR_BOLD}" "${CLR_RESET}" >&2
    echo "" >&2
    log_info "Log file: ${LOG_FILE}"
    log_info "GPU mode: ${GPU_MODE}"
    log_info "Bridge: ${BRIDGE_NAME}"

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warn "This was a dry run — no changes were made"
    fi
    echo "" >&2
}

# =============================================================================
# Main Entry Point
# =============================================================================

main() {
    show_banner
    parse_args "$@"

    log_init
    _log_to_file "START" "${SCRIPT_NAME} v${SCRIPT_VERSION} started"
    _log_to_file "ARGS" "skip_nvidia=${SKIP_NVIDIA} skip_kvm=${SKIP_KVM} skip_vfio=${SKIP_VFIO} skip_bridge=${SKIP_BRIDGE} gpu_mode=${GPU_MODE} dry_run=${DRY_RUN} yes=${YES_MODE}"

    log_info "${SCRIPT_NAME} v${SCRIPT_VERSION}"
    log_info "GPU mode: ${GPU_MODE}"
    log_info "Dry run: ${DRY_RUN}"

    # Phase 0: Pre-flight checks
    run_preflight_checks

    # Phase 1: NVIDIA setup
    run_phase 1 "NVIDIA Driver & CUDA Setup" phase_nvidia_setup "${SKIP_NVIDIA}"

    # Phase 2: KVM/libvirt setup
    run_phase 2 "KVM/libvirt Setup" phase_kvm_setup "${SKIP_KVM}"

    # Phase 3: IOMMU/VFIO configuration
    run_phase 3 "IOMMU/VFIO Configuration" phase_vfio_setup "${SKIP_VFIO}"

    # Phase 4: Bridge network setup
    run_phase 4 "Bridge Network Setup" phase_bridge_setup "${SKIP_BRIDGE}"

    # Phase 5: vmctl installation
    run_phase 5 "vmctl Installation" phase_vmctl_install

    # Summary
    print_summary

    _log_to_file "END" "${SCRIPT_NAME} completed successfully"
    return "${EXIT_SUCCESS}"
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
