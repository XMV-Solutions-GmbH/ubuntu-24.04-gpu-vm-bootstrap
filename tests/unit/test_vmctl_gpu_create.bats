#!/usr/bin/env bats
# shellcheck disable=SC1090,SC2030,SC2031,SC2034
# SPDX-License-Identifier: MIT OR Apache-2.0
# Unit tests for vmctl GPU management, networking, smart defaults, and create
# Tests Phases 8-11 functionality with mocked system dependencies

load '../test_helper'

setup() {
    test_setup
    export LOG_FILE="$TEST_TMP_DIR/vmctl-test.log"
    export VMCTL_CONFIG_DIR="$TEST_TMP_DIR/vmctl-config"
    export VMCTL_IMAGE_DIR="$TEST_TMP_DIR/vmctl-images"
    mkdir -p "$VMCTL_CONFIG_DIR" "$VMCTL_IMAGE_DIR"
    source "$VMCTL_SCRIPT"
}

teardown() {
    test_teardown
}

# =============================================================================
# GPU Helper Functions
# =============================================================================

@test "_gpu_pci_slots_withGPU_returnsSlots" {
    local mock_dir
    mock_dir="$(mock_nvidia_gpu)"
    export PATH="$mock_dir:$PATH"

    run _gpu_pci_slots
    assert_status 0
    assert_output_contains "01:00.0"
}

@test "_gpu_pci_slots_noGPU_returnsEmpty" {
    local mock_dir
    mock_dir="$(mock_no_nvidia_gpu)"
    export PATH="$mock_dir:$PATH"

    run _gpu_pci_slots
    # Should succeed but with empty output
    [[ -z "$output" ]] || [[ "$status" -ne 0 ]]
}

@test "_gpu_vendor_device_returnsVendorDeviceId" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/lspci" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"-n"* ]] && [[ "$*" == *"-s"* ]]; then
    echo "01:00.0 0302: 10de:20f1 (rev a1)"
    exit 0
fi
echo "01:00.0 3D controller: NVIDIA Corporation GA100 [A100]"
exit 0
MOCK
    chmod +x "$mock_dir/lspci"
    export PATH="$mock_dir:$PATH"

    run _gpu_vendor_device "01:00.0"
    assert_status 0
    assert_output_contains "10de:20f1"
}

@test "_gpu_current_driver_sysfsPath_returnsDriver" {
    # Create a mock sysfs structure
    local sysfs_base="$TEST_TMP_DIR/sys/bus/pci/devices/0000:01:00.0"
    mkdir -p "$sysfs_base"
    mkdir -p "$TEST_TMP_DIR/drivers/nvidia"
    ln -sf "$TEST_TMP_DIR/drivers/nvidia" "$sysfs_base/driver"

    # Override the function to use our mock sysfs
    _gpu_current_driver() {
        local slot="$1"
        local driver_path="$TEST_TMP_DIR/sys/bus/pci/devices/0000:${slot}/driver"
        if [[ -L "${driver_path}" ]]; then
            basename "$(readlink -f "${driver_path}")"
        else
            echo "none"
        fi
    }

    run _gpu_current_driver "01:00.0"
    assert_status 0
    [[ "$output" == "nvidia" ]]
}

@test "_gpu_current_driver_noDriver_returnsNone" {
    local sysfs_base="$TEST_TMP_DIR/sys/bus/pci/devices/0000:02:00.0"
    mkdir -p "$sysfs_base"
    # No driver symlink

    _gpu_current_driver() {
        local slot="$1"
        local driver_path="$TEST_TMP_DIR/sys/bus/pci/devices/0000:${slot}/driver"
        if [[ -L "${driver_path}" ]]; then
            basename "$(readlink -f "${driver_path}")"
        else
            echo "none"
        fi
    }

    run _gpu_current_driver "02:00.0"
    assert_status 0
    [[ "$output" == "none" ]]
}

@test "_has_gpu_withNVIDIA_returnsTrue" {
    local mock_dir
    mock_dir="$(mock_nvidia_gpu)"
    export PATH="$mock_dir:$PATH"

    run _has_gpu
    assert_status 0
}

