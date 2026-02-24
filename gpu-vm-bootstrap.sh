#!/usr/bin/env bash
# shellcheck disable=SC2034
# SPDX-License-Identifier: MIT OR Apache-2.0
# gpu-vm-bootstrap.sh — One-liner bootstrap for Ubuntu 24.04 GPU VM hosts
# Transforms a fresh Ubuntu 24.04 installation into a fully GPU-capable
# virtualisation host with KVM, VFIO passthrough, and bridge networking.
#
# Usage:
#   curl -fsSL https://raw.githubusercontent.com/XMV-Solutions-GmbH/ubuntu-24.04-gpu-vm-bootstrap/main/gpu-vm-bootstrap.sh | sudo bash
#
# Copyright (c) 2024-2026 XMV Solutions GmbH
# See LICENCE files for details.

set -euo pipefail

# =============================================================================
# Constants
# =============================================================================

readonly SCRIPT_NAME="gpu-vm-bootstrap"
readonly SCRIPT_VERSION="0.1.0-dev"
readonly SCRIPT_DOWNLOAD_URL="https://raw.githubusercontent.com/XMV-Solutions-GmbH/ubuntu-24.04-gpu-vm-bootstrap/main/gpu-vm-bootstrap.sh"
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
REBOOT_REQUIRED=false

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
    ║       Ubuntu 24.04 GPU VM Bootstrap                   ║
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
  # One-liner bootstrap (auto-launches in tmux)
  curl -fsSL <URL> | sudo bash

  # Full bootstrap with defaults (inside tmux)
  sudo ./gpu-vm-bootstrap.sh

  # Non-interactive, skip bridge setup
  sudo ./gpu-vm-bootstrap.sh --yes --skip-bridge

  # Dry run to preview actions
  sudo ./gpu-vm-bootstrap.sh --dry-run

  # Exclusive GPU passthrough mode
  sudo ./gpu-vm-bootstrap.sh --gpu-mode exclusive

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

# Check for Secure Boot — NVIDIA drivers require it to be disabled
check_secure_boot() {
    log_step "secureboot" "Checking Secure Boot status..."

    # mokutil may not be installed; install it if needed
    if ! is_command_available mokutil; then
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_dry_run "Would install mokutil to check Secure Boot"
            log_info "Secure Boot check skipped in dry-run"
            return 0
        fi
        ensure_pkg_installed mokutil
    fi

    local sb_state=""
    sb_state="$(mokutil --sb-state 2>&1 || true)"

    if echo "${sb_state}" | grep -qi "SecureBoot enabled"; then
        log_error "Secure Boot is enabled"
        log_error ""
        log_error "NVIDIA proprietary drivers cannot be loaded with Secure Boot enabled"
        log_error "unless MOK (Machine Owner Key) enrollment is configured."
        log_error ""
        log_error "To disable Secure Boot:"
        log_error "  1. Reboot and enter BIOS/UEFI setup (usually DEL, F2, or F12)"
        log_error "  2. Navigate to Security → Secure Boot"
        log_error "  3. Set Secure Boot to 'Disabled'"
        log_error "  4. Save and exit BIOS"
        log_error "  5. Re-run this script"
        log_error ""
        log_error "For remote/headless servers (e.g. Hetzner, OVH):"
        log_error "  - Use the provider's rescue system or KVM console to access BIOS"
        log_error "  - Some providers offer a web-based BIOS/IPMI interface"
        log_error "  - Check your provider's documentation for Secure Boot settings"
        return "${EXIT_GENERAL_ERROR}"
    fi

    log_success "Secure Boot is disabled"
    return "${EXIT_SUCCESS}"
}

# Detect whether we are running inside a terminal multiplexer.
_is_inside_multiplexer() {
    [[ -n "${TMUX:-}" ]] && return 0
    [[ "${TERM:-}" == screen* ]] && return 0
    [[ -n "${STY:-}" ]] && return 0
    return 1
}

# Re-launch the bootstrap inside a tmux session so it survives
# SSH/tunnel disconnections.  This is called automatically when bridge
# setup is enabled and no multiplexer is detected.
#
# For piped execution (curl | sudo bash) the script cannot re-exec
# itself from «$0», so it downloads a fresh copy first.
_relaunch_in_tmux() {
    log_info "Bridge setup enabled — a terminal multiplexer is required"

    # Install tmux if not present
    if ! command -v tmux &>/dev/null; then
        log_info "Installing tmux..."
        apt-get update -qq >/dev/null 2>&1
        apt-get install -y -qq tmux >/dev/null 2>&1
    fi

    # Determine the script file path
    local script_path="${BASH_SOURCE[0]:-}"
    if [[ -z "${script_path}" ]] || [[ ! -f "${script_path}" ]]; then
        # Piped execution — download a copy
        script_path="/tmp/${SCRIPT_NAME}.sh"
        log_info "Downloading script to ${script_path}..."
        curl -fsSL "${SCRIPT_DOWNLOAD_URL}" -o "${script_path}"
        chmod +x "${script_path}"
    fi

    # Build the argument list for re-execution
    local -a args=("$@")

    log_info "Launching tmux session 'bootstrap'..."
    log_info "If disconnected, re-attach with: sudo tmux attach -t bootstrap"

    # Replace the current process with a tmux session
    exec tmux new-session -s bootstrap "${script_path}" "${args[@]}"
}

# Safety-net check: verify we are inside a multiplexer before bridge
# setup begins.  Normally _relaunch_in_tmux() will have handled this,
# but if the re-launch failed or was skipped this check catches it.
check_terminal_multiplexer() {
    # Only relevant when bridge networking will be reconfigured
    if [[ "${SKIP_BRIDGE}" == "true" ]]; then
        log_debug "Bridge setup skipped — multiplexer check not required"
        return "${EXIT_SUCCESS}"
    fi

    log_step "session" "Checking terminal multiplexer..."

    if _is_inside_multiplexer; then
        log_success "Running inside a terminal multiplexer"
        return "${EXIT_SUCCESS}"
    fi

    # Not inside a multiplexer — the auto-relaunch must have failed
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_warn "Not running inside a terminal multiplexer (tmux/screen)"
        log_warn "In a real run the script would auto-launch tmux"
        return "${EXIT_SUCCESS}"
    fi

    if [[ "${YES_MODE}" == "true" ]]; then
        log_warn "Not running inside a terminal multiplexer (tmux/screen)"
        log_warn "If the connection drops the bootstrap will continue in the background"
        log_warn "but interactive prompts (reboot, bridge) will be skipped."
        return "${EXIT_SUCCESS}"
    fi

    log_error "Not running inside a terminal multiplexer (tmux/screen)"
    log_error ""
    log_error "Automatic tmux launch failed.  Please start manually:"
    log_error "  tmux new-session -s bootstrap"
    log_error "  sudo ./gpu-vm-bootstrap.sh"
    log_error ""
    log_error "Or use --yes to continue without a multiplexer (non-interactive)."
    return "${EXIT_GENERAL_ERROR}"
}

