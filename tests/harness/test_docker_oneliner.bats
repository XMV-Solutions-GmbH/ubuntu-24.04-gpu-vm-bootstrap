#!/usr/bin/env bats
# shellcheck disable=SC1090,SC2030,SC2031
# SPDX-License-Identifier: MIT OR Apache-2.0
# Harness tests for the one-liner install via Docker
# Spins up an Ubuntu 24.04 Docker container (optionally with GPU),
# downloads gpu-vm-bootstrap.sh from the latest GitHub release,
# and validates the install pipeline end-to-end.
#
# Prerequisites:
#   - Docker installed and running
#   - NVIDIA Container Toolkit installed (for GPU tests)
#   - Internet access (downloads from GitHub Releases)
#
# Usage:
#   bats tests/harness/test_docker_oneliner.bats
#   # or via Makefile:
#   make test-harness

load '../test_helper'

# =============================================================================
# Constants
# =============================================================================

REPO_URL="https://github.com/XMV-Solutions-GmbH/ubuntu-24.04-gpu-vm-bootstrap"
RELEASE_URL="${REPO_URL}/releases/latest/download/gpu-vm-bootstrap.sh"
DOCKER_IMAGE="ubuntu:24.04"
CONTAINER_PREFIX="bootstrap-harness"

# Set HARNESS_VERBOSE=true to stream Docker output to the terminal in real time.
# Usage: HARNESS_VERBOSE=true bats tests/harness/test_docker_oneliner.bats
HARNESS_VERBOSE="${HARNESS_VERBOSE:-false}"

# =============================================================================
# Helpers
# =============================================================================

setup() {
    test_setup

    if ! command -v docker &>/dev/null; then
        skip "Docker not installed — skipping Docker harness tests"
    fi

    if ! docker info &>/dev/null 2>&1; then
        skip "Docker daemon not running — skipping Docker harness tests"
    fi
}

teardown() {
    # Clean up any containers left behind by this test run
    local containers
    containers=$(docker ps -aq --filter "name=${CONTAINER_PREFIX}" 2>/dev/null || true)
    if [[ -n "${containers}" ]]; then
        echo "${containers}" | xargs docker rm -f &>/dev/null || true
    fi

    test_teardown
}

# Run a command inside a fresh Ubuntu 24.04 container.
# Uses --network host so that ping-based connectivity checks succeed.
# When HARNESS_VERBOSE=true, streams output to fd 3 (bats terminal).
# Arguments:
#   $1 — test suffix (used in container name)
#   $2… — command and arguments to run
_docker_run() {
    local suffix="$1"; shift
    local name="${CONTAINER_PREFIX}-${suffix}-$$"

    if [[ "${HARNESS_VERBOSE}" == "true" ]]; then
        echo ">>> [${suffix}] starting container ${name}" >&3
        docker run --rm \
            --name "${name}" \
            --network host \
            "${DOCKER_IMAGE}" \
            bash -c "$*" 2>&1 | tee /dev/fd/3
    else
        docker run --rm \
            --name "${name}" \
            --network host \
            "${DOCKER_IMAGE}" \
            bash -c "$*"
    fi
}

# Run a command inside a container with GPU access.
# When HARNESS_VERBOSE=true, streams output to fd 3 (bats terminal).
# Arguments:
#   $1 — test suffix
#   $2… — command and arguments
_docker_run_gpu() {
    local suffix="$1"; shift
    local name="${CONTAINER_PREFIX}-${suffix}-$$"

    if [[ "${HARNESS_VERBOSE}" == "true" ]]; then
        echo ">>> [${suffix}] starting GPU container ${name}" >&3
        docker run --rm \
            --name "${name}" \
            --network host \
            --gpus all \
            "${DOCKER_IMAGE}" \
            bash -c "$*" 2>&1 | tee /dev/fd/3
    else
        docker run --rm \
            --name "${name}" \
            --network host \
            --gpus all \
            "${DOCKER_IMAGE}" \
            bash -c "$*"
    fi
}

# Check whether the NVIDIA Container Toolkit is functional.
_gpu_available_in_docker() {
    docker run --rm --gpus all "${DOCKER_IMAGE}" \
        bash -c "command -v nvidia-smi &>/dev/null && nvidia-smi --query-gpu=name --format=csv,noheader" \
        &>/dev/null 2>&1
}

# =============================================================================
# Prerequisite checks
# =============================================================================

@test "docker_harness_prerequisite_dockerAvailable" {
    run docker version --format '{{.Server.Version}}'
    assert_status 0
    [[ -n "${output}" ]]
}