@test "_has_gpu_noNVIDIA_returnsFalse" {
    local mock_dir
    mock_dir="$(mock_no_nvidia_gpu)"
    export PATH="$mock_dir:$PATH"

    run _has_gpu
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# Networking Helper Functions
# =============================================================================

@test "_is_direct_route_mode_onlink_returnsTrue" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
echo "default via 88.198.21.129 dev enp4s0 proto static onlink"
exit 0
MOCK
    chmod +x "$mock_dir/ip"
    export PATH="$mock_dir:$PATH"

    run _is_direct_route_mode
    assert_status 0
}

@test "_is_direct_route_mode_standardRoute_returnsFalse" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
echo "default via 192.168.1.1 dev eth0 proto dhcp metric 100"
exit 0
MOCK
    chmod +x "$mock_dir/ip"
    export PATH="$mock_dir:$PATH"

    run _is_direct_route_mode
    [[ "$status" -ne 0 ]]
}

@test "_host_gateway_returnsGateway" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
echo "default via 88.198.21.129 dev enp4s0 proto static onlink"
exit 0
MOCK
    chmod +x "$mock_dir/ip"
    export PATH="$mock_dir:$PATH"

    run _host_gateway
    assert_status 0
    [[ "$output" == "88.198.21.129" ]]
}

@test "_bridge_name_withBridge_returnsBr0" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"type bridge"* ]]; then
    echo "4: br0: <BROADCAST,MULTICAST,UP,LOWER_UP>"
    exit 0
fi
echo "default via 192.168.1.1 dev eth0"
exit 0
MOCK
    chmod +x "$mock_dir/ip"
    export PATH="$mock_dir:$PATH"

    run _bridge_name
    assert_status 0
    [[ "$output" == "br0" ]]
}

@test "_bridge_name_noBridge_returnsVirbr0Fallback" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"type bridge"* ]]; then
    echo ""
    exit 0
fi
echo "default via 192.168.1.1 dev eth0"
exit 0
MOCK
    chmod +x "$mock_dir/ip"
    export PATH="$mock_dir:$PATH"

    run _bridge_name
    assert_status 0
    [[ "$output" == "br0" ]]
}

# =============================================================================
# Smart Defaults
# =============================================================================

@test "_auto_cpus_returnsHalfOfNproc" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/nproc" << 'MOCK'
#!/bin/bash
echo "20"
exit 0
MOCK
    chmod +x "$mock_dir/nproc"
    export PATH="$mock_dir:$PATH"

    run _auto_cpus
    assert_status 0
    [[ "$output" == "10" ]]
}

@test "_auto_cpus_singleCPU_returnsMinimum2" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/nproc" << 'MOCK'
#!/bin/bash
echo "1"
exit 0
MOCK
    chmod +x "$mock_dir/nproc"
    export PATH="$mock_dir:$PATH"

    run _auto_cpus
    assert_status 0
    [[ "$output" == "2" ]]
}

@test "_auto_memory_returnsHalfOfTotal" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/free" << 'MOCK'
#!/bin/bash
if [[ "$1" == "-m" ]]; then
    echo "              total        used        free      shared  buff/cache   available"
    echo "Mem:          64000       16000       32000         100       16000       47000"
    echo "Swap:          2048           0        2048"
fi
exit 0
MOCK
    chmod +x "$mock_dir/free"
    export PATH="$mock_dir:$PATH"

    run _auto_memory
    assert_status 0
    [[ "$output" == "32000" ]]
}

@test "_auto_memory_lowRAM_returnsMinimum2048" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/free" << 'MOCK'
#!/bin/bash
if [[ "$1" == "-m" ]]; then
    echo "              total        used        free      shared  buff/cache   available"
    echo "Mem:           2000        1000         500          50         500        1000"
    echo "Swap:          2048           0        2048"
fi
exit 0
MOCK
    chmod +x "$mock_dir/free"
    export PATH="$mock_dir:$PATH"

    run _auto_memory
    assert_status 0
    [[ "$output" == "2048" ]]
}

@test "_auto_name_noExistingVMs_returnsFirstName" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/virsh" << 'MOCK'
#!/bin/bash
if [[ "$1" == "list" ]]; then
    echo ""
    exit 0
fi
if [[ "$1" == "dominfo" ]]; then
    exit 1
fi
exit 0
MOCK
    chmod +x "$mock_dir/virsh"
    export PATH="$mock_dir:$PATH"

    run _auto_name "talos"
    assert_status 0
    [[ "$output" == "talos-01" ]]
}

@test "_auto_name_existingVM_incrementsNumber" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/virsh" << 'MOCK'
#!/bin/bash
if [[ "$1" == "list" ]]; then
    echo "talos-01"
    exit 0