# Run all pre-flight checks
run_preflight_checks() {
    log_phase "0" "Pre-flight Checks"

    log_step "os" "Checking operating system..."
    check_ubuntu_version

    log_step "root" "Checking privileges..."
    check_root

    check_network

    check_secure_boot

    check_terminal_multiplexer

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
# Phase 1: NVIDIA Driver & CUDA Setup
# =============================================================================

# Detect NVIDIA GPU hardware via lspci
detect_nvidia_gpu() {
    log_step "gpu" "Detecting NVIDIA GPU hardware..."

    if ! is_command_available lspci; then
        log_info "Installing pciutils for GPU detection..."
        if [[ "${DRY_RUN}" == "true" ]]; then
            log_dry_run "Would install pciutils"
        else
            ensure_pkg_installed pciutils
        fi
    fi

    local gpu_info
    gpu_info="$(lspci -nn 2>/dev/null | grep -i 'nvidia' || true)"

    if [[ -z "${gpu_info}" ]]; then
        log_error "No NVIDIA GPU detected"
        log_error "This script requires an NVIDIA GPU for driver installation"
        return "${EXIT_MISSING_DEPS}"
    fi

    # Extract PCI IDs (vendor:device) for all NVIDIA devices
    local gpu_count
    gpu_count="$(echo "${gpu_info}" | wc -l)"

    log_success "Detected ${gpu_count} NVIDIA device(s):"
    while IFS= read -r line; do
        log_info "  ${line}"
    done <<< "${gpu_info}"

    # Extract the PCI slot address of the first GPU (for VFIO later)
    NVIDIA_GPU_PCI_SLOT="$(echo "${gpu_info}" | head -1 | awk '{print $1}')"
    export NVIDIA_GPU_PCI_SLOT

    # Extract vendor:device ID pair (e.g. 10de:20f1)
    NVIDIA_GPU_PCI_ID="$(echo "${gpu_info}" | head -1 | sed -n 's/.*\[\([0-9a-f]\{4\}:[0-9a-f]\{4\}\)\].*/\1/p' | head -1 || true)"
    export NVIDIA_GPU_PCI_ID

    log_debug "GPU PCI slot: ${NVIDIA_GPU_PCI_SLOT}"
    log_debug "GPU PCI ID: ${NVIDIA_GPU_PCI_ID:-unknown}"

    return "${EXIT_SUCCESS}"
}

# Add the official NVIDIA CUDA repository
add_nvidia_repository() {
    log_step "repo" "Configuring NVIDIA CUDA repository..."

    local keyring_path="/usr/share/keyrings/cuda-archive-keyring.gpg"
    local sources_list="/etc/apt/sources.list.d/cuda-ubuntu2404-x86_64.list"
    local pin_file="/etc/apt/preferences.d/cuda-repository-pin-600"

    # Check if repository is already configured
    if [[ -f "${keyring_path}" && -f "${sources_list}" ]]; then
        log_debug "NVIDIA CUDA repository already configured"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "Would add NVIDIA CUDA repository"
        log_dry_run "Would download keyring to ${keyring_path}"
        log_dry_run "Would configure apt sources"
        return 0
    fi

    # Download and install the CUDA keyring package
    local keyring_deb="cuda-keyring_1.1-1_all.deb"
    local keyring_url="https://developer.download.nvidia.com/compute/cuda/repos/ubuntu2404/x86_64/${keyring_deb}"

    log_info "Downloading NVIDIA CUDA keyring..."
    local tmp_deb
    tmp_deb="$(mktemp /tmp/cuda-keyring-XXXXXX.deb)"

    if ! curl -fsSL "${keyring_url}" -o "${tmp_deb}"; then
        log_error "Failed to download NVIDIA CUDA keyring from ${keyring_url}"
        rm -f "${tmp_deb}"
        return "${EXIT_GENERAL_ERROR}"
    fi

    log_info "Installing NVIDIA CUDA keyring..."
    if ! dpkg -i "${tmp_deb}" >> "${LOG_FILE}" 2>&1; then
        log_error "Failed to install NVIDIA CUDA keyring"
        rm -f "${tmp_deb}"
        return "${EXIT_GENERAL_ERROR}"
    fi

    rm -f "${tmp_deb}"

    # Update package lists with new repository
    log_info "Updating package lists..."
    apt-get update -qq >> "${LOG_FILE}" 2>&1

    log_success "NVIDIA CUDA repository configured"
    return 0
}

# Ensure kernel headers are installed for the running kernel
# DKMS requires these to build kernel modules (NVIDIA, VFIO, etc.)
ensure_kernel_headers() {
    log_step "headers" "Ensuring kernel headers are installed..."

    local kernel_version
    kernel_version="$(uname -r)"
    local headers_pkg="linux-headers-${kernel_version}"

    if is_pkg_installed "${headers_pkg}"; then
        log_debug "Kernel headers already installed: ${headers_pkg}"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "Would install ${headers_pkg}"
        return 0
    fi

    log_info "Installing kernel headers for ${kernel_version}..."
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${headers_pkg}" >> "${LOG_FILE}" 2>&1; then
        log_error "Failed to install ${headers_pkg}"
        log_error "DKMS cannot build kernel modules without matching headers"
        return "${EXIT_GENERAL_ERROR}"
    fi

    log_success "Kernel headers installed: ${headers_pkg}"
    return 0
}

# Install NVIDIA drivers from the official repository
install_nvidia_drivers() {
    log_step "driver" "Installing NVIDIA drivers..."

    # Check if NVIDIA driver is already installed and functional
    if is_command_available nvidia-smi; then
        local existing_version
        existing_version="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || true)"
        if [[ -n "${existing_version}" ]]; then
            log_success "NVIDIA driver already installed (v${existing_version})"
            return 0
        fi
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "Would install NVIDIA driver package (cuda-drivers)"
        return 0
    fi

    # Install the NVIDIA driver meta-package
    # cuda-drivers pulls the latest compatible driver for the GPU
    log_info "Installing NVIDIA drivers (this may take several minutes)..."
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -qq cuda-drivers >> "${LOG_FILE}" 2>&1; then
        log_error "Failed to install NVIDIA drivers"
        log_error "Check ${LOG_FILE} for details"
        return "${EXIT_GENERAL_ERROR}"
    fi

    log_success "NVIDIA drivers installed"
    return 0
}

# Install the CUDA toolkit
install_cuda_toolkit() {
    log_step "cuda" "Installing CUDA toolkit..."

    # Check if CUDA is already installed
    if is_command_available nvcc; then
        local cuda_version
        cuda_version="$(nvcc --version 2>/dev/null | sed -n 's/.*release \([0-9]\{1,\}\.[0-9]\{1,\}\).*/\1/p' || true)"
        if [[ -n "${cuda_version}" ]]; then
            log_success "CUDA toolkit already installed (v${cuda_version})"
            return 0
        fi
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "Would install CUDA toolkit (cuda-toolkit)"
        return 0
    fi

    log_info "Installing CUDA toolkit (this may take several minutes)..."
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -qq cuda-toolkit >> "${LOG_FILE}" 2>&1; then
        log_error "Failed to install CUDA toolkit"
        log_error "Check ${LOG_FILE} for details"
        return "${EXIT_GENERAL_ERROR}"
    fi

    # Add CUDA to PATH if not already present
    local cuda_profile="/etc/profile.d/cuda.sh"
    if [[ ! -f "${cuda_profile}" ]]; then
        log_info "Configuring CUDA environment variables..."
        cat > "${cuda_profile}" << 'CUDA_ENV'
# CUDA toolkit environment configuration
# Added by gpu-vm-bootstrap
if [ -d /usr/local/cuda/bin ]; then
    export PATH="/usr/local/cuda/bin${PATH:+:${PATH}}"
fi
if [ -d /usr/local/cuda/lib64 ]; then
    export LD_LIBRARY_PATH="/usr/local/cuda/lib64${LD_LIBRARY_PATH:+:${LD_LIBRARY_PATH}}"
fi
CUDA_ENV
        chmod 644 "${cuda_profile}"
        log_debug "Created ${cuda_profile}"
    fi

    log_success "CUDA toolkit installed"
    return 0
}

# Install nvidia-container-toolkit for containerised GPU workloads
install_nvidia_container_toolkit() {
    log_step "container" "Installing nvidia-container-toolkit..."

    # Check if already installed
    if is_command_available nvidia-ctk; then
        log_success "nvidia-container-toolkit already installed"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "Would add NVIDIA container toolkit repository"
        log_dry_run "Would install nvidia-container-toolkit"
        return 0
    fi

    local nct_keyring="/usr/share/keyrings/nvidia-container-toolkit-keyring.gpg"
    local nct_sources="/etc/apt/sources.list.d/nvidia-container-toolkit.list"

    # Add the NVIDIA container toolkit repository if not present
    if [[ ! -f "${nct_keyring}" || ! -f "${nct_sources}" ]]; then
        log_info "Adding NVIDIA container toolkit repository..."

        curl -fsSL https://nvidia.github.io/libnvidia-container/gpgkey \
            | gpg --dearmor -o "${nct_keyring}" 2>/dev/null

        curl -fsSL https://nvidia.github.io/libnvidia-container/stable/deb/nvidia-container-toolkit.list \
            | sed "s#deb https://#deb [signed-by=${nct_keyring}] https://#g" \
            > "${nct_sources}"

        apt-get update -qq >> "${LOG_FILE}" 2>&1
    fi

    log_info "Installing nvidia-container-toolkit..."
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -qq nvidia-container-toolkit >> "${LOG_FILE}" 2>&1; then
        log_error "Failed to install nvidia-container-toolkit"
        log_error "Check ${LOG_FILE} for details"
        return "${EXIT_GENERAL_ERROR}"
    fi

    log_success "nvidia-container-toolkit installed"
    return 0
}

# Verify that the NVIDIA setup is functional
verify_nvidia_setup() {
    log_step "verify" "Verifying NVIDIA setup..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "Would verify NVIDIA setup via nvidia-smi"
        return 0
    fi

    # Verify nvidia-smi is available and responds
    if ! is_command_available nvidia-smi; then
        log_warn "nvidia-smi not found in PATH"
        log_warn "A reboot may be required to load the NVIDIA kernel modules"
        NVIDIA_REBOOT_REQUIRED=true
        export NVIDIA_REBOOT_REQUIRED
        return 0
    fi

    if nvidia-smi &>/dev/null; then
        log_success "nvidia-smi reports healthy GPU status"

        # Log GPU details
        local gpu_name
        gpu_name="$(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1 || true)"
        local driver_version
        driver_version="$(nvidia-smi --query-gpu=driver_version --format=csv,noheader 2>/dev/null | head -1 || true)"
        local cuda_version
        cuda_version="$(nvidia-smi --query-gpu=compute_cap --format=csv,noheader 2>/dev/null | head -1 || true)"

        log_info "GPU: ${gpu_name:-unknown}"
        log_info "Driver: ${driver_version:-unknown}"
        log_info "Compute capability: ${cuda_version:-unknown}"
    else
        log_warn "nvidia-smi failed — a reboot may be required to load NVIDIA kernel modules"
        NVIDIA_REBOOT_REQUIRED=true
        export NVIDIA_REBOOT_REQUIRED
    fi

    return 0
}

# Phase 1 orchestrator: NVIDIA driver & CUDA setup
phase_nvidia_setup() {
    NVIDIA_REBOOT_REQUIRED=false

    detect_nvidia_gpu || return $?
    add_nvidia_repository || return $?
    ensure_kernel_headers || return $?
    install_nvidia_drivers || return $?
    install_cuda_toolkit || return $?
    install_nvidia_container_toolkit || return $?
    verify_nvidia_setup || return $?

    if [[ "${NVIDIA_REBOOT_REQUIRED}" == "true" ]]; then
        REBOOT_REQUIRED=true
        log_warn "A reboot is required to complete NVIDIA setup"
    fi

    return 0
}

# =============================================================================
# Phase 2: KVM/libvirt Setup
# =============================================================================

# KVM/QEMU required packages
readonly KVM_PACKAGES=(
    qemu-kvm
    qemu-utils
    libvirt-daemon-system
    libvirt-clients
    virtinst
    virt-manager
    ovmf
    cpu-checker
    bridge-utils
)

# Install KVM/QEMU virtualisation packages
install_kvm_packages() {
    log_step "packages" "Installing KVM/QEMU packages..."

    local all_installed=true
    for pkg in "${KVM_PACKAGES[@]}"; do
        if ! is_pkg_installed "${pkg}"; then
            all_installed=false
            break
        fi
    done

    if [[ "${all_installed}" == "true" ]]; then
        log_success "All KVM/QEMU packages already installed"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "Would install packages: ${KVM_PACKAGES[*]}"
        return 0
    fi

    log_info "Updating package lists..."
    apt-get update -qq >> "${LOG_FILE}" 2>&1

    log_info "Installing KVM/QEMU packages..."
    if ! DEBIAN_FRONTEND=noninteractive apt-get install -y -qq "${KVM_PACKAGES[@]}" >> "${LOG_FILE}" 2>&1; then
        log_error "Failed to install KVM/QEMU packages"
        log_error "Check ${LOG_FILE} for details"
        return "${EXIT_GENERAL_ERROR}"
    fi

    log_success "KVM/QEMU packages installed"
    return 0
}

# Configure the libvirtd service and user permissions
configure_libvirtd() {
    log_step "libvirtd" "Configuring libvirt daemon..."

    # Enable and start libvirtd
    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "Would enable and start libvirtd"
        log_dry_run "Would add current user to libvirt and kvm groups"
        return 0
    fi

    ensure_service_running "libvirtd"

    # Add the invoking user (SUDO_USER) to libvirt and kvm groups
    local target_user="${SUDO_USER:-}"

    if [[ -n "${target_user}" && "${target_user}" != "root" ]]; then
        local groups_changed=false

        if ! id -nG "${target_user}" 2>/dev/null | grep -qw "libvirt"; then
            log_info "Adding user '${target_user}' to group 'libvirt'..."
            usermod -aG libvirt "${target_user}"
            groups_changed=true
        fi

        if ! id -nG "${target_user}" 2>/dev/null | grep -qw "kvm"; then
            log_info "Adding user '${target_user}' to group 'kvm'..."
            usermod -aG kvm "${target_user}"
            groups_changed=true
        fi

        if [[ "${groups_changed}" == "true" ]]; then
            log_success "User '${target_user}' added to libvirt/kvm groups"
            log_info "Group changes take effect on next login"
        else
            log_debug "User '${target_user}' already in libvirt/kvm groups"
        fi
    else
        log_debug "Running as root without SUDO_USER — skipping group configuration"
    fi

    # Configure libvirt default URI
    local libvirt_profile="/etc/profile.d/libvirt.sh"
    if [[ ! -f "${libvirt_profile}" ]]; then
        log_info "Setting default libvirt connection URI..."
        cat > "${libvirt_profile}" << 'LIBVIRT_ENV'
# Default libvirt connection URI
# Added by gpu-vm-bootstrap
export LIBVIRT_DEFAULT_URI="qemu:///system"
LIBVIRT_ENV
        chmod 644 "${libvirt_profile}"
        log_debug "Created ${libvirt_profile}"
    fi

    log_success "libvirt daemon configured"
    return 0
}

# Verify KVM readiness — check CPU virtualisation support and module loading
verify_kvm_readiness() {
    log_step "verify" "Verifying KVM readiness..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "Would verify KVM readiness via kvm-ok and module checks"
        return 0
    fi

    # Check hardware virtualisation support via kvm-ok
    if is_command_available kvm-ok; then
        if kvm-ok >> "${LOG_FILE}" 2>&1; then
            log_success "Hardware virtualisation support confirmed (kvm-ok)"
        else
            log_warn "kvm-ok reports issues — check BIOS/UEFI virtualisation settings"
            log_warn "Ensure Intel VT-x or AMD-V is enabled"
        fi
    else
        log_debug "kvm-ok not available — checking modules directly"
    fi

    # Check that KVM kernel module is loaded
    if is_module_loaded kvm; then
        log_success "KVM kernel module loaded"

        # Check for vendor-specific module
        if is_module_loaded kvm_intel; then
            log_info "KVM Intel module loaded (VT-x)"
        elif is_module_loaded kvm_amd; then
            log_info "KVM AMD module loaded (AMD-V)"
        else
            log_debug "No vendor-specific KVM module detected"
        fi
    else
        log_warn "KVM kernel module not loaded"
        log_warn "Check that virtualisation is enabled in BIOS/UEFI"
    fi

    # Check /dev/kvm exists and is accessible
    if [[ -c /dev/kvm ]]; then
        log_success "/dev/kvm is available"
    else
        log_warn "/dev/kvm not found — KVM acceleration will not be available"
    fi

    # Verify libvirtd is running
    if is_service_active libvirtd; then
        log_success "libvirtd service is active"
    else
        log_warn "libvirtd service is not running"
    fi

    # Verify virsh can connect
    if is_command_available virsh; then
        if virsh -c qemu:///system version >> "${LOG_FILE}" 2>&1; then
            log_success "virsh can connect to QEMU/KVM"
        else
            log_warn "virsh cannot connect to QEMU/KVM — check libvirtd"
        fi
    fi

    return 0
}

# Phase 2 orchestrator: KVM/libvirt setup
phase_kvm_setup() {
    install_kvm_packages || return $?
    configure_libvirtd || return $?
    verify_kvm_readiness || return $?

    return 0
}

# =============================================================================
# Phase 3: IOMMU/VFIO Configuration
# =============================================================================

# Detect CPU vendor for correct IOMMU parameter
detect_cpu_vendor() {
    log_step "cpu" "Detecting CPU vendor..."

    local vendor_id
    vendor_id="$(grep -m1 'vendor_id' /proc/cpuinfo 2>/dev/null | awk '{print $NF}' || true)"

    case "${vendor_id}" in
        GenuineIntel)
            CPU_VENDOR="intel"
            IOMMU_PARAM="intel_iommu=on"
            log_success "Intel CPU detected"
            ;;
        AuthenticAMD)
            CPU_VENDOR="amd"
            IOMMU_PARAM="amd_iommu=on"
            log_success "AMD CPU detected"
            ;;
        *)
            log_error "Unknown CPU vendor: '${vendor_id:-empty}'"
            log_error "Cannot determine correct IOMMU parameter"
            return "${EXIT_GENERAL_ERROR}"
            ;;
    esac

    export CPU_VENDOR
    export IOMMU_PARAM

    return 0
}