@test "docker_harness_prerequisite_ubuntuImagePullable" {
    run docker pull "${DOCKER_IMAGE}"
    assert_status 0
}

# =============================================================================
# One-liner download tests
# =============================================================================

@test "docker_harness_oneliner_curlDownloadsScript" {
    run _docker_run "curl-dl" \
        "apt-get update -qq && apt-get install -y -qq curl >/dev/null 2>&1 && \
         curl -fsSL ${RELEASE_URL} -o /tmp/gpu-vm-bootstrap.sh && \
         test -s /tmp/gpu-vm-bootstrap.sh && \
         head -1 /tmp/gpu-vm-bootstrap.sh"
    assert_status 0
    assert_output_contains "#!/usr/bin/env bash"
}

@test "docker_harness_oneliner_scriptIsValidBash" {
    run _docker_run "bash-syntax" \
        "apt-get update -qq && apt-get install -y -qq curl >/dev/null 2>&1 && \
         curl -fsSL ${RELEASE_URL} -o /tmp/gpu-vm-bootstrap.sh && \
         bash -n /tmp/gpu-vm-bootstrap.sh && \
         echo 'SYNTAX_OK'"
    assert_status 0
    assert_output_contains "SYNTAX_OK"
}

# =============================================================================
# --dry-run mode tests (no GPU required, no system changes)
# =============================================================================

@test "docker_harness_dryrun_detectsUbuntu2404" {
    run _docker_run "dryrun-detect" \
        "apt-get update -qq && apt-get install -y -qq curl pciutils iputils-ping >/dev/null 2>&1 && \
         curl -fsSL ${RELEASE_URL} -o /tmp/gpu-vm-bootstrap.sh && \
         chmod +x /tmp/gpu-vm-bootstrap.sh && \
         /tmp/gpu-vm-bootstrap.sh --dry-run --yes 2>&1 || true"
    assert_status 0
    assert_output_contains "Ubuntu 24.04 detected"
}

@test "docker_harness_dryrun_showsDryRunActions" {
    run _docker_run "dryrun-actions" \
        "apt-get update -qq && apt-get install -y -qq curl pciutils iputils-ping >/dev/null 2>&1 && \
         curl -fsSL ${RELEASE_URL} -o /tmp/gpu-vm-bootstrap.sh && \
         chmod +x /tmp/gpu-vm-bootstrap.sh && \
         /tmp/gpu-vm-bootstrap.sh --dry-run --yes 2>&1 || true"
    assert_status 0
    assert_output_contains "Dry run: true"
}

@test "docker_harness_dryrun_showsHelpText" {
    run _docker_run "dryrun-help" \
        "apt-get update -qq && apt-get install -y -qq curl >/dev/null 2>&1 && \
         curl -fsSL ${RELEASE_URL} -o /tmp/gpu-vm-bootstrap.sh && \
         chmod +x /tmp/gpu-vm-bootstrap.sh && \
         /tmp/gpu-vm-bootstrap.sh --help 2>&1"
    assert_status 0
    assert_output_contains "Usage"
    assert_output_contains "--dry-run"
    assert_output_contains "--skip-nvidia"
}

@test "docker_harness_dryrun_acceptsAllSkipFlags" {
    run _docker_run "dryrun-skipall" \
        "apt-get update -qq && apt-get install -y -qq curl pciutils iputils-ping >/dev/null 2>&1 && \
         curl -fsSL ${RELEASE_URL} -o /tmp/gpu-vm-bootstrap.sh && \
         chmod +x /tmp/gpu-vm-bootstrap.sh && \
         /tmp/gpu-vm-bootstrap.sh --dry-run --yes \
             --skip-nvidia --skip-kvm --skip-vfio --skip-bridge 2>&1 || true"
    assert_status 0
    assert_output_contains "Skipping"
}

@test "docker_harness_dryrun_wouldInstallPackages" {
    run _docker_run "dryrun-pkgs" \
        "apt-get update -qq && apt-get install -y -qq curl pciutils iputils-ping >/dev/null 2>&1 && \
         curl -fsSL ${RELEASE_URL} -o /tmp/gpu-vm-bootstrap.sh && \
         chmod +x /tmp/gpu-vm-bootstrap.sh && \
         /tmp/gpu-vm-bootstrap.sh --dry-run --yes --skip-vfio --skip-bridge 2>&1 || true"
    assert_status 0
    assert_output_contains "Would install"
}

# =============================================================================
# Pipe-to-bash tests — the EXACT one-liner from the README
#
# These tests run the real curl | bash against the live GitHub Release.
# No mounts, no local files, no shortcuts.  If these fail the release
# is broken.
# =============================================================================

