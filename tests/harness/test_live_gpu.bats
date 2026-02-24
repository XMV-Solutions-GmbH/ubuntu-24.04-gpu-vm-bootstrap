#!/usr/bin/env bats
# shellcheck disable=SC1090,SC2030,SC2031
# SPDX-License-Identifier: MIT OR Apache-2.0
# Harness tests for real NVIDIA GPU hardware
# These tests run on a dedicated machine with an actual NVIDIA GPU.
# They are READ-ONLY and do NOT modify driver bindings, VMs, or system state.
#
# Prerequisites:
#   - NVIDIA GPU present
#   - NVIDIA drivers installed (nvidia-smi working)
#   - IOMMU enabled in BIOS and kernel
#   - VFIO modules loaded
#   - KVM/libvirt installed
#
# Usage:
#   bats tests/harness/test_live_gpu.bats
#   # or:
#   ./tests/run_tests.sh harness

load '../test_helper'

setup() {
    test_setup
    export LOG_FILE="$TEST_TMP_DIR/harness-test.log"
    source "$VMCTL_SCRIPT"
}

teardown() {
    test_teardown
}

# =============================================================================
# Prerequisites — skip entire suite if hardware not available
# =============================================================================

@test "harness_prerequisite_nvidiaSmiAvailable" {
    if ! command -v nvidia-smi &>/dev/null; then
        skip "nvidia-smi not found — not an NVIDIA GPU host"
    fi
    run nvidia-smi --query-gpu=name --format=csv,noheader
    assert_status 0
    [[ -n "$output" ]]
}

@test "harness_prerequisite_lspciShowsNvidiaGPU" {
    if ! command -v lspci &>/dev/null; then
        skip "lspci not found"
    fi
    run lspci -nn
    assert_status 0
    assert_output_contains "NVIDIA"
}

@test "harness_prerequisite_kvmModuleLoaded" {
    if ! lsmod | grep -q '^kvm'; then
        skip "KVM module not loaded"
    fi
    run lsmod
    assert_status 0
    assert_output_contains "kvm"
}

@test "harness_prerequisite_vfioModuleLoaded" {
    if ! lsmod | grep -q '^vfio_pci'; then
        skip "vfio_pci module not loaded"
    fi
    run lsmod
    assert_status 0
    assert_output_contains "vfio_pci"
}

@test "harness_prerequisite_iommuEnabled" {
    local iommu_groups="/sys/kernel/iommu_groups"
    if [[ ! -d "${iommu_groups}" ]]; then
        skip "IOMMU groups not found in sysfs"
    fi
    local count
    count="$(find "${iommu_groups}" -maxdepth 1 -mindepth 1 -type d | wc -l)"
    [[ ${count} -gt 0 ]]
}

# =============================================================================
# vmctl gpu status — live system tests
# =============================================================================

@test "harness_gpuStatus_showsNvidiaGPU" {
    if ! command -v nvidia-smi &>/dev/null; then
        skip "nvidia-smi not found"
    fi

    run cmd_gpu_status
    assert_status 0
    assert_output_contains "GPU status"
    assert_output_contains "SLOT"
}

@test "harness_gpuStatus_showsVendorDeviceId" {
    if ! command -v nvidia-smi &>/dev/null; then
        skip "nvidia-smi not found"
    fi

    run cmd_gpu_status
    assert_status 0
    # NVIDIA vendor ID prefix
    assert_output_contains "10de:"
}

@test "harness_gpuStatus_showsDriverBinding" {
    if ! command -v nvidia-smi &>/dev/null; then
        skip "nvidia-smi not found"
    fi

    run cmd_gpu_status
    assert_status 0
    # Should show either nvidia or vfio-pci driver
    [[ "$output" == *"nvidia"* ]] || [[ "$output" == *"vfio-pci"* ]]
}

@test "harness_gpuStatus_showsIommuGroup" {
    if ! command -v nvidia-smi &>/dev/null; then
        skip "nvidia-smi not found"
    fi

    run cmd_gpu_status
    assert_status 0
    # IOMMU group should be a number
    [[ "$output" =~ [0-9]+ ]]
}

# =============================================================================
# GPU helper functions — live system tests
# =============================================================================