# Configure GRUB with IOMMU kernel parameters
configure_grub_iommu() {
    log_step "grub" "Configuring GRUB for IOMMU..."

    local grub_file="${GRUB_DEFAULT_FILE:-/etc/default/grub}"
    local iommu_params="${IOMMU_PARAM} iommu=pt"

    # Check if already configured
    local all_set=true
    for param in ${iommu_params}; do
        if ! is_grub_param_set "${param}"; then
            all_set=false
            break
        fi
    done

    if [[ "${all_set}" == "true" ]]; then
        log_success "GRUB IOMMU parameters already configured"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "Would add to GRUB_CMDLINE_LINUX_DEFAULT: ${iommu_params}"
        log_dry_run "Would run update-grub"
        return 0
    fi

    if [[ ! -f "${grub_file}" ]]; then
        log_error "GRUB configuration file not found: ${grub_file}"
        return "${EXIT_GENERAL_ERROR}"
    fi

    # Back up current GRUB config
    cp "${grub_file}" "${grub_file}.bak.$(date +%Y%m%d%H%M%S)"
    log_debug "Backed up ${grub_file}"

    # Read current GRUB_CMDLINE_LINUX_DEFAULT value
    local current_line
    current_line="$(grep '^GRUB_CMDLINE_LINUX_DEFAULT=' "${grub_file}" || true)"

    if [[ -z "${current_line}" ]]; then
        # No existing line — add one
        echo "GRUB_CMDLINE_LINUX_DEFAULT=\"${iommu_params}\"" >> "${grub_file}"
    else
        # Extract current value (strip quotes and prefix)
        local current_value="${current_line#GRUB_CMDLINE_LINUX_DEFAULT=\"}"
        current_value="${current_value%\"}"

        # Append missing parameters
        local new_value="${current_value}"
        for param in ${iommu_params}; do
            if [[ "${new_value}" != *"${param}"* ]]; then
                new_value="${new_value} ${param}"
            fi
        done

        # Trim leading/trailing whitespace
        new_value="$(echo "${new_value}" | sed 's/^[[:space:]]*//;s/[[:space:]]*$//')"

        # Replace the line in grub file
        sed -i "s|^GRUB_CMDLINE_LINUX_DEFAULT=.*|GRUB_CMDLINE_LINUX_DEFAULT=\"${new_value}\"|" "${grub_file}"
    fi

    log_success "GRUB IOMMU parameters configured: ${iommu_params}"

    # Update GRUB
    log_info "Running update-grub..."
    if ! update-grub >> "${LOG_FILE}" 2>&1; then
        log_error "update-grub failed"
        return "${EXIT_GENERAL_ERROR}"
    fi

    log_success "GRUB updated"
    VFIO_REBOOT_REQUIRED=true
    return 0
}