fi
if [[ "$1" == "dominfo" ]]; then
    if [[ "$2" == "talos-01" ]]; then
        echo "Name: talos-01"
        exit 0
    fi
    exit 1
fi
exit 0
MOCK
    chmod +x "$mock_dir/virsh"
    export PATH="$mock_dir:$PATH"

    run _auto_name "talos"
    assert_status 0
    [[ "$output" == "talos-02" ]]
}

@test "_random_mac_generatesValidMAC" {
    run _random_mac
    assert_status 0
    # Should start with 52:54:00 (QEMU/KVM prefix)
    [[ "$output" == 52:54:00:* ]]
    # Should be 17 characters (xx:xx:xx:xx:xx:xx)
    [[ ${#output} -eq 17 ]]
}

# =============================================================================
# _parse_create_opts
# =============================================================================

@test "_parse_create_opts_defaultValues_appliesSmartDefaults" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/nproc" << 'MOCK'
#!/bin/bash
echo "16"
exit 0
MOCK
    chmod +x "$mock_dir/nproc"
    cat > "$mock_dir/free" << 'MOCK'
#!/bin/bash
echo "              total        used        free      shared  buff/cache   available"
echo "Mem:          32000       16000       16000         100       16000       16000"
exit 0
MOCK
    chmod +x "$mock_dir/free"
    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
echo "default via 192.168.1.1 dev eth0 proto dhcp metric 100"
exit 0
MOCK
    chmod +x "$mock_dir/ip"
    cat > "$mock_dir/lspci" << 'MOCK'
#!/bin/bash
echo "00:02.0 VGA compatible controller: Intel Corporation UHD Graphics"
exit 0
MOCK
    chmod +x "$mock_dir/lspci"
    export PATH="$mock_dir:$PATH"

    _parse_create_opts
    [[ "$VM_CPUS" == "8" ]]
    [[ "$VM_MEMORY" == "16000" ]]
    [[ "$VM_DISK" == "50" ]]
    [[ "$VM_GPU" == "none" ]]
    [[ "$VM_GATEWAY" == "192.168.1.1" ]]
    [[ -n "$VM_MAC" ]]
}

@test "_parse_create_opts_explicitValues_overridesDefaults" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
echo "default via 192.168.1.1 dev eth0 proto dhcp metric 100"
exit 0
MOCK
    chmod +x "$mock_dir/ip"
    cat > "$mock_dir/lspci" << 'MOCK'
#!/bin/bash
echo "00:02.0 VGA compatible controller: Intel"
exit 0
MOCK
    chmod +x "$mock_dir/lspci"
    export PATH="$mock_dir:$PATH"

    _parse_create_opts --name "my-vm" --cpus 4 --memory 8192 --disk 100 --no-gpu
    [[ "$VM_NAME" == "my-vm" ]]
    [[ "$VM_CPUS" == "4" ]]
    [[ "$VM_MEMORY" == "8192" ]]
    [[ "$VM_DISK" == "100" ]]
    [[ "$VM_GPU" == "none" ]]
}

@test "_parse_create_opts_directRouteMode_noMacIP_returnsError" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/nproc" << 'MOCK'
#!/bin/bash
echo "8"
exit 0
MOCK
    chmod +x "$mock_dir/nproc"
    cat > "$mock_dir/free" << 'MOCK'
#!/bin/bash
echo "              total        used        free      shared  buff/cache   available"
echo "Mem:          32000       16000       16000         100       16000       16000"
exit 0
MOCK
    chmod +x "$mock_dir/free"
    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
echo "default via 88.198.21.129 dev enp4s0 proto static onlink"
exit 0
MOCK
    chmod +x "$mock_dir/ip"
    cat > "$mock_dir/lspci" << 'MOCK'
#!/bin/bash
echo "00:02.0 VGA: Intel"
exit 0
MOCK
    chmod +x "$mock_dir/lspci"
    export PATH="$mock_dir:$PATH"

    run _parse_create_opts
    assert_status "$EXIT_INVALID_ARGS"
    assert_output_contains "--mac"
}

@test "_parse_create_opts_directRouteMode_withMacIP_succeeds" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/nproc" << 'MOCK'
#!/bin/bash
echo "8"
exit 0
MOCK
    chmod +x "$mock_dir/nproc"
    cat > "$mock_dir/free" << 'MOCK'
