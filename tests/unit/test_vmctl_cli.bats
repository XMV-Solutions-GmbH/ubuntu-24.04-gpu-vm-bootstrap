#!/usr/bin/env bats
# shellcheck disable=SC1090,SC2030,SC2031
# SPDX-License-Identifier: MIT OR Apache-2.0
# Unit tests for vmctl CLI — command dispatch, usage, helpers
# Tests the vmctl script in isolation with mocked dependencies

load '../test_helper'

setup() {
    test_setup
    export LOG_FILE="$TEST_TMP_DIR/vmctl-test.log"
    source "$VMCTL_SCRIPT"
}

teardown() {
    test_teardown
}

# =============================================================================
# show_version
# =============================================================================

@test "show_version_printsVersionString" {
    run show_version
    assert_status 0
    assert_output_contains "vmctl"
    assert_output_contains "v"
}

# =============================================================================
# show_usage
# =============================================================================

@test "show_usage_printsHelpText" {
    run show_usage
    assert_status 0
    assert_output_contains "vmctl"
    assert_output_contains "Commands"
    assert_output_contains "list"
    assert_output_contains "start"
    assert_output_contains "stop"
    assert_output_contains "delete"
    assert_output_contains "ssh"
    assert_output_contains "gpu"
    assert_output_contains "create"
}

# =============================================================================
# main dispatcher
# =============================================================================

@test "main_noArgs_showsUsage" {
    run main
    assert_status 0
    assert_output_contains "Commands"
}

@test "main_help_showsUsage" {
    run main help
    assert_status 0
    assert_output_contains "Commands"
}

@test "main_dashH_showsUsage" {
    run main -h
    assert_status 0
    assert_output_contains "Commands"
}

@test "main_dashDashHelp_showsUsage" {
    run main --help
    assert_status 0
    assert_output_contains "Commands"
}

@test "main_version_showsVersion" {
    run main version
    assert_status 0
    assert_output_contains "vmctl v"
}

@test "main_unknownCommand_returnsError" {
    run main nonsense
    assert_status "$EXIT_INVALID_ARGS"
    assert_output_contains "Unknown command"
}

# =============================================================================
# _require_command
# =============================================================================

@test "_require_command_existingCommand_succeeds" {
    run _require_command bash
    assert_status 0
}

@test "_require_command_missingCommand_returnsError" {
    run _require_command __nonexistent_binary_xyzzy__
    assert_status "$EXIT_GENERAL_ERROR"
    assert_output_contains "not installed"
}

# =============================================================================
# cmd_start — argument validation
# =============================================================================

@test "cmd_start_noName_returnsInvalidArgs" {
    run cmd_start
    assert_status "$EXIT_INVALID_ARGS"
    assert_output_contains "Usage"
}

# =============================================================================
# cmd_stop — argument validation
# =============================================================================

@test "cmd_stop_noName_returnsInvalidArgs" {
    run cmd_stop
    assert_status "$EXIT_INVALID_ARGS"
    assert_output_contains "Usage"
}

# =============================================================================
# cmd_info — argument validation
# =============================================================================

@test "cmd_info_noName_returnsInvalidArgs" {
    run cmd_info
    assert_status "$EXIT_INVALID_ARGS"
    assert_output_contains "Usage"
}

# =============================================================================
# cmd_delete — argument validation
# =============================================================================

@test "cmd_delete_noName_returnsInvalidArgs" {
    run cmd_delete
    assert_status "$EXIT_INVALID_ARGS"
    assert_output_contains "Usage"
}

# =============================================================================
# cmd_ssh — argument validation
# =============================================================================

@test "cmd_ssh_noName_returnsInvalidArgs" {
    run cmd_ssh
    assert_status "$EXIT_INVALID_ARGS"
    assert_output_contains "Usage"
}

# =============================================================================
# cmd_gpu — subcommand validation
# =============================================================================

@test "cmd_gpu_status_returnsStubMessage" {
    run cmd_gpu status
    assert_status 0
    assert_output_contains "not yet implemented"
}

@test "cmd_gpu_attach_returnsStubMessage" {
    run cmd_gpu attach
    assert_status 0
    assert_output_contains "not yet implemented"
}

@test "cmd_gpu_detach_returnsStubMessage" {
    run cmd_gpu detach
    assert_status 0
    assert_output_contains "not yet implemented"
}

@test "cmd_gpu_invalidSubcommand_returnsError" {
    run cmd_gpu nonsense
    assert_status "$EXIT_INVALID_ARGS"
    assert_output_contains "Usage"
}