# Configure VFIO kernel modules
configure_vfio_modules() {
    log_step "vfio" "Configuring VFIO kernel modules..."

    local modules_file="/etc/modules"
    local modprobe_conf="/etc/modprobe.d/vfio.conf"

    local vfio_modules=(vfio vfio_iommu_type1 vfio_pci)

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "Would add VFIO modules to ${modules_file}"
        if [[ "${GPU_MODE}" == "exclusive" && -n "${NVIDIA_GPU_PCI_ID:-}" ]]; then
            log_dry_run "Would configure VFIO PCI IDs in ${modprobe_conf}"
        fi
        log_dry_run "Would run update-initramfs -u"
        return 0
    fi

    # Add VFIO modules to /etc/modules for auto-loading at boot
    local modules_changed=false
    for mod in "${vfio_modules[@]}"; do
        if ! is_line_in_file "${modules_file}" "${mod}"; then
            echo "${mod}" >> "${modules_file}"
            modules_changed=true
            log_debug "Added ${mod} to ${modules_file}"
        fi
    done

    if [[ "${modules_changed}" == "true" ]]; then
        log_success "VFIO modules added to ${modules_file}"
    else
        log_debug "VFIO modules already in ${modules_file}"
    fi

    # In exclusive GPU mode, configure VFIO to claim the GPU at boot
    if [[ "${GPU_MODE}" == "exclusive" && -n "${NVIDIA_GPU_PCI_ID:-}" ]]; then
        log_info "Configuring exclusive GPU mode — VFIO will claim GPU at boot"

        # Create modprobe config for VFIO PCI
        if [[ ! -f "${modprobe_conf}" ]] || ! grep -q "${NVIDIA_GPU_PCI_ID}" "${modprobe_conf}" 2>/dev/null; then
            cat > "${modprobe_conf}" << EOF
# VFIO PCI configuration for GPU passthrough
# Added by gpu-vm-bootstrap (exclusive mode)
# GPU PCI ID: ${NVIDIA_GPU_PCI_ID}
options vfio-pci ids=${NVIDIA_GPU_PCI_ID}
softdep nvidia pre: vfio-pci
EOF
            log_success "VFIO PCI configuration created: ${modprobe_conf}"
        else
            log_debug "VFIO PCI configuration already contains GPU ID"
        fi
    elif [[ "${GPU_MODE}" == "flexible" ]]; then
        log_info "Flexible GPU mode — VFIO bind/unbind managed by vmctl on demand"
    fi

    # Update initramfs to include VFIO modules
    log_info "Updating initramfs..."
    if ! update-initramfs -u >> "${LOG_FILE}" 2>&1; then
        log_warn "update-initramfs failed — VFIO modules may not load at next boot"
    else
        log_success "initramfs updated"
    fi

    VFIO_REBOOT_REQUIRED=true
    return 0
}

