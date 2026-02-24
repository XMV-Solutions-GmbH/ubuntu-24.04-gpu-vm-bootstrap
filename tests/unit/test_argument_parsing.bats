#!/usr/bin/env bats
# SPDX-License-Identifier: MIT OR Apache-2.0
# Unit tests for gpu-vm-bootstrap.sh argument parsing
# Tests all CLI flags, default values, and error handling

load '../test_helper'

setup() {
    test_setup
    # Source the bootstrap script to get access to functions
    # We source it rather than executing it, so main() does not run
    source "$PROJECT_ROOT/gpu-vm-bootstrap.sh"
}

teardown() {
    test_teardown
}

# =============================================================================
# Default Values
# =============================================================================

@test "parse_args_noArgs_defaultsAreSet" {
    parse_args

    [[ "$SKIP_NVIDIA" == "false" ]]
    [[ "$SKIP_KVM" == "false" ]]
    [[ "$SKIP_VFIO" == "false" ]]
    [[ "$SKIP_BRIDGE" == "false" ]]
    [[ "$GPU_MODE" == "flexible" ]]
    [[ "$DRY_RUN" == "false" ]]
    [[ "$YES_MODE" == "false" ]]
    [[ "$REBOOT_ALLOWED" == "false" ]]
    [[ "$VERBOSE" == "false" ]]
    [[ "$BRIDGE_NAME" == "br0" ]]
    [[ "$BRIDGE_SUBNET" == "" ]]
}

# =============================================================================
# Skip Flags
# =============================================================================

@test "parse_args_skipNvidia_setsFlag" {
    parse_args --skip-nvidia
    [[ "$SKIP_NVIDIA" == "true" ]]
}

@test "parse_args_skipKvm_setsFlag" {
    parse_args --skip-kvm
    [[ "$SKIP_KVM" == "true" ]]
}

@test "parse_args_skipVfio_setsFlag" {
    parse_args --skip-vfio
    [[ "$SKIP_VFIO" == "true" ]]
}

@test "parse_args_skipBridge_setsFlag" {
    parse_args --skip-bridge
    [[ "$SKIP_BRIDGE" == "true" ]]
}

@test "parse_args_allSkipFlags_setsAllFlags" {
    parse_args --skip-nvidia --skip-kvm --skip-vfio --skip-bridge

    [[ "$SKIP_NVIDIA" == "true" ]]
    [[ "$SKIP_KVM" == "true" ]]
    [[ "$SKIP_VFIO" == "true" ]]
    [[ "$SKIP_BRIDGE" == "true" ]]
}

# =============================================================================
# GPU Mode
# =============================================================================

@test "parse_args_gpuModeExclusive_setsMode" {
    parse_args --gpu-mode exclusive
    [[ "$GPU_MODE" == "exclusive" ]]
}

@test "parse_args_gpuModeFlexible_setsMode" {
    parse_args --gpu-mode flexible
    [[ "$GPU_MODE" == "flexible" ]]
}

@test "parse_args_gpuModeInvalid_returnsError" {
    run parse_args --gpu-mode invalid
    [[ "$status" -ne 0 ]]
}

@test "parse_args_gpuModeNoValue_returnsError" {
    run parse_args --gpu-mode
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# Bridge Options
# =============================================================================

@test "parse_args_bridgeName_setsName" {
    parse_args --bridge-name br1
    [[ "$BRIDGE_NAME" == "br1" ]]
}

@test "parse_args_bridgeNameNoValue_returnsError" {
    run parse_args --bridge-name
    [[ "$status" -ne 0 ]]
}

@test "parse_args_bridgeSubnet_setsSubnet" {
    parse_args --bridge-subnet "192.168.1.0/24"
    [[ "$BRIDGE_SUBNET" == "192.168.1.0/24" ]]
}

@test "parse_args_bridgeSubnetNoValue_returnsError" {
    run parse_args --bridge-subnet
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# Behaviour Flags
# =============================================================================

@test "parse_args_dryRun_setsFlag" {
    parse_args --dry-run
    [[ "$DRY_RUN" == "true" ]]
}

@test "parse_args_yes_setsFlag" {
    parse_args --yes
    [[ "$YES_MODE" == "true" ]]
}

@test "parse_args_yShorthand_setsFlag" {
    parse_args -y
    [[ "$YES_MODE" == "true" ]]
}

@test "parse_args_reboot_setsFlag" {
    parse_args --reboot
    [[ "$REBOOT_ALLOWED" == "true" ]]
}

@test "parse_args_verbose_setsFlag" {
    parse_args --verbose
    [[ "$VERBOSE" == "true" ]]
}

@test "parse_args_verboseShorthand_setsFlag" {
    parse_args -v
    [[ "$VERBOSE" == "true" ]]
}

# =============================================================================
# Combined Arguments
# =============================================================================

@test "parse_args_multipleFlags_allSet" {
    parse_args --skip-nvidia --gpu-mode exclusive --dry-run --yes --verbose --bridge-name virbr0

    [[ "$SKIP_NVIDIA" == "true" ]]
    [[ "$GPU_MODE" == "exclusive" ]]
    [[ "$DRY_RUN" == "true" ]]
    [[ "$YES_MODE" == "true" ]]
    [[ "$VERBOSE" == "true" ]]
    [[ "$BRIDGE_NAME" == "virbr0" ]]
}

# =============================================================================
# Error Handling
# =============================================================================

@test "parse_args_unknownOption_returnsError" {
    run parse_args --unknown-flag
    [[ "$status" -ne 0 ]]
}

@test "parse_args_unknownOption_outputContainsFlag" {
    run parse_args --bogus
    [[ "$output" == *"--bogus"* ]]
}

# =============================================================================
# Version
# =============================================================================

@test "parse_args_version_outputContainsVersion" {
    run parse_args --version
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"gpu-vm-bootstrap"* ]]
    [[ "$output" == *"0.1.0"* ]]
}

# =============================================================================
# Help
# =============================================================================

@test "parse_args_help_outputContainsUsage" {
    run parse_args --help
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Usage"* ]]
}

@test "parse_args_helpShorthand_outputContainsUsage" {
    run parse_args -h
    [[ "$status" -eq 0 ]]
    [[ "$output" == *"Usage"* ]]
}