@test "cmd_gpu_noSubcommand_returnsError" {
    run cmd_gpu
    assert_status "$EXIT_INVALID_ARGS"
    assert_output_contains "Usage"
}

# =============================================================================
# cmd_ip — subcommand validation
# =============================================================================

@test "cmd_ip_check_returnsStubMessage" {
    run cmd_ip check
    assert_status 0
    assert_output_contains "not yet implemented"
}

@test "cmd_ip_list_returnsStubMessage" {
    run cmd_ip list
    assert_status 0
    assert_output_contains "not yet implemented"
}

@test "cmd_ip_invalidSubcommand_returnsError" {
    run cmd_ip nonsense
    assert_status "$EXIT_INVALID_ARGS"
    assert_output_contains "Usage"
}

@test "cmd_ip_noSubcommand_returnsError" {
    run cmd_ip
    assert_status "$EXIT_INVALID_ARGS"
    assert_output_contains "Usage"
}

# =============================================================================
# cmd_create — subcommand validation
# =============================================================================

@test "cmd_create_talos_returnsStubMessage" {
    run cmd_create talos
    assert_status 0
    assert_output_contains "not yet implemented"
}

@test "cmd_create_ubuntu_returnsStubMessage" {
    run cmd_create ubuntu
    assert_status 0
    assert_output_contains "not yet implemented"
}

@test "cmd_create_invalidType_returnsError" {
    run cmd_create nonsense
    assert_status "$EXIT_INVALID_ARGS"
    assert_output_contains "Usage"
}

@test "cmd_create_noType_returnsError" {
    run cmd_create
    assert_status "$EXIT_INVALID_ARGS"
    assert_output_contains "Usage"
}

# =============================================================================
# Dispatcher routes to correct subcommand
# =============================================================================

@test "main_list_callsCmdList" {
    # Mock virsh to avoid real system interaction
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/virsh" << 'MOCK'
#!/bin/bash
echo ""
exit 0
MOCK
    chmod +x "$mock_dir/virsh"
    export PATH="$mock_dir:$PATH"

    run main list
    assert_status 0
    # Should show table header or "No VMs found"
    [[ "$output" == *"NAME"* ]] || [[ "$output" == *"No VMs"* ]]
}

@test "main_gpu_status_dispatches" {
    run main gpu status
    assert_status 0
    assert_output_contains "not yet implemented"
}

@test "main_ip_check_dispatches" {
    run main ip check
    assert_status 0
    assert_output_contains "not yet implemented"
}

@test "main_create_talos_dispatches" {
    run main create talos
    assert_status 0
    assert_output_contains "not yet implemented"
}

# =============================================================================
# _vm_exists — with mock virsh
# =============================================================================

@test "_vm_exists_knownVM_succeeds" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/virsh" << 'MOCK'
#!/bin/bash
if [[ "$1" == "dominfo" && "$2" == "test-vm" ]]; then
    echo "Id:             1"
    echo "Name:           test-vm"
    echo "State:          running"
    exit 0
fi
exit 1
MOCK
    chmod +x "$mock_dir/virsh"
    export PATH="$mock_dir:$PATH"

    run _vm_exists "test-vm"
    assert_status 0
}

@test "_vm_exists_unknownVM_fails" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/virsh" << 'MOCK'
#!/bin/bash
echo "error: failed to get domain 'no-such-vm'" >&2
exit 1
MOCK
    chmod +x "$mock_dir/virsh"
    export PATH="$mock_dir:$PATH"

    run _vm_exists "no-such-vm"
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# _vm_state — with mock virsh
# =============================================================================

@test "_vm_state_runningVM_returnsRunning" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/virsh" << 'MOCK'
#!/bin/bash
if [[ "$1" == "domstate" ]]; then
    echo "running"
    exit 0
fi
exit 1
MOCK
    chmod +x "$mock_dir/virsh"
    export PATH="$mock_dir:$PATH"

    run _vm_state "test-vm"
    assert_status 0
    [[ "$output" == "running" ]]
}

@test "_vm_state_stoppedVM_returnsShutOff" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/virsh" << 'MOCK'
#!/bin/bash
if [[ "$1" == "domstate" ]]; then
    echo "shut off"
    exit 0
fi
exit 1
MOCK
    chmod +x "$mock_dir/virsh"
    export PATH="$mock_dir:$PATH"

    run _vm_state "test-vm"
    assert_status 0
    [[ "$output" == "shut off" ]]
}