# Detect IOMMU groups for GPU isolation verification
detect_iommu_groups() {
    log_step "iommu" "Detecting IOMMU groups..."

    local iommu_base="/sys/kernel/iommu_groups"

    if [[ ! -d "${iommu_base}" ]] || [[ -z "$(ls -A "${iommu_base}" 2>/dev/null)" ]]; then
        if [[ "${VFIO_REBOOT_REQUIRED:-false}" == "true" ]]; then
            log_info "IOMMU groups not yet available — will be populated after reboot"
        else
            log_warn "No IOMMU groups found — IOMMU may not be enabled"
            log_warn "Check BIOS/UEFI settings for VT-d (Intel) or AMD-Vi (AMD)"
        fi
        return 0
    fi

    # Count IOMMU groups
    local group_count
    group_count="$(find "${iommu_base}" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)"
    log_success "Found ${group_count} IOMMU group(s)"

    # Find NVIDIA GPU IOMMU group if we know the PCI slot
    if [[ -n "${NVIDIA_GPU_PCI_SLOT:-}" ]]; then
        local gpu_iommu_group=""
        local gpu_sysfs="/sys/bus/pci/devices/0000:${NVIDIA_GPU_PCI_SLOT}"

        if [[ -L "${gpu_sysfs}/iommu_group" ]]; then
            gpu_iommu_group="$(basename "$(readlink "${gpu_sysfs}/iommu_group")")"
            log_info "NVIDIA GPU (${NVIDIA_GPU_PCI_SLOT}) in IOMMU group ${gpu_iommu_group}"

            # List all devices in the same group
            local group_dir="${iommu_base}/${gpu_iommu_group}/devices"
            if [[ -d "${group_dir}" ]]; then
                local device_count
                device_count="$(find "${group_dir}" -maxdepth 1 -mindepth 1 2>/dev/null | wc -l)"
                log_debug "IOMMU group ${gpu_iommu_group} contains ${device_count} device(s)"

                if [[ "${device_count}" -gt 2 ]]; then
                    log_warn "GPU IOMMU group contains ${device_count} devices"
                    log_warn "For clean passthrough, the GPU should ideally be in its own group"
                    log_info "Consider ACS override patch if grouping is too broad"
                fi
            fi
        else
            log_debug "GPU sysfs path not found or no IOMMU group link"
        fi
    fi

    return 0
}