@test "docker_harness_pipeToBash_curlPipeBashDryRun" {
    # The exact one-liner a user would run, with --dry-run --yes appended.
    run _docker_run "pipe-dryrun" \
        "apt-get update -qq && apt-get install -y -qq curl pciutils iputils-ping >/dev/null 2>&1 && \
         curl -fsSL ${RELEASE_URL} | bash -s -- --dry-run --yes 2>&1 || true"
    assert_status 0
    assert_output_contains "Ubuntu 24.04 detected"
    assert_output_contains "Dry run: true"
}

@test "docker_harness_pipeToBash_curlPipeBashHelp" {
    run _docker_run "pipe-help" \
        "apt-get update -qq && apt-get install -y -qq curl >/dev/null 2>&1 && \
         curl -fsSL ${RELEASE_URL} | bash -s -- --help 2>&1"
    assert_status 0
    assert_output_contains "Usage"
    assert_output_contains "--dry-run"
}

@test "docker_harness_pipeToBash_curlPipeSudoBashDryRun" {
    # Variant: sudo on bash (the correct way for real installs).
    # In Docker we are already root, so sudo is a no-op — but it proves
    # the pipe pattern does not break.
    run _docker_run "pipe-sudo" \
        "apt-get update -qq && apt-get install -y -qq curl pciutils iputils-ping sudo >/dev/null 2>&1 && \
         curl -fsSL ${RELEASE_URL} | sudo bash -s -- --dry-run --yes 2>&1 || true"
    assert_status 0
    assert_output_contains "Ubuntu 24.04 detected"
    assert_output_contains "Dry run: true"
}

@test "docker_harness_pipeToBash_sudoCurlPipeBashDryRun" {
    # Common mistake: sudo on curl instead of bash.
    # Must not crash — should degrade gracefully.
    run _docker_run "pipe-sudocurl" \
        "apt-get update -qq && apt-get install -y -qq curl pciutils iputils-ping sudo >/dev/null 2>&1 && \
         sudo curl -fsSL ${RELEASE_URL} | bash -s -- --dry-run --yes 2>&1 || true"
    assert_status 0
    assert_output_contains "Ubuntu 24.04 detected"
    assert_output_contains "Dry run: true"
}

# =============================================================================
# GPU-in-Docker tests (requires NVIDIA Container Toolkit)
# =============================================================================

@test "docker_harness_gpu_nvidiaSmiAvailableInContainer" {
    if ! _gpu_available_in_docker; then
        skip "GPU not available in Docker — NVIDIA Container Toolkit missing or no GPU"
    fi

    run _docker_run_gpu "gpu-smi" "nvidia-smi --query-gpu=name --format=csv,noheader"
    assert_status 0
    assert_output_contains "NVIDIA"
}

@test "docker_harness_gpu_dryrunDetectsGPU" {
    if ! _gpu_available_in_docker; then
        skip "GPU not available in Docker"
    fi

    run _docker_run_gpu "gpu-dryrun" \
        "apt-get update -qq && apt-get install -y -qq curl pciutils iputils-ping >/dev/null 2>&1 && \
         curl -fsSL ${RELEASE_URL} -o /tmp/gpu-vm-bootstrap.sh && \
         chmod +x /tmp/gpu-vm-bootstrap.sh && \
         /tmp/gpu-vm-bootstrap.sh --dry-run --yes --skip-kvm --skip-bridge 2>&1 || true"
    assert_status 0
    assert_output_contains "NVIDIA"
}

@test "docker_harness_gpu_scriptSeesGPUviaPciutils" {
    if ! _gpu_available_in_docker; then
        skip "GPU not available in Docker"
    fi

    run _docker_run_gpu "gpu-lspci" \
        "apt-get update -qq && apt-get install -y -qq pciutils >/dev/null 2>&1 && \
         lspci -nn | grep -i nvidia"
    assert_status 0
    assert_output_contains "NVIDIA"
}

# =============================================================================
# vmctl download test
# =============================================================================

@test "docker_harness_vmctl_downloadableFromRelease" {
    local vmctl_url="${REPO_URL}/releases/latest/download/vmctl"

    run _docker_run "vmctl-dl" \
        "apt-get update -qq && apt-get install -y -qq curl >/dev/null 2>&1 && \
         curl -fsSL ${vmctl_url} -o /tmp/vmctl && \
         test -s /tmp/vmctl && \
         head -1 /tmp/vmctl && \
         bash -n /tmp/vmctl && \
         echo 'VMCTL_SYNTAX_OK'"
    assert_status 0
    assert_output_contains "#!/usr/bin/env bash"
    assert_output_contains "VMCTL_SYNTAX_OK"
}
