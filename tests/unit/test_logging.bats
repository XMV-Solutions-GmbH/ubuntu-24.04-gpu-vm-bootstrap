#!/usr/bin/env bats
# SPDX-License-Identifier: MIT OR Apache-2.0
# Unit tests for gpu-vm-bootstrap.sh logging framework
# Tests log output formatting, log file writing, and colour handling

load '../test_helper'

setup() {
    test_setup
    # Set LOG_FILE to a temp location before sourcing so it's testable
    export LOG_FILE="$TEST_TMP_DIR/bootstrap-test.log"
    source "$PROJECT_ROOT/gpu-vm-bootstrap.sh"
    _LOG_INITIALISED=false
}

teardown() {
    test_teardown
}

# =============================================================================
# Log Initialisation
# =============================================================================

@test "log_init_validPath_initialisesSuccessfully" {
    _LOG_INITIALISED=false

    # log_init should initialise the log file at LOG_FILE (already set in setup)
    log_init

    [[ -f "$LOG_FILE" ]]
    [[ "$_LOG_INITIALISED" == "true" ]]
}

# =============================================================================
# Log Output (stderr)
# =============================================================================

@test "log_info_message_outputContainsINFO" {
    run log_info "Test message"
    [[ "$output" == *"INFO"* ]]
    [[ "$output" == *"Test message"* ]]
}

@test "log_success_message_outputContainsOK" {
    run log_success "Operation succeeded"
    [[ "$output" == *"OK"* ]]
    [[ "$output" == *"Operation succeeded"* ]]
}

@test "log_warn_message_outputContainsWARN" {
    run log_warn "Something suspicious"
    [[ "$output" == *"WARN"* ]]
    [[ "$output" == *"Something suspicious"* ]]
}

@test "log_error_message_outputContainsFAIL" {
    run log_error "Something broke"
    [[ "$output" == *"FAIL"* ]]
    [[ "$output" == *"Something broke"* ]]
}

# =============================================================================
# Debug Logging
# =============================================================================

@test "log_debug_verboseOff_noOutput" {
    VERBOSE=false
    run log_debug "Debug message"
    # Debug messages should not appear on stderr when verbose is off
    [[ "$output" != *"Debug message"* ]]
}

@test "log_debug_verboseOn_outputContainsDBUG" {
    VERBOSE=true
    run log_debug "Debug message"
    [[ "$output" == *"DBUG"* ]]
    [[ "$output" == *"Debug message"* ]]
}

# =============================================================================
# Phase and Step Logging
# =============================================================================

@test "log_phase_phaseNumber_outputContainsPhase" {
    run log_phase "1" "NVIDIA Setup"
    [[ "$output" == *"Phase 1"* ]]
    [[ "$output" == *"NVIDIA Setup"* ]]
}

@test "log_step_stepName_outputContainsStep" {
    run log_step "network" "Checking connectivity"
    [[ "$output" == *"Checking connectivity"* ]]
}

# =============================================================================
# Dry-run Logging
# =============================================================================

@test "log_dry_run_message_outputContainsDRYRUN" {
    run log_dry_run "Would install package: foo"
    [[ "$output" == *"DRY-RUN"* ]]
    [[ "$output" == *"Would install package: foo"* ]]
}

# =============================================================================
# Log File Writing
# =============================================================================

@test "_log_to_file_initialised_writesToFile" {
    _LOG_INITIALISED=true
    touch "$LOG_FILE"

    _log_to_file "INFO" "Test file message"

    [[ -f "$LOG_FILE" ]]
    grep -q "INFO" "$LOG_FILE"
    grep -q "Test file message" "$LOG_FILE"
}

@test "_log_to_file_initialised_containsTimestamp" {
    _LOG_INITIALISED=true
    touch "$LOG_FILE"

    _log_to_file "INFO" "Timestamped message"

    # Timestamp format: YYYY-MM-DD HH:MM:SS
    grep -qE '[0-9]{4}-[0-9]{2}-[0-9]{2} [0-9]{2}:[0-9]{2}:[0-9]{2}' "$LOG_FILE"
}

@test "_log_to_file_notInitialised_doesNotCrash" {
    _LOG_INITIALISED=false

    # Should not fail even when log is not initialised
    run _log_to_file "INFO" "Should not crash"
    [[ "$status" -eq 0 ]]
}