# Handle reboot requirement
handle_vfio_reboot() {
    if [[ "${VFIO_REBOOT_REQUIRED:-false}" != "true" ]]; then
        return 0
    fi

    REBOOT_REQUIRED=true
    log_warn "A reboot is required to activate IOMMU and load VFIO modules"

    return 0
}

# Phase 3 orchestrator: IOMMU/VFIO configuration
phase_vfio_setup() {
    VFIO_REBOOT_REQUIRED=false

    detect_cpu_vendor || return $?
    configure_grub_iommu || return $?
    configure_vfio_modules || return $?
    detect_iommu_groups || return $?
    handle_vfio_reboot

    return 0
}

# =============================================================================
# Phase 4: Bridge Network Setup
# =============================================================================

# Detect the primary network interface (the one with the default route)
detect_primary_nic() {
    log_step "bridge" "Detecting primary network interface..."

    local nic=""
    # Use ip route to find the interface carrying the default route
    nic="$(ip route show default 2>/dev/null | sed -n 's/.*dev \([^ ]*\).*/\1/p' | head -n1)"

    if [[ -z "${nic}" ]]; then
        log_error "Could not detect primary network interface — no default route found"
        return "${EXIT_GENERAL_ERROR}"
    fi

    export PRIMARY_NIC="${nic}"
    log_success "Primary NIC detected: ${PRIMARY_NIC}"

    # Gather current IP configuration for migration
    local ip_addr=""
    ip_addr="$(ip -4 addr show dev "${PRIMARY_NIC}" 2>/dev/null \
        | sed -n 's/.*inet \([0-9./]*\).*/\1/p' | head -n1)"

    if [[ -n "${ip_addr}" ]]; then
        export PRIMARY_NIC_IP="${ip_addr}"
        log_info "Current IP: ${PRIMARY_NIC_IP}"
    else
        export PRIMARY_NIC_IP=""
        log_warn "No IPv4 address found on ${PRIMARY_NIC}"
    fi

    # Detect current gateway
    local gateway=""
    gateway="$(ip route show default 2>/dev/null | sed -n 's/.*via \([0-9.]*\).*/\1/p' | head -n1)"

    if [[ -n "${gateway}" ]]; then
        export PRIMARY_NIC_GATEWAY="${gateway}"
        log_info "Gateway: ${PRIMARY_NIC_GATEWAY}"
    else
        export PRIMARY_NIC_GATEWAY=""
        log_warn "No default gateway detected"
    fi

    # Detect /32 direct-route mode (point-to-point hosting providers)
    # In this mode the host has a /32 address with an on-link default route
    # to a gateway outside its subnet — common with dedicated server providers
    export DIRECT_ROUTE_MODE=false
    local default_route=""
    default_route="$(ip route show default 2>/dev/null | head -n1)"
    if [[ -n "${PRIMARY_NIC_IP}" ]] && echo "${PRIMARY_NIC_IP}" | grep -q '/32'; then
        if echo "${default_route}" | grep -q 'onlink'; then
            export DIRECT_ROUTE_MODE=true
            log_info "Detected /32 direct-route mode (point-to-point)"
        fi
    fi

    # Detect DNS servers from systemd-resolved or resolv.conf
    local dns_servers=""
    if command -v resolvectl &>/dev/null; then
        # Extract only IPv4 DNS addresses; resolvectl output contains IPv6
        # addresses with colons that interfere with naive sed parsing
        dns_servers="$(resolvectl dns "${PRIMARY_NIC}" 2>/dev/null \
            | sed 's/^[^)]*): *//' \
            | grep -oE '[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' \
            | tr '\n' ',' | sed 's/,$//')"
    fi
    if [[ -z "${dns_servers}" ]] && [[ -f "/etc/resolv.conf" ]]; then
        dns_servers="$(sed -n 's/^nameserver \([0-9.]*\)/\1/p' /etc/resolv.conf \
            | head -n3 | tr '\n' ',' | sed 's/,$//')"
    fi

    export PRIMARY_NIC_DNS="${dns_servers:-}"
    if [[ -n "${PRIMARY_NIC_DNS}" ]]; then
        log_info "DNS servers: ${PRIMARY_NIC_DNS}"
    fi

    return 0
}

# Build a DNS nameservers YAML fragment from comma-separated DNS addresses
_build_dns_section() {
    local dns_csv="$1"
    local indent="$2"

    if [[ -z "${dns_csv}" ]]; then
        return 0
    fi

    local dns_yaml=""
    IFS=',' read -ra dns_arr <<< "${dns_csv}"
    for dns in "${dns_arr[@]}"; do
        dns="${dns// /}"
        if [[ -n "${dns}" ]]; then
            dns_yaml="${dns_yaml}${dns_yaml:+, }${dns}"
        fi
    done

    if [[ -n "${dns_yaml}" ]]; then
        echo "${indent}nameservers:"
        echo "${indent}  addresses: [${dns_yaml}]"
    fi
}

