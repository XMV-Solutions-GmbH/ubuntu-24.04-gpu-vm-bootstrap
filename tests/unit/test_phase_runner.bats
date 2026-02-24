#!/usr/bin/env bats
# SPDX-License-Identifier: MIT OR Apache-2.0
# Unit tests for gpu-vm-bootstrap.sh phase runner
# Tests phase execution, skip logic, and error propagation

load '../test_helper'

setup() {
    test_setup
    source "$PROJECT_ROOT/gpu-vm-bootstrap.sh"
}

teardown() {
    test_teardown
}

# =============================================================================
# Phase Runner
# =============================================================================

@test "run_phase_normalExecution_succeeds" {
    _test_phase_ok() { return 0; }

    run run_phase "1" "Test Phase" _test_phase_ok "false"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Phase 1"* ]]
    [[ "$output" == *"Test Phase"* ]]
}

@test "run_phase_skipped_outputContainsSkipping" {
    _test_phase_skip() { return 0; }

    run run_phase "2" "Skipped Phase" _test_phase_skip "true"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Skipping"* ]]
}

@test "run_phase_skipped_phaseNotExecuted" {
    local was_called=false
    _test_phase_should_not_run() { was_called=true; return 0; }

    run_phase "3" "Should Not Run" _test_phase_should_not_run "true"
    [[ "$was_called" == "false" ]]
}

@test "run_phase_phaseFails_returnsNonZero" {
    _test_phase_fail() { return 1; }

    run run_phase "4" "Failing Phase" _test_phase_fail "false"
    [[ "$status" -ne 0 ]]
    [[ "$output" == *"failed"* ]]
}

@test "run_phase_phaseSucceeds_outputContainsComplete" {
    _test_phase_success() { return 0; }

    run run_phase "5" "Success Phase" _test_phase_success "false"
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"complete"* ]]
}

# =============================================================================
# Phase Stubs
# =============================================================================

@test "phase_nvidia_setup_dryRun_succeeds" {
    export DRY_RUN=true
    local mock_dir
    mock_dir="$(mock_nvidia_gpu)"
    export PATH="$mock_dir:$PATH"

    run phase_nvidia_setup
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"DRY-RUN"* ]]
}

@test "phase_kvm_setup_stub_succeeds" {
    run phase_kvm_setup
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"not yet implemented"* ]]
}

@test "phase_vfio_setup_stub_succeeds" {
    run phase_vfio_setup
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"not yet implemented"* ]]
}

@test "phase_bridge_setup_stub_succeeds" {
    run phase_bridge_setup
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"not yet implemented"* ]]
}

@test "phase_vmctl_install_stub_succeeds" {
    run phase_vmctl_install
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"not yet implemented"* ]]
}

# =============================================================================
# Show Banner / Summary
# =============================================================================

@test "show_banner_outputContainsProjectName" {
    run show_banner
    [[ "$output" == *"GPU VM Bootstrap"* ]]
}

@test "print_summary_outputContainsComplete" {
    DRY_RUN=false
    run print_summary
    [[ "$output" == *"Bootstrap Complete"* ]]
}

@test "print_summary_dryRun_outputContainsDryRun" {
    DRY_RUN=true
    run print_summary
    [[ "$output" == *"dry run"* ]]
}