#!/bin/bash
echo "              total        used        free      shared  buff/cache   available"
echo "Mem:          32000       16000       16000         100       16000       16000"
exit 0
MOCK
    chmod +x "$mock_dir/free"
    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
echo "default via 88.198.21.129 dev enp4s0 proto static onlink"
exit 0
MOCK
    chmod +x "$mock_dir/ip"
    cat > "$mock_dir/lspci" << 'MOCK'
#!/bin/bash
echo "00:02.0 VGA: Intel"
exit 0
MOCK
    chmod +x "$mock_dir/lspci"
    export PATH="$mock_dir:$PATH"

    _parse_create_opts --mac "52:54:00:aa:bb:cc" --ip "1.2.3.4"
    [[ "$VM_MAC" == "52:54:00:aa:bb:cc" ]]
    [[ "$VM_IP" == "1.2.3.4" ]]
}

@test "_parse_create_opts_unknownOption_returnsError" {
    run _parse_create_opts --bogus-opt "value"
    assert_status "$EXIT_INVALID_ARGS"
    assert_output_contains "Unknown option"
}

@test "_parse_create_opts_ipAndMac_setsValues" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/nproc" << 'MOCK'
#!/bin/bash
echo "8"
exit 0
MOCK
    chmod +x "$mock_dir/nproc"
    cat > "$mock_dir/free" << 'MOCK'
#!/bin/bash
echo "              total        used        free      shared  buff/cache   available"
echo "Mem:          32000       16000       16000         100       16000       16000"
exit 0
MOCK
    chmod +x "$mock_dir/free"
    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
echo "default via 192.168.1.1 dev eth0"
exit 0
MOCK
    chmod +x "$mock_dir/ip"
    cat > "$mock_dir/lspci" << 'MOCK'
#!/bin/bash
echo "00:02.0 VGA: Intel"
exit 0
MOCK
    chmod +x "$mock_dir/lspci"
    export PATH="$mock_dir:$PATH"

    _parse_create_opts --ip "10.0.0.5" --mac "52:54:00:11:22:33" --gateway "10.0.0.1"
    [[ "$VM_IP" == "10.0.0.5" ]]
    [[ "$VM_MAC" == "52:54:00:11:22:33" ]]
    [[ "$VM_GATEWAY" == "10.0.0.1" ]]
}

# =============================================================================
# Talos Image Factory
# =============================================================================

@test "_nvidia_extension_name_turingPlus_returnsOpen" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    # RTX 4000 SFF Ada = 27b0 (Ada Lovelace, > 0x1e00)
    cat > "$mock_dir/lspci" << 'MOCK'
#!/bin/bash
echo "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation [10de:27b0] (rev a1)"
exit 0
MOCK
    chmod +x "$mock_dir/lspci"
    export PATH="$mock_dir:$PATH"

    run _nvidia_extension_name
    assert_status 0
    [[ "$output" == "nvidia-open-gpu-kernel-modules" ]]
}

@test "_nvidia_extension_name_maxwell_returnsNonfree" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    # GTX 970 = 13c2 (Maxwell, < 0x1e00)
    cat > "$mock_dir/lspci" << 'MOCK'
#!/bin/bash
echo "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GM204 [GeForce GTX 970] [10de:13c2] (rev a1)"
exit 0
MOCK
    chmod +x "$mock_dir/lspci"
    export PATH="$mock_dir:$PATH"

    run _nvidia_extension_name
    assert_status 0
    [[ "$output" == "nonfree-kmod-nvidia" ]]
}

@test "_nvidia_extension_name_pascal_returnsNonfree" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    # GTX 1080 = 1b80 (Pascal, < 0x1e00)
    cat > "$mock_dir/lspci" << 'MOCK'
#!/bin/bash
echo "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation GP104 [GeForce GTX 1080] [10de:1b80] (rev a1)"
exit 0
MOCK
    chmod +x "$mock_dir/lspci"
    export PATH="$mock_dir:$PATH"

    run _nvidia_extension_name
    assert_status 0
    [[ "$output" == "nonfree-kmod-nvidia" ]]
}

@test "_nvidia_extension_name_turing_returnsOpen" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    # RTX 2080 = 1e87 (Turing, >= 0x1e00)
    cat > "$mock_dir/lspci" << 'MOCK'