# Generate Netplan YAML for /32 direct-route mode (point-to-point providers)
# In this mode the host IP is /32, the gateway is reached via an on-link route,
# and the bridge must preserve this routing topology.
_generate_direct_route_bridge_config() {
    local netplan_file="$1"
    local dns_block=""
    dns_block="$(_build_dns_section "${PRIMARY_NIC_DNS:-}" "      ")"

    cat > "${netplan_file}" << EOF
# Bridge network configuration for GPU VM host
# Generated by gpu-vm-bootstrap
# Mode: /32 direct-route (point-to-point)
# Primary NIC: ${PRIMARY_NIC} → Bridge: ${BRIDGE_NAME}
network:
  version: 2
  renderer: networkd
  ethernets:
    ${PRIMARY_NIC}:
      dhcp4: false
      dhcp6: false
  bridges:
    ${BRIDGE_NAME}:
      interfaces: [${PRIMARY_NIC}]
      addresses: [${PRIMARY_NIC_IP}]
      routes:
        - on-link: true
          to: 0.0.0.0/0
          via: ${PRIMARY_NIC_GATEWAY}
${dns_block:+${dns_block}
}      parameters:
        stp: false
        forward-delay: 0
EOF
}

# Generate Netplan YAML for standard subnet mode (e.g. /24)
_generate_standard_bridge_config() {
    local netplan_file="$1"

    # Determine addressing mode
    local addressing="dhcp4: true"
    if [[ -n "${PRIMARY_NIC_IP:-}" ]]; then
        addressing="addresses: [${PRIMARY_NIC_IP}]"
    fi

    # Build routes section
    local routes_section=""
    if [[ -n "${PRIMARY_NIC_GATEWAY:-}" ]]; then
        routes_section="      routes:
        - to: default
          via: ${PRIMARY_NIC_GATEWAY}"
    fi

    # Build DNS section
    local dns_block=""
    dns_block="$(_build_dns_section "${PRIMARY_NIC_DNS:-}" "      ")"

    cat > "${netplan_file}" << EOF
# Bridge network configuration for GPU VM host
# Generated by gpu-vm-bootstrap
# Mode: standard subnet
# Primary NIC: ${PRIMARY_NIC} → Bridge: ${BRIDGE_NAME}
network:
  version: 2
  renderer: networkd
  ethernets:
    ${PRIMARY_NIC}:
      dhcp4: false
      dhcp6: false
  bridges:
    ${BRIDGE_NAME}:
      interfaces: [${PRIMARY_NIC}]
      ${addressing}
${routes_section:+${routes_section}
}${dns_block:+${dns_block}
}      parameters:
        stp: true
        forward-delay: 4
EOF
}

# Create a Netplan bridge configuration that migrates the host IP to the bridge
configure_bridge_interface() {
    log_step "bridge" "Configuring bridge interface: ${BRIDGE_NAME}..."

    if [[ -z "${PRIMARY_NIC:-}" ]]; then
        log_error "Primary NIC not detected — run detect_primary_nic first"
        return "${EXIT_GENERAL_ERROR}"
    fi

    local netplan_dir="${NETPLAN_DIR:-/etc/netplan}"
    local netplan_file="${netplan_dir}/60-bridge-${BRIDGE_NAME}.yaml"

    # Skip if Netplan config already exists and contains the bridge
    if [[ -f "${netplan_file}" ]] && grep -q "${BRIDGE_NAME}" "${netplan_file}" 2>/dev/null; then
        log_debug "Bridge Netplan config already exists: ${netplan_file}"
        return 0
    fi

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "Would create Netplan bridge config: ${netplan_file}"
        log_dry_run "Would bridge NIC ${PRIMARY_NIC} into ${BRIDGE_NAME}"
        if [[ -n "${PRIMARY_NIC_IP:-}" ]]; then
            log_dry_run "Would assign IP ${PRIMARY_NIC_IP} to ${BRIDGE_NAME}"
        fi
        if [[ "${DIRECT_ROUTE_MODE:-false}" == "true" ]]; then
            log_dry_run "Would use /32 direct-route mode (on-link gateway)"
        fi
        return 0
    fi

    # Back up existing Netplan configs
    local backup_dir=""
    backup_dir="${netplan_dir}/backup-$(date +%Y%m%d%H%M%S)"
    mkdir -p "${backup_dir}"
    local backed_up=false
    for f in "${netplan_dir}"/*.yaml; do
        if [[ -f "${f}" ]]; then
            cp "${f}" "${backup_dir}/"
            backed_up=true
        fi
    done
    if [[ "${backed_up}" == "true" ]]; then
        log_info "Existing Netplan configs backed up to: ${backup_dir}"
    fi

    # Generate the appropriate Netplan config based on detected routing mode
    if [[ "${DIRECT_ROUTE_MODE:-false}" == "true" ]]; then
        log_info "Using /32 direct-route bridge configuration"
        _generate_direct_route_bridge_config "${netplan_file}"
    else
        log_info "Using standard subnet bridge configuration"
        _generate_standard_bridge_config "${netplan_file}"
    fi

    # Netplan files must be readable only by root
    chmod 600 "${netplan_file}"
    log_success "Created Netplan bridge config: ${netplan_file}"

    return 0
}

# Apply the Netplan configuration to activate the bridge
#
# Uses 'netplan try --timeout 120' for a safe roll-out: if the new
# configuration breaks connectivity the previous state is automatically
# restored after 120 seconds.  After connectivity is verified we
# confirm with 'netplan apply'.
apply_bridge_config() {
    log_step "bridge" "Applying bridge configuration..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "Would run 'netplan try --timeout 120' to activate bridge"
        log_dry_run "Would confirm with 'netplan apply' after connectivity check"
        return 0
    fi

    log_warn "Applying bridge config — brief network interruption expected"
    log_info "Using 'netplan try' — automatic rollback after 120 s if connectivity fails"

    if ! netplan try --timeout 120 >> "${LOG_FILE}" 2>&1; then
        log_error "netplan try failed — previous configuration has been restored"
        log_error "Check ${LOG_FILE} for details"
        return "${EXIT_GENERAL_ERROR}"
    fi

    # netplan try succeeded; confirm permanently
    if ! netplan apply >> "${LOG_FILE}" 2>&1; then
        log_error "netplan apply (confirm) failed — check ${LOG_FILE} for details"
        log_warn "Network state may be inconsistent; review manually"
        return "${EXIT_GENERAL_ERROR}"
    fi

    log_success "Bridge configuration applied and confirmed"
    return 0
}

# Verify bridge is operational and network connectivity is intact
verify_bridge_connectivity() {
    log_step "bridge" "Verifying bridge connectivity..."

    if [[ "${DRY_RUN}" == "true" ]]; then
        log_dry_run "Would verify bridge ${BRIDGE_NAME} is operational"
        log_dry_run "Would verify network connectivity"
        return 0
    fi

    # Check bridge interface exists
    if ! ip link show "${BRIDGE_NAME}" &>/dev/null; then
        log_error "Bridge interface ${BRIDGE_NAME} does not exist"
        return "${EXIT_GENERAL_ERROR}"
    fi

    # Check bridge is in UP state
    local bridge_state=""
    bridge_state="$(ip -br link show "${BRIDGE_NAME}" 2>/dev/null | awk '{print $2}')"
    if [[ "${bridge_state}" != "UP" ]]; then
        log_warn "Bridge ${BRIDGE_NAME} is in state: ${bridge_state:-UNKNOWN}"
    else
        log_success "Bridge ${BRIDGE_NAME} is UP"
    fi

    # Check bridge has an IP address
    local bridge_ip=""
    bridge_ip="$(ip -4 addr show dev "${BRIDGE_NAME}" 2>/dev/null \
        | sed -n 's/.*inet \([0-9./]*\).*/\1/p' | head -n1)"

    if [[ -n "${bridge_ip}" ]]; then
        log_success "Bridge IP: ${bridge_ip}"
    else
        log_warn "Bridge ${BRIDGE_NAME} has no IPv4 address yet"
    fi

    # Check bridge has members
    local member_count=0
    if command -v bridge &>/dev/null; then
        member_count="$(bridge link show master "${BRIDGE_NAME}" 2>/dev/null | wc -l)"
    fi
    log_info "Bridge members: ${member_count}"

    # Verify default route goes through the bridge
    local route_dev=""
    route_dev="$(ip route show default 2>/dev/null | sed -n 's/.*dev \([^ ]*\).*/\1/p' | head -n1)"
    if [[ "${route_dev}" == "${BRIDGE_NAME}" ]]; then
        log_success "Default route via ${BRIDGE_NAME}"
    else
        log_warn "Default route via ${route_dev:-UNKNOWN} (expected ${BRIDGE_NAME})"
    fi

    # Test network connectivity with a simple ping
    local gateway="${PRIMARY_NIC_GATEWAY:-}"
    if [[ -n "${gateway}" ]]; then
        if ping -c1 -W3 "${gateway}" &>/dev/null; then
            log_success "Gateway ${gateway} reachable"
        else
            log_warn "Cannot reach gateway ${gateway}"
        fi
    fi

    return 0
}

