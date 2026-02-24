#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
# Test helper functions for GPU VM Bootstrap tests
# Provides common utilities, setup, and teardown functions
# shellcheck disable=SC2155,SC2154

# Colours for test output
export RED='\033[0;31m'
export GREEN='\033[0;32m'
export YELLOW='\033[1;33m'
export BLUE='\033[0;34m'
export NC='\033[0m'

# Test environment paths
export TEST_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
export PROJECT_ROOT="$(cd "$TEST_DIR/.." && pwd)"
export BOOTSTRAP_SCRIPT="$PROJECT_ROOT/gpu-vm-bootstrap.sh"
export VMCTL_SCRIPT="$PROJECT_ROOT/vmctl"
export FIXTURES_DIR="$TEST_DIR/fixtures"

# Temporary directory for test artefacts
export TEST_TMP_DIR=""

# =============================================================================
# Setup and Teardown Functions
# =============================================================================

# Per-test setup
test_setup() {
    TEST_TMP_DIR=$(mktemp -d)
    export TEST_TMP_DIR
}

# Per-test teardown
test_teardown() {
    if [[ -n "$TEST_TMP_DIR" && -d "$TEST_TMP_DIR" ]]; then
        rm -rf "$TEST_TMP_DIR"
    fi
}

# =============================================================================
# Assertion Helper Functions
# =============================================================================

# Assert that output contains a string
assert_output_contains() {
    local expected="$1"
    if [[ "$output" != *"$expected"* ]]; then
        echo "Expected output to contain: $expected" >&2
        echo "Actual output: $output" >&2
        return 1
    fi
}

# Assert that output does not contain a string
assert_output_not_contains() {
    local unexpected="$1"
    if [[ "$output" == *"$unexpected"* ]]; then
        echo "Expected output NOT to contain: $unexpected" >&2
        echo "Actual output: $output" >&2
        return 1
    fi
}

# Assert that a file exists
assert_file_exists() {
    local file_path="$1"
    if [[ ! -f "$file_path" ]]; then
        echo "Expected file to exist: $file_path" >&2
        return 1
    fi
}

# Assert that a file does not exist
assert_file_not_exists() {
    local file_path="$1"
    if [[ -f "$file_path" ]]; then
        echo "Expected file NOT to exist: $file_path" >&2
        return 1
    fi
}

# Assert that a file contains a string
assert_file_contains() {
    local file_path="$1"
    local expected="$2"
    if ! grep -q "$expected" "$file_path" 2>/dev/null; then
        echo "Expected file $file_path to contain: $expected" >&2
        return 1
    fi
}

# Assert exit status
assert_status() {
    local expected="$1"
    if [[ "$status" -ne "$expected" ]]; then
        echo "Expected status: $expected, got: $status" >&2
        echo "Output: $output" >&2
        return 1
    fi
}

# =============================================================================
# Mock Function Helpers
# =============================================================================

# Create a mock command that logs calls and returns specified output
create_mock_command() {
    local cmd_name="$1"
    local return_code="${2:-0}"
    local output="${3:-}"
    local mock_dir="$TEST_TMP_DIR/mocks"
    local log_file="$TEST_TMP_DIR/${cmd_name}_calls.log"

    mkdir -p "$mock_dir"

    cat > "$mock_dir/$cmd_name" << EOF
#!/bin/bash
echo "\$@" >> "$log_file"
echo "$output"
exit $return_code
EOF

    chmod +x "$mock_dir/$cmd_name"
    echo "$mock_dir"
}

# Get the call log for a mock command
get_mock_calls() {
    local cmd_name="$1"
    local log_file="$TEST_TMP_DIR/${cmd_name}_calls.log"

    if [[ -f "$log_file" ]]; then
        cat "$log_file"
    fi
}

# Check if mock command was called with specific arguments
mock_was_called_with() {
    local cmd_name="$1"
    local expected_args="$2"

    get_mock_calls "$cmd_name" | grep -q "$expected_args"
}

# =============================================================================
# Utility Functions
# =============================================================================

# Generate a random string for unique identifiers
generate_random_string() {
    local length="${1:-8}"
    LC_ALL=C tr -dc 'a-z0-9' < /dev/urandom | head -c "$length"
}

# Check if Docker is available
docker_available() {
    command -v docker &>/dev/null && docker info &>/dev/null
}

# Skip test if Docker is not available
skip_if_no_docker() {
    if ! docker_available; then
        skip "Docker is not available"
    fi
}

# Print debug information
debug() {
    if [[ "${DEBUG:-}" == "true" ]]; then
        echo "DEBUG: $*" >&2
    fi
}

# =============================================================================
# GPU / System Detection Helpers (for mocking)
# =============================================================================

# Create mock lspci output with NVIDIA GPU
mock_nvidia_gpu() {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/lspci" << 'EOF'
#!/bin/bash
if [[ "$*" == *"NVIDIA"* ]] || [[ "$*" == *"nvidia"* ]] || [[ "$*" == *"-nn"* ]]; then
    echo "01:00.0 3D controller [0302]: NVIDIA Corporation GA100 [A100 PCIe 40GB] [10de:20f1] (rev a1)"
else
    echo "00:00.0 Host bridge: Intel Corporation Device 9a14 (rev 01)"
    echo "01:00.0 3D controller: NVIDIA Corporation GA100 [A100 PCIe 40GB] (rev a1)"
fi
exit 0
EOF

    chmod +x "$mock_dir/lspci"
    echo "$mock_dir"
}

# Create mock lspci output without NVIDIA GPU
mock_no_nvidia_gpu() {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/lspci" << 'EOF'
#!/bin/bash
echo "00:00.0 Host bridge: Intel Corporation Device 9a14 (rev 01)"
echo "00:02.0 VGA compatible controller: Intel Corporation UHD Graphics (rev 01)"
exit 0
EOF

    chmod +x "$mock_dir/lspci"
    echo "$mock_dir"
}

# Create mock for Ubuntu 24.04 detection
mock_ubuntu_2404() {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    mkdir -p "$TEST_TMP_DIR/etc"
    cat > "$TEST_TMP_DIR/etc/os-release" << 'EOF'
PRETTY_NAME="Ubuntu 24.04.1 LTS"
NAME="Ubuntu"
VERSION_ID="24.04"
VERSION="24.04.1 LTS (Noble Numbat)"
VERSION_CODENAME=noble
ID=ubuntu
ID_LIKE=debian
EOF
}
