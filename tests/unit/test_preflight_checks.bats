#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
# SPDX-License-Identifier: MIT OR Apache-2.0
# Unit tests for gpu-vm-bootstrap.sh pre-flight checks
# Tests OS version detection, root check, and network check

load '../test_helper'

setup() {
    test_setup
    source "$PROJECT_ROOT/gpu-vm-bootstrap.sh"
}

teardown() {
    test_teardown
}

# =============================================================================
# Ubuntu Version Detection
# =============================================================================

@test "check_ubuntu_version_ubuntu2404_succeeds" {
    mock_ubuntu_2404

    OS_RELEASE_FILE="$TEST_TMP_DIR/etc/os-release"
    run check_ubuntu_version
    [[ "$status" -eq 0 ]]
}

@test "check_ubuntu_version_ubuntu2404_outputContainsDetected" {
    mock_ubuntu_2404

    OS_RELEASE_FILE="$TEST_TMP_DIR/etc/os-release"
    run check_ubuntu_version
    [[ "$output" == *"Ubuntu 24.04 detected"* ]]
}

@test "check_ubuntu_version_wrongVersion_fails" {
    mkdir -p "$TEST_TMP_DIR/etc"
    cat > "$TEST_TMP_DIR/etc/os-release" << 'EOF'
PRETTY_NAME="Ubuntu 22.04 LTS"
NAME="Ubuntu"
VERSION_ID="22.04"
VERSION="22.04 LTS (Jammy Jellyfish)"
VERSION_CODENAME=jammy
ID=ubuntu
ID_LIKE=debian
EOF

    OS_RELEASE_FILE="$TEST_TMP_DIR/etc/os-release"
    run check_ubuntu_version
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"22.04"* ]]
}

@test "check_ubuntu_version_notUbuntu_fails" {
    mkdir -p "$TEST_TMP_DIR/etc"
    cat > "$TEST_TMP_DIR/etc/os-release" << 'EOF'
PRETTY_NAME="Debian GNU/Linux 12 (bookworm)"
NAME="Debian GNU/Linux"
VERSION_ID="12"
ID=debian
EOF

    OS_RELEASE_FILE="$TEST_TMP_DIR/etc/os-release"
    run check_ubuntu_version
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"debian"* ]]
}

@test "check_ubuntu_version_missingFile_fails" {
    OS_RELEASE_FILE="$TEST_TMP_DIR/nonexistent/os-release"
    run check_ubuntu_version
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"not found"* ]]
}

@test "check_ubuntu_version_fedora_fails" {
    mkdir -p "$TEST_TMP_DIR/etc"
    cat > "$TEST_TMP_DIR/etc/os-release" << 'EOF'
NAME="Fedora Linux"
VERSION_ID="39"
ID=fedora
EOF

    OS_RELEASE_FILE="$TEST_TMP_DIR/etc/os-release"
    run check_ubuntu_version
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# Root Check
# =============================================================================

@test "check_root_nonRoot_fails" {
    # This test only works when NOT running as root
    if [[ "$(id -u)" -eq 0 ]]; then
        skip "Test must be run as non-root user"
    fi

    run check_root
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"root"* ]]
}

@test "check_root_asRoot_succeeds" {
    # This test only works when running as root
    if [[ "$(id -u)" -ne 0 ]]; then
        skip "Test must be run as root user"
    fi

    run check_root
    [[ "$status" -eq 0 ]]
}

# =============================================================================
# Network Check
# =============================================================================

@test "check_network_reachable_succeeds" {
    # Create a mock ping that always succeeds
    local mock_dir
    mock_dir=$(create_mock_command "ping" 0 "PING response")
    export PATH="$mock_dir:$PATH"

    run check_network
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"connectivity confirmed"* ]]
}

@test "check_network_unreachable_fails" {
    # Create a mock ping that always fails
    local mock_dir
    mock_dir=$(create_mock_command "ping" 1 "")
    export PATH="$mock_dir:$PATH"

    run check_network
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"No internet connectivity"* ]]
}
