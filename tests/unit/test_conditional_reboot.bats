#!/usr/bin/env bats
# shellcheck disable=SC1090,SC2030,SC2031
# SPDX-License-Identifier: MIT OR Apache-2.0
# Unit tests for Phase 7: Conditional Nightly Reboot
# Tests configure_conditional_reboot() — cron job creation, idempotency,
# and dry-run behaviour.

load '../test_helper'

setup() {
    test_setup
    export LOG_FILE="$TEST_TMP_DIR/bootstrap-test.log"
    export DRY_RUN=false
    export VERBOSE=false

    source "$BOOTSTRAP_SCRIPT"
}

teardown() {
    test_teardown
}

# =============================================================================
# configure_conditional_reboot() tests
# =============================================================================

@test "configure_conditional_reboot: dry-run shows what would be done" {
    export DRY_RUN=true

    run configure_conditional_reboot
    assert_status 0
    assert_output_contains "DRY-RUN"
    assert_output_contains "02:00"
    assert_output_contains "Europe/Berlin"
    assert_output_contains "reboot-required"
}

@test "configure_conditional_reboot: dry-run does not create cron file" {
    export DRY_RUN=true

    local cron_file="/etc/cron.d/gpu-vm-conditional-reboot"
    # Remove if present from a previous test
    rm -f "${cron_file}" 2>/dev/null || true

    run configure_conditional_reboot
    assert_status 0

    [[ ! -f "${cron_file}" ]] || skip "File pre-exists (cannot remove without root)"
}

@test "configure_conditional_reboot: creates cron file with correct content" {
    local cron_file="/etc/cron.d/gpu-vm-conditional-reboot"
    rm -f "${cron_file}" 2>/dev/null || true

    run configure_conditional_reboot

    # On non-root CI the function may succeed but the file does not exist
    if [[ ! -f "${cron_file}" ]]; then
        skip "Cannot write to /etc/cron.d (no root)"
    fi

    assert_file_contains "${cron_file}" "TZ=Europe/Berlin"
    assert_file_contains "${cron_file}" "reboot-required"
    assert_file_contains "${cron_file}" "0 2 * * *"
    assert_file_contains "${cron_file}" "/sbin/reboot"
    assert_file_contains "${cron_file}" "gpu-vm-bootstrap"

    # Clean up
    rm -f "${cron_file}" 2>/dev/null || true
}

@test "configure_conditional_reboot: skips when cron already exists" {
    export VERBOSE=true

    local cron_file="/etc/cron.d/gpu-vm-conditional-reboot"
    mkdir -p "$(dirname "${cron_file}")" 2>/dev/null || true
    echo "# existing" > "${cron_file}" 2>/dev/null || {
        skip "Cannot write to /etc/cron.d (no root)"
    }

    run configure_conditional_reboot
    assert_status 0
    assert_output_contains "already configured"

    rm -f "${cron_file}" 2>/dev/null || true
}
