#!/usr/bin/env bats
# shellcheck disable=SC2030,SC2031
# SPDX-License-Identifier: MIT OR Apache-2.0
# Unit tests for gpu-vm-bootstrap.sh idempotency helpers
# Tests package detection, service checks, module checks, and file helpers

load '../test_helper'

setup() {
    test_setup
    source "$PROJECT_ROOT/gpu-vm-bootstrap.sh"
}

teardown() {
    test_teardown
}

# =============================================================================
# Package Detection
# =============================================================================

@test "is_pkg_installed_installedPkg_returnsZero" {
    # dpkg-query is only available on Debian/Ubuntu
    if ! command -v dpkg-query &>/dev/null; then
        skip "dpkg-query not available (not a Debian-based system)"
    fi
    run is_pkg_installed "bash"
    [[ "$status" -eq 0 ]]
}

@test "is_pkg_installed_missingPkg_returnsNonZero" {
    if ! command -v dpkg-query &>/dev/null; then
        skip "dpkg-query not available (not a Debian-based system)"
    fi
    run is_pkg_installed "this-package-definitely-does-not-exist-12345"
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# Command Availability
# =============================================================================

@test "is_command_available_existingCmd_returnsZero" {
    run is_command_available "bash"
    [[ "$status" -eq 0 ]]
}

@test "is_command_available_missingCmd_returnsNonZero" {
    run is_command_available "nonexistent_command_xyz_12345"
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# File Helpers
# =============================================================================

@test "is_file_present_existingFile_returnsZero" {
    echo "content" > "$TEST_TMP_DIR/testfile.txt"
    run is_file_present "$TEST_TMP_DIR/testfile.txt"
    [[ "$status" -eq 0 ]]
}

@test "is_file_present_emptyFile_returnsNonZero" {
    touch "$TEST_TMP_DIR/empty.txt"
    run is_file_present "$TEST_TMP_DIR/empty.txt"
    [[ "$status" -ne 0 ]]
}

@test "is_file_present_missingFile_returnsNonZero" {
    run is_file_present "$TEST_TMP_DIR/no-such-file.txt"
    [[ "$status" -ne 0 ]]
}

@test "is_line_in_file_linePresent_returnsZero" {
    cat > "$TEST_TMP_DIR/config.txt" << 'EOF'
option_a=true
option_b=false
some_setting=123
EOF
    run is_line_in_file "$TEST_TMP_DIR/config.txt" "option_a=true"
    [[ "$status" -eq 0 ]]
}

@test "is_line_in_file_lineAbsent_returnsNonZero" {
    cat > "$TEST_TMP_DIR/config.txt" << 'EOF'
option_a=true
option_b=false
EOF
    run is_line_in_file "$TEST_TMP_DIR/config.txt" "option_c=maybe"
    [[ "$status" -ne 0 ]]
}

@test "is_line_in_file_fileMissing_returnsNonZero" {
    run is_line_in_file "$TEST_TMP_DIR/no-such-file.txt" "anything"
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# GRUB Parameter Detection
# =============================================================================

@test "is_grub_param_set_paramPresent_returnsZero" {
    cat > "$TEST_TMP_DIR/grub" << 'EOF'
GRUB_DEFAULT=0
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash intel_iommu=on"
GRUB_CMDLINE_LINUX=""
EOF
    GRUB_DEFAULT_FILE="$TEST_TMP_DIR/grub"
    run is_grub_param_set "intel_iommu=on"
    [[ "$status" -eq 0 ]]
}

@test "is_grub_param_set_paramAbsent_returnsNonZero" {
    cat > "$TEST_TMP_DIR/grub" << 'EOF'
GRUB_DEFAULT=0
GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"
GRUB_CMDLINE_LINUX=""
EOF
    GRUB_DEFAULT_FILE="$TEST_TMP_DIR/grub"
    run is_grub_param_set "intel_iommu=on"
    [[ "$status" -ne 0 ]]
}

@test "is_grub_param_set_fileMissing_returnsNonZero" {
    GRUB_DEFAULT_FILE="$TEST_TMP_DIR/nonexistent-grub"
    run is_grub_param_set "intel_iommu=on"
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# Service Checks
# =============================================================================

@test "is_service_active_nonexistentService_returnsNonZero" {
    if ! command -v systemctl &>/dev/null; then
        skip "systemctl not available (not a systemd-based system)"
    fi
    run is_service_active "nonexistent-service-xyz-12345"
    [[ "$status" -ne 0 ]]
}

@test "is_service_enabled_nonexistentService_returnsNonZero" {
    if ! command -v systemctl &>/dev/null; then
        skip "systemctl not available (not a systemd-based system)"
    fi
    run is_service_enabled "nonexistent-service-xyz-12345"
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# Module Checks
# =============================================================================

@test "is_module_loaded_loadedModule_returnsZero" {
    # Most Linux systems have at least one module loaded
    # We check for a common one; skip if running in minimal container
    local any_module
    any_module="$(lsmod | tail -n1 | awk '{print $1}' 2>/dev/null)" || true

    if [[ -z "$any_module" ]]; then
        skip "No kernel modules loaded (possibly running in a container)"
    fi

    run is_module_loaded "$any_module"
    [[ "$status" -eq 0 ]]
}

@test "is_module_loaded_missingModule_returnsNonZero" {
    run is_module_loaded "nonexistent_module_xyz_12345"
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# ensure_pkg_installed (dry-run mode)
# =============================================================================

@test "ensure_pkg_installed_dryRun_doesNotInstall" {
    DRY_RUN=true
    run ensure_pkg_installed "some-nonexistent-package"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"DRY-RUN"* ]]
}

@test "ensure_pkg_installed_alreadyInstalled_skips" {
    DRY_RUN=false
    VERBOSE=true

    # Mock dpkg-query to report installed
    local mock_dir
    mock_dir=$(create_mock_command "dpkg-query" 0 "install ok installed")
    export PATH="$mock_dir:$PATH"

    run ensure_pkg_installed "bash"
    [[ "$status" -eq 0 ]]
}

# =============================================================================
# ensure_service_running (dry-run mode)
# =============================================================================

@test "ensure_service_running_dryRun_doesNotStart" {
    DRY_RUN=true

    # Mock systemctl to return inactive
    local mock_dir
    mock_dir=$(create_mock_command "systemctl" 1 "inactive")
    export PATH="$mock_dir:$PATH"

    run ensure_service_running "some-service"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"DRY-RUN"* ]]
}