#!/bin/bash
echo "01:00.0 VGA compatible controller [0300]: NVIDIA Corporation [10de:1e87] (rev a1)"
exit 0
MOCK
    chmod +x "$mock_dir/lspci"
    export PATH="$mock_dir:$PATH"

    run _nvidia_extension_name
    assert_status 0
    [[ "$output" == "nvidia-open-gpu-kernel-modules" ]]
}

@test "_nvidia_extension_name_noGPU_defaultsToOpen" {
    local mock_dir
    mock_dir="$(mock_no_nvidia_gpu)"
    export PATH="$mock_dir:$PATH"

    run _nvidia_extension_name
    assert_status 0
    [[ "$output" == "nvidia-open-gpu-kernel-modules" ]]
}

@test "_fetch_talos_version_fromCache_returnsCachedVersion" {
    echo "v1.9.0" > "$VMCTL_IMAGE_DIR/talos-latest-version"
    # Touch with current timestamp
    touch "$VMCTL_IMAGE_DIR/talos-latest-version"

    run _fetch_talos_version
    assert_status 0
    [[ "$output" == "v1.9.0" ]]
}

# =============================================================================
# cmd_gpu subcommand dispatch
# =============================================================================

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

@test "cmd_gpu_attach_vmNotFound_returnsError" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/virsh" << 'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$mock_dir/virsh"
    export PATH="$mock_dir:$PATH"

    run cmd_gpu_attach "nonexistent-vm"
    assert_status "$EXIT_VM_NOT_FOUND"
    assert_output_contains "not found"
}

@test "cmd_gpu_detach_vmNotFound_returnsError" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/virsh" << 'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$mock_dir/virsh"
    export PATH="$mock_dir:$PATH"

    run cmd_gpu_detach "nonexistent-vm"
    assert_status "$EXIT_VM_NOT_FOUND"
    assert_output_contains "not found"
}

# =============================================================================
# cmd_ip subcommand dispatch
# =============================================================================

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
# cmd_create subcommand dispatch
# =============================================================================

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

@test "cmd_create_talos_vmAlreadyExists_returnsError" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/nproc" << 'MOCK'
#!/bin/bash
echo "8"
exit 0
MOCK
    chmod +x "$mock_dir/nproc"
    cat > "$mock_dir/free" << 'MOCK'
#!/bin/bash
echo "              total        used        free      shared  buff/cache   available"
echo "Mem:          32000       16000       16000         100       16000       16000"
exit 0
MOCK
    chmod +x "$mock_dir/free"
    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
echo "default via 192.168.1.1 dev eth0"
exit 0
MOCK
    chmod +x "$mock_dir/ip"
    cat > "$mock_dir/lspci" << 'MOCK'
#!/bin/bash
echo "00:02.0 VGA: Intel"
exit 0
MOCK
    chmod +x "$mock_dir/lspci"
    cat > "$mock_dir/virsh" << 'MOCK'
#!/bin/bash
if [[ "$1" == "dominfo" && "$2" == "my-existing-vm" ]]; then
    echo "Name: my-existing-vm"
    exit 0
fi
if [[ "$1" == "list" ]]; then
    echo ""
    exit 0
fi
exit 1
MOCK
    chmod +x "$mock_dir/virsh"
    cat > "$mock_dir/virt-install" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$mock_dir/virt-install"
    export PATH="$mock_dir:$PATH"

    run cmd_create_talos --name "my-existing-vm"
    assert_status "$EXIT_GENERAL_ERROR"
    assert_output_contains "already exists"
}

# =============================================================================
# cmd_ip_list — with VMs
# =============================================================================

@test "cmd_ip_list_withVMs_showsTable" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/virsh" << 'MOCK'
#!/bin/bash
if [[ "$1" == "list" ]]; then
    echo "talos-01"
    echo "talos-02"
    exit 0
fi
if [[ "$1" == "domstate" ]]; then
    if [[ "$2" == "talos-01" ]]; then
        echo "running"
        exit 0
    fi
    echo "shut off"
    exit 0
fi
if [[ "$1" == "domifaddr" ]]; then
    if [[ "$2" == "talos-01" ]]; then
        echo " Name       MAC address          Protocol     Address"
        echo "-------------------------------------------------------------------------------"
        echo " enp1s0     52:54:00:ab:cd:ef    ipv4         10.0.0.10/24"
        exit 0
    fi
    echo ""
    exit 0
fi
exit 0
MOCK
    chmod +x "$mock_dir/virsh"
    export PATH="$mock_dir:$PATH"

    run cmd_ip_list
    assert_status 0
    assert_output_contains "talos-01"
    assert_output_contains "talos-02"
}