# =============================================================================
# _vm_ip — with mock virsh
# =============================================================================

@test "_vm_ip_guestAgentReturnsIP_outputsIP" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/virsh" << 'MOCK'
#!/bin/bash
if [[ "$1" == "domifaddr" && "$3" == "--source" && "$4" == "agent" ]]; then
    echo " Name       MAC address          Protocol     Address"
    echo "-------------------------------------------------------------------------------"
    echo " lo         00:00:00:00:00:00    ipv4         127.0.0.1/8"
    echo " enp1s0     52:54:00:ab:cd:ef    ipv4         192.168.122.50/24"
    exit 0
fi
echo ""
exit 0
MOCK
    chmod +x "$mock_dir/virsh"
    export PATH="$mock_dir:$PATH"

    run _vm_ip "test-vm"
    assert_status 0
    [[ "$output" == "192.168.122.50" ]]
}

@test "_vm_ip_noAgent_fallsBackToARP" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/virsh" << 'MOCK'
#!/bin/bash
if [[ "$1" == "domifaddr" && "$3" == "--source" ]]; then
    # Guest agent fails
    exit 1
fi
if [[ "$1" == "domifaddr" ]]; then
    echo " Name       MAC address          Protocol     Address"
    echo "-------------------------------------------------------------------------------"
    echo " vnet0      52:54:00:ab:cd:ef    ipv4         10.0.0.42/24"
    exit 0
fi
exit 1
MOCK
    chmod +x "$mock_dir/virsh"
    export PATH="$mock_dir:$PATH"

    run _vm_ip "test-vm"
    assert_status 0
    [[ "$output" == "10.0.0.42" ]]
}

@test "_vm_ip_noIPAvailable_returnsDash" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/virsh" << 'MOCK'
#!/bin/bash
echo ""
exit 0
MOCK
    chmod +x "$mock_dir/virsh"
    export PATH="$mock_dir:$PATH"

    run _vm_ip "test-vm"
    assert_status 0
    [[ "$output" == "—" ]]
}

# =============================================================================
# cmd_list — with mocked virsh
# =============================================================================

@test "cmd_list_noVMs_showsNoVMsMessage" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/virsh" << 'MOCK'
#!/bin/bash
if [[ "$1" == "list" ]]; then
    echo ""
    exit 0
fi
exit 0
MOCK
    chmod +x "$mock_dir/virsh"
    export PATH="$mock_dir:$PATH"

    run cmd_list
    assert_status 0
    assert_output_contains "No VMs"
}

# =============================================================================
# cmd_start — VM not found
# =============================================================================

@test "cmd_start_vmNotFound_returnsError" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/virsh" << 'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$mock_dir/virsh"
    export PATH="$mock_dir:$PATH"

    run cmd_start "no-such-vm"
    assert_status "$EXIT_VM_NOT_FOUND"
    assert_output_contains "not found"
}

# =============================================================================
# cmd_stop — VM not found
# =============================================================================

@test "cmd_stop_vmNotFound_returnsError" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/virsh" << 'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$mock_dir/virsh"
    export PATH="$mock_dir:$PATH"

    run cmd_stop "no-such-vm"
    assert_status "$EXIT_VM_NOT_FOUND"
    assert_output_contains "not found"
}

# =============================================================================
# cmd_info — VM not found
# =============================================================================

@test "cmd_info_vmNotFound_returnsError" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/virsh" << 'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$mock_dir/virsh"
    export PATH="$mock_dir:$PATH"

    run cmd_info "no-such-vm"
    assert_status "$EXIT_VM_NOT_FOUND"
    assert_output_contains "not found"
}

# =============================================================================
# cmd_delete — VM not found
# =============================================================================

@test "cmd_delete_vmNotFound_returnsError" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/virsh" << 'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$mock_dir/virsh"
    export PATH="$mock_dir:$PATH"

    run cmd_delete "no-such-vm"
    assert_status "$EXIT_VM_NOT_FOUND"
    assert_output_contains "not found"
}

# =============================================================================
# cmd_ssh — VM not found / not running
# =============================================================================

@test "cmd_ssh_vmNotFound_returnsError" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/virsh" << 'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$mock_dir/virsh"
    cat > "$mock_dir/ssh" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$mock_dir/ssh"
    export PATH="$mock_dir:$PATH"

    run cmd_ssh "no-such-vm"
    assert_status "$EXIT_VM_NOT_FOUND"
    assert_output_contains "not found"
}