@test "harness_gpuPciSlots_returnsAtLeastOneSlot" {
    if ! command -v lspci &>/dev/null; then
        skip "lspci not found"
    fi
    if ! lspci -nn | grep -qi 'nvidia'; then
        skip "No NVIDIA GPU found"
    fi

    run _gpu_pci_slots
    assert_status 0
    [[ -n "$output" ]]
    # PCI slot format: XX:XX.X
    [[ "$output" =~ [0-9a-f]+:[0-9a-f]+\.[0-9] ]]
}

@test "harness_gpuVendorDevice_returnsNvidiaId" {
    if ! command -v lspci &>/dev/null; then
        skip "lspci not found"
    fi
    if ! lspci -nn | grep -qi 'nvidia'; then
        skip "No NVIDIA GPU found"
    fi

    local slot
    slot="$(_gpu_pci_slots | head -n1)"
    run _gpu_vendor_device "${slot}"
    assert_status 0
    assert_output_contains "10de:"
}

@test "harness_gpuCurrentDriver_returnsKnownDriver" {
    if ! command -v lspci &>/dev/null; then
        skip "lspci not found"
    fi
    if ! lspci -nn | grep -qi 'nvidia'; then
        skip "No NVIDIA GPU found"
    fi

    local slot
    slot="$(_gpu_pci_slots | head -n1)"
    run _gpu_current_driver "${slot}"
    assert_status 0
    # Should be nvidia, vfio-pci, or nouveau
    [[ "$output" == "nvidia" ]] || [[ "$output" == "vfio-pci" ]] || \
    [[ "$output" == "nouveau" ]] || [[ "$output" == "none" ]]
}

@test "harness_hasGpu_returnsTrue" {
    if ! lspci -nn 2>/dev/null | grep -i 'nvidia' | grep -qi '\[03'; then
        skip "No NVIDIA VGA/3D GPU found"
    fi

    run _has_gpu
    assert_status 0
}

# =============================================================================
# Networking helpers — live system tests
# =============================================================================

@test "harness_hostGateway_returnsValidIP" {
    run _host_gateway
    assert_status 0
    [[ -n "$output" ]]
    # Should look like an IP address
    [[ "$output" =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]
}

@test "harness_isDirectRouteMode_returnsWithoutError" {
    # Just check it runs without crashing — result depends on the host
    run _is_direct_route_mode
    # Either 0 (direct route) or 1 (standard) is valid
    [[ "$status" -eq 0 ]] || [[ "$status" -eq 1 ]]
}

# =============================================================================
# Smart defaults — live system tests
# =============================================================================

@test "harness_autoCpus_returnsReasonableNumber" {
    run _auto_cpus
    assert_status 0
    [[ "$output" =~ ^[0-9]+$ ]]
    [[ "$output" -ge 2 ]]
}

@test "harness_autoMemory_returnsReasonableNumber" {
    run _auto_memory
    assert_status 0
    [[ "$output" =~ ^[0-9]+$ ]]
    [[ "$output" -ge 2048 ]]
}

@test "harness_randomMac_generatesValidFormat" {
    run _random_mac
    assert_status 0
    [[ "$output" == 52:54:00:* ]]
    [[ ${#output} -eq 17 ]]
}

# =============================================================================
# NVIDIA extension detection — live system tests
# =============================================================================

@test "harness_nvidiaExtensionName_returnsKnownExtension" {
    if ! lspci -nn 2>/dev/null | grep -i 'nvidia' | grep -qi '\[03'; then
        skip "No NVIDIA VGA/3D GPU found"
    fi

    run _nvidia_extension_name
    assert_status 0
    [[ "$output" == "nvidia-open-gpu-kernel-modules" ]] || \
    [[ "$output" == "nonfree-kmod-nvidia" ]]
}

# =============================================================================
# vmctl ip — live system tests
# =============================================================================

@test "harness_ipList_runsWithoutError" {
    if ! command -v virsh &>/dev/null; then
        skip "virsh not found"
    fi

    run cmd_ip_list
    assert_status 0
    assert_output_contains "VM"
}

@test "harness_ipCheck_runsWithoutError" {
    run cmd_ip_check
    assert_status 0
}

# =============================================================================
# vmctl list — live system tests
# =============================================================================

@test "harness_vmctlList_runsWithoutError" {
    if ! command -v virsh &>/dev/null; then
        skip "virsh not found"
    fi

    run cmd_list
    assert_status 0
}