# =============================================================================
# show_usage — updated content checks
# =============================================================================

@test "show_usage_containsCreateOptions" {
    run show_usage
    assert_status 0
    assert_output_contains "--name"
    assert_output_contains "--cpus"
    assert_output_contains "--memory"
    assert_output_contains "--disk"
    assert_output_contains "--no-gpu"
    assert_output_contains "--ip"
    assert_output_contains "--mac"
    assert_output_contains "--gateway"
    assert_output_contains "--talos-version"
}

@test "show_usage_containsGPUCommands" {
    run show_usage
    assert_status 0
    assert_output_contains "gpu    status"
    assert_output_contains "gpu    attach"
    assert_output_contains "gpu    detach"
}

@test "show_usage_containsExamples" {
    run show_usage
    assert_status 0
    assert_output_contains "vmctl create talos"
    assert_output_contains "vmctl create ubuntu"
}

# =============================================================================
# Ubuntu ISO Download Helpers
# =============================================================================

@test "_fetch_ubuntu_iso_name_parsesIndexPage" {
    # Mock curl to return a fake directory listing
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/curl" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"-fsSL"* ]]; then
    cat << 'HTML'
<a href="ubuntu-25.10-desktop-amd64.iso">ubuntu-25.10-desktop-amd64.iso</a>
HTML
    exit 0
fi
exit 0
MOCK
    chmod +x "$mock_dir/curl"
    export PATH="$mock_dir:$PATH"

    run _fetch_ubuntu_iso_name "25.10"
    assert_status 0
    assert_output_contains "ubuntu-25.10-desktop-amd64.iso"
}

@test "_fetch_ubuntu_iso_name_noISOFound_returnsError" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/curl" << 'MOCK'
#!/bin/bash
echo "<html>empty page</html>"
exit 0
MOCK
    chmod +x "$mock_dir/curl"
    export PATH="$mock_dir:$PATH"

    run _fetch_ubuntu_iso_name "99.99"
    assert_status 1
}

@test "_download_ubuntu_iso_usesCachedISO" {
    # Place a fake cached ISO
    touch "$VMCTL_IMAGE_DIR/ubuntu-25.10-desktop-amd64.iso"

    run _download_ubuntu_iso
    assert_status 0
    assert_output_contains "Using cached"
    assert_output_contains "ubuntu-25.10-desktop-amd64.iso"
}

@test "_download_ubuntu_iso_noCachedISO_triggersDownload" {
    # Mock curl for both index page and download
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/curl" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"-fsSL"* ]]; then
    cat << 'HTML'
<a href="ubuntu-25.10-desktop-amd64.iso">ubuntu-25.10-desktop-amd64.iso</a>
HTML
    exit 0
fi
if [[ "$*" == *"-fSL"* ]] && [[ "$*" == *"--progress-bar"* ]]; then
    # Fake download — extract -o argument to create file
    local outfile=""
    local prev=""
    for arg in $@; do
        if [[ "$prev" == "-o" ]]; then
            outfile="$arg"
            break
        fi
        prev="$arg"
    done
    if [[ -n "$outfile" ]]; then
        echo "fake-iso-content" > "$outfile"
    fi
    exit 0
fi
exit 0
MOCK
    chmod +x "$mock_dir/curl"
    export PATH="$mock_dir:$PATH"

    run _download_ubuntu_iso
    assert_status 0
    assert_output_contains "Downloading Ubuntu"
    assert_output_contains "Ubuntu ISO ready"
}

@test "_host_prefix_len_returns32ForDirectRoute" {
    # Mock ip command to return /32
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"addr show"* ]]; then
    echo "    inet 88.198.21.134/32 scope global enp4s0"
    exit 0
fi
exit 0
MOCK
    chmod +x "$mock_dir/ip"
    export PATH="$mock_dir:$PATH"

    run _host_prefix_len
    assert_status 0
    [[ "$output" == "32" ]]
}

@test "_host_prefix_len_returns28ForSubnet" {
    # Mock ip command to return /28
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"addr show"* ]]; then
    echo "    inet 88.198.27.122/28 scope global enp4s0"
    exit 0
fi
exit 0
MOCK
    chmod +x "$mock_dir/ip"
    export PATH="$mock_dir:$PATH"

    run _host_prefix_len
    assert_status 0
    [[ "$output" == "28" ]]
}
