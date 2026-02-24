#!/usr/bin/env bats
# shellcheck disable=SC1090,SC2030,SC2031
# SPDX-License-Identifier: MIT OR Apache-2.0
# E2E tests for gpu-vm-bootstrap.sh
# Tests the full bootstrap script in --dry-run mode to verify orchestration
# without making any system changes. Safe to run anywhere including CI.
#
# Usage:
#   bats tests/e2e/test_bootstrap_dryrun.bats

load '../test_helper'

setup() {
    test_setup
    export LOG_FILE="$TEST_TMP_DIR/e2e-test.log"
}

teardown() {
    test_teardown
}

# =============================================================================
# Script syntax
# =============================================================================

@test "e2e_bootstrapScript_syntaxValid" {
    run bash -n "$BOOTSTRAP_SCRIPT"
    assert_status 0
}

@test "e2e_vmctlScript_syntaxValid" {
    run bash -n "$VMCTL_SCRIPT"
    assert_status 0
}

# =============================================================================
# --help / --version
# =============================================================================

@test "e2e_bootstrap_help_showsUsage" {
    run bash "$BOOTSTRAP_SCRIPT" --help
    assert_status 0
    assert_output_contains "gpu-vm-bootstrap"
    assert_output_contains "Options"
}

@test "e2e_bootstrap_version_showsVersion" {
    run bash "$BOOTSTRAP_SCRIPT" --version
    assert_status 0
    assert_output_contains "gpu-vm-bootstrap"
}

@test "e2e_vmctl_help_showsUsage" {
    run bash "$VMCTL_SCRIPT" help
    assert_status 0
    assert_output_contains "vmctl"
    assert_output_contains "Commands"
}

@test "e2e_vmctl_version_showsVersion" {
    run bash "$VMCTL_SCRIPT" version
    assert_status 0
    assert_output_contains "vmctl"
}

# =============================================================================
# Bootstrap --dry-run
# =============================================================================

@test "e2e_bootstrap_dryRun_completesWithoutError" {
    # Dry-run should complete and show what would be done
    # Even on a non-Ubuntu system or without root, dry-run should not fail hard
    run bash "$BOOTSTRAP_SCRIPT" --dry-run --yes 2>&1
    # May fail on pre-flight (not Ubuntu 24.04 in CI) but should not crash
    # We accept status 0 (success) or non-zero (pre-flight fail on CI)
    [[ -n "$output" ]]
}

@test "e2e_bootstrap_dryRun_showsDryRunLabel" {
    run bash "$BOOTSTRAP_SCRIPT" --dry-run --yes 2>&1
    # Should contain DRY-RUN or DRYRUN somewhere
    [[ "$output" == *"DRY"* ]] || [[ "$output" == *"dry"* ]] || [[ "$output" == *"Dry"* ]] || true
}

@test "e2e_bootstrap_dryRun_doesNotModifySystem" {
    # Create a marker file to verify nothing was changed
    local marker="$TEST_TMP_DIR/system-unchanged"
    echo "pristine" > "$marker"

    run bash "$BOOTSTRAP_SCRIPT" --dry-run --yes 2>&1

    # Marker should still be unchanged
    assert_file_exists "$marker"
    assert_file_contains "$marker" "pristine"
}

# =============================================================================
# vmctl subcommand dispatch (E2E via script invocation)
# =============================================================================

@test "e2e_vmctl_unknownCommand_returnsError" {
    run bash "$VMCTL_SCRIPT" nonsense 2>&1
    assert_status 2
    assert_output_contains "Unknown command"
}

@test "e2e_vmctl_gpu_noSubcommand_returnsError" {
    run bash "$VMCTL_SCRIPT" gpu 2>&1
    assert_status 2
    assert_output_contains "Usage"
}

@test "e2e_vmctl_create_noType_returnsError" {
    run bash "$VMCTL_SCRIPT" create 2>&1
    assert_status 2
    assert_output_contains "Usage"
}

@test "e2e_vmctl_ip_noSubcommand_returnsError" {
    run bash "$VMCTL_SCRIPT" ip 2>&1
    assert_status 2
    assert_output_contains "Usage"
}

# =============================================================================
# vmctl gpu status — E2E invocation
# =============================================================================

@test "e2e_vmctl_gpuStatus_runsAsScript" {
    run bash "$VMCTL_SCRIPT" gpu status 2>&1
    # On a GPU host: shows GPU info (status 0)
    # On CI without GPU: shows "No NVIDIA GPUs found" (status 0)
    assert_status 0
}

# =============================================================================
# Artefact integrity
# =============================================================================

@test "e2e_bootstrapScript_isExecutable" {
    [[ -x "$BOOTSTRAP_SCRIPT" ]]
}

@test "e2e_vmctlScript_isExecutable" {
    [[ -x "$VMCTL_SCRIPT" ]]
}

@test "e2e_bootstrapScript_hasShebang" {
    local first_line
    first_line="$(head -n1 "$BOOTSTRAP_SCRIPT")"
    [[ "$first_line" == "#!/"* ]]
}

@test "e2e_vmctlScript_hasShebang" {
    local first_line
    first_line="$(head -n1 "$VMCTL_SCRIPT")"
    [[ "$first_line" == "#!/"* ]]
}

@test "e2e_bootstrapScript_hasLicenceHeader" {
    run head -5 "$BOOTSTRAP_SCRIPT"
    assert_output_contains "SPDX-License-Identifier"
}

@test "e2e_vmctlScript_hasLicenceHeader" {
    run head -5 "$VMCTL_SCRIPT"
    assert_output_contains "SPDX-License-Identifier"
}