# Phase 4 orchestrator: Bridge network setup
phase_bridge_setup() {
    detect_primary_nic || return $?
    configure_bridge_interface || return $?
    apply_bridge_config || return $?
    verify_bridge_connectivity || return $?

    return 0
}

# =============================================================================
# Phase Stubs (to be implemented in subsequent phases)
# =============================================================================

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

# Prompt user interactively to reboot now or later
# Uses cursor-key selection: Yes / No (default: No)
# Falls back to a non-interactive message when stdin is not a terminal
# (e.g. piped input, dead SSH session, VS Code tunnel disconnect).
prompt_reboot() {
    if [[ "${REBOOT_REQUIRED}" != "true" ]]; then
        return 0
    fi

    # In non-interactive mode (--yes), auto-reboot if --reboot was also set
    if [[ "${YES_MODE}" == "true" ]]; then
        if [[ "${REBOOT_ALLOWED}" == "true" ]]; then
            log_info "Rebooting now (--yes --reboot)"
            _log_to_file "REBOOT" "Automatic reboot initiated"
            reboot
        else
            log_warn "Reboot required — run 'sudo reboot' when ready"
        fi
        return 0
    fi

    # In dry-run mode, just inform
    if [[ "${DRY_RUN}" == "true" ]]; then
        return 0
    fi

    # If stdin is not a terminal we cannot present an interactive menu
    if [[ ! -t 0 ]]; then
        log_warn "Reboot required to complete the setup"
        log_warn "Run 'sudo reboot' when ready"
        return 0
    fi

    echo "" >&2
    log_warn "A reboot is required to complete the setup"
    log_info "(NVIDIA kernel modules, IOMMU, VFIO)"
    echo "" >&2

    # Interactive selection with arrow keys
    local options=("Yes — reboot now" "No  — reboot later")
    local selected=1  # Default to "No"

    # Save cursor, hide it
    printf '\033[?25l' >&2

    # Draw menu
    _draw_reboot_menu() {
        # Move cursor up to redraw (except first draw)
        if [[ "${1:-}" == "redraw" ]]; then
            printf '\033[2A' >&2
        fi
        local i
        for i in 0 1; do
            if [[ $i -eq $selected ]]; then
                printf '  %b> %s%b\n' "${CLR_GREEN}" "${options[$i]}" "${CLR_RESET}" >&2
            else
                printf '    %s\n' "${options[$i]}" >&2
            fi
        done
    }

    _draw_reboot_menu

    # Read arrow keys and Enter
    while true; do
        local key=""
        IFS= read -rsn1 key
        if [[ "${key}" == $'\x1b' ]]; then
            read -rsn2 key
            case "${key}" in
                '[A') # Up arrow
                    selected=0
                    _draw_reboot_menu redraw
                    ;;
                '[B') # Down arrow
                    selected=1
                    _draw_reboot_menu redraw
                    ;;
            esac
        elif [[ "${key}" == "" ]]; then
            # Enter pressed
            break
        fi
    done

    # Restore cursor
    printf '\033[?25h' >&2

    if [[ $selected -eq 0 ]]; then
        log_info "Rebooting now..."
        _log_to_file "REBOOT" "User-initiated reboot"
        reboot
    else
        log_info "Reboot skipped — run 'sudo reboot' when ready"
    fi

    return 0
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

    # Auto-detect piped execution (e.g. curl | sudo bash) and imply --yes
    # Piped stdin is non-interactive, so all prompts must be skipped.
    if [[ ! -t 0 ]] && [[ "${YES_MODE}" != "true" ]]; then
        log_info "Piped execution detected — enabling non-interactive mode (--yes)"
        YES_MODE=true
    fi

    # Auto-launch inside tmux when bridge setup is enabled and no
    # multiplexer is detected.  Skipped in dry-run so previews work
    # without tmux.  The _relaunch_in_tmux function never returns — it
    # replaces the process with a tmux session.
    if [[ "${SKIP_BRIDGE}" != "true" ]] && [[ "${DRY_RUN}" != "true" ]] \
       && ! _is_inside_multiplexer; then
        _relaunch_in_tmux "$@"
    fi

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

    # Prompt for reboot if required by any phase
    prompt_reboot

    return "${EXIT_SUCCESS}"
}

# Only run main if script is executed directly (not sourced)
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
