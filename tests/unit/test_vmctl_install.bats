#!/usr/bin/env bats
# shellcheck disable=SC1090,SC2030,SC2031
# SPDX-License-Identifier: MIT OR Apache-2.0
# Unit tests for Phase 5: vmctl CLI Installation
# Tests install_vmctl, create_vmctl_config_dir, verify_vmctl, and
# the _locate_vmctl_source / _vmctl_version_matches helpers

load '../test_helper'

setup() {
    test_setup
    export LOG_FILE="$TEST_TMP_DIR/bootstrap-test.log"
    export CONFIG_DIR="$TEST_TMP_DIR/etc/vmctl"
    export DRY_RUN=false
    export VERBOSE=false

    # Override install path to a temp location
    # (cannot write to /usr/local/bin in CI)
    export VMCTL_INSTALL_PATH="$TEST_TMP_DIR/usr/local/bin/vmctl"
    mkdir -p "$TEST_TMP_DIR/usr/local/bin"

    source "$BOOTSTRAP_SCRIPT"
}

teardown() {
    test_teardown
}

# =============================================================================
# _locate_vmctl_source
# =============================================================================

@test "_locate_vmctl_source_scriptInSameDir_returnsLocalPath" {
    run _locate_vmctl_source
    assert_status 0
    # Should find the vmctl file next to gpu-vm-bootstrap.sh
    assert_output_contains "vmctl"
    [[ -f "$output" ]]
}

# =============================================================================
# _vmctl_version_matches
# =============================================================================

@test "_vmctl_version_matches_noInstalledBinary_returnsFalse" {
    # No vmctl at the install path
    run _vmctl_version_matches "$PROJECT_ROOT/vmctl"
    [[ "$status" -ne 0 ]]
}

@test "_vmctl_version_matches_sameVersion_returnsTrue" {
    # Install vmctl to the temp path so it's available
    cp "$PROJECT_ROOT/vmctl" "$VMCTL_INSTALL_PATH"
    chmod +x "$VMCTL_INSTALL_PATH"

    run _vmctl_version_matches "$PROJECT_ROOT/vmctl"
    assert_status 0
}

@test "_vmctl_version_matches_differentVersion_returnsFalse" {
    # Install vmctl, then modify the source version string
    cp "$PROJECT_ROOT/vmctl" "$VMCTL_INSTALL_PATH"
    chmod +x "$VMCTL_INSTALL_PATH"

    # Create a modified source with a different version
    local modified="$TEST_TMP_DIR/vmctl_modified"
    sed 's/VMCTL_VERSION="[^"]*"/VMCTL_VERSION="99.99.99"/' \
        "$PROJECT_ROOT/vmctl" > "$modified"

    run _vmctl_version_matches "$modified"
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# install_vmctl
# =============================================================================

@test "install_vmctl_freshInstall_copiesBinary" {
    run install_vmctl
    assert_status 0
    [[ -f "$VMCTL_INSTALL_PATH" ]]
    [[ -x "$VMCTL_INSTALL_PATH" ]]
    assert_output_contains "Installed vmctl"
}

@test "install_vmctl_alreadyInstalled_skips" {
    # Pre-install the same version
    cp "$PROJECT_ROOT/vmctl" "$VMCTL_INSTALL_PATH"
    chmod +x "$VMCTL_INSTALL_PATH"

    run install_vmctl
    assert_status 0
    assert_output_not_contains "Installed vmctl"
}

@test "install_vmctl_dryRun_doesNotCopy" {
    export DRY_RUN=true

    run install_vmctl
    assert_status 0
    assert_output_contains "Would install vmctl"
    [[ ! -f "$VMCTL_INSTALL_PATH" ]]
}

@test "install_vmctl_updatesOlderVersion" {
    # Install a fake older version
    cat > "$VMCTL_INSTALL_PATH" << 'EOF'
#!/usr/bin/env bash
readonly VMCTL_NAME="vmctl"
readonly VMCTL_VERSION="0.0.1-old"
show_version() { echo "${VMCTL_NAME} v${VMCTL_VERSION}"; }
case "${1:-}" in version) show_version ;; esac
EOF
    chmod +x "$VMCTL_INSTALL_PATH"

    run install_vmctl
    assert_status 0
    assert_output_contains "Installed vmctl"

    # Verify the installed file is the new version
    local installed_ver
    installed_ver="$("$VMCTL_INSTALL_PATH" version 2>/dev/null | awk '{print $NF}')"
    [[ "$installed_ver" != "v0.0.1-old" ]]
}

# =============================================================================
# create_vmctl_config_dir
# =============================================================================

@test "create_vmctl_config_dir_dirNotExist_createsIt" {
    run create_vmctl_config_dir
    assert_status 0
    [[ -d "$CONFIG_DIR" ]]
    assert_output_contains "Created config directory"
}

@test "create_vmctl_config_dir_dirAlreadyExists_skips" {
    mkdir -p "$CONFIG_DIR"

    run create_vmctl_config_dir
    assert_status 0
    assert_output_not_contains "Created config directory"
}

@test "create_vmctl_config_dir_dryRun_doesNotCreate" {
    export DRY_RUN=true

    run create_vmctl_config_dir
    assert_status 0
    assert_output_contains "Would create directory"
    [[ ! -d "$CONFIG_DIR" ]]
}

# =============================================================================
# verify_vmctl
# =============================================================================

@test "verify_vmctl_installed_succeeds" {
    # Put mock vmctl on PATH
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/vmctl" << 'MOCK'
#!/bin/bash
echo "vmctl v0.1.0-dev"
exit 0
MOCK
    chmod +x "$mock_dir/vmctl"
    export PATH="$mock_dir:$PATH"

    run verify_vmctl
    assert_status 0
    assert_output_contains "vmctl operational"
}

@test "verify_vmctl_notOnPath_returnsError" {
    # Ensure vmctl is NOT on PATH
    export PATH="/usr/bin:/bin"

    run verify_vmctl
    assert_status "$EXIT_GENERAL_ERROR"
    assert_output_contains "not found in PATH"
}

@test "verify_vmctl_dryRun_skipsCheck" {
    export DRY_RUN=true

    run verify_vmctl
    assert_status 0
    assert_output_contains "Would verify"
}

# =============================================================================
# phase_vmctl_install — orchestrator
# =============================================================================

@test "phase_vmctl_install_fullRun_succeeds" {
    # Put vmctl on PATH after install
    export PATH="$TEST_TMP_DIR/usr/local/bin:$PATH"

    run phase_vmctl_install
    assert_status 0
    [[ -f "$VMCTL_INSTALL_PATH" ]]
    [[ -d "$CONFIG_DIR" ]]
}

@test "phase_vmctl_install_dryRun_succeeds" {
    export DRY_RUN=true

    run phase_vmctl_install
    assert_status 0
    assert_output_contains "Would install"
    assert_output_contains "Would create"
    assert_output_contains "Would verify"
}
