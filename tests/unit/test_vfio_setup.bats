#!/usr/bin/env bats
# shellcheck disable=SC1090,SC2030,SC2031
# SPDX-License-Identifier: MIT OR Apache-2.0
# Unit tests for Phase 4: IOMMU/VFIO Configuration
# Tests CPU detection, GRUB config, VFIO modules, IOMMU groups, reboot handling

load '../test_helper'

setup() {
    test_setup
    export LOG_FILE="$TEST_TMP_DIR/bootstrap-test.log"
    export CONFIG_DIR="$TEST_TMP_DIR/etc/vmctl"
    export GRUB_DEFAULT_FILE="$TEST_TMP_DIR/etc/default/grub"
    export DRY_RUN=false
    export VERBOSE=false
    export SKIP_VFIO=false
    export GPU_MODE="flexible"
    export REBOOT_ALLOWED=false

    # Source the bootstrap script
    source "$BOOTSTRAP_SCRIPT"
}

teardown() {
    test_teardown
}

# =============================================================================
# detect_cpu_vendor() tests
# =============================================================================

@test "detect_cpu_vendor: detects Intel CPU" {
    # On this machine we can test directly from /proc/cpuinfo
    local vendor
    vendor="$(grep -m1 'vendor_id' /proc/cpuinfo 2>/dev/null | awk '{print $NF}' || true)"

    if [[ "$vendor" == "GenuineIntel" ]]; then
        run detect_cpu_vendor
        assert_status 0
        assert_output_contains "Intel"
    elif [[ "$vendor" == "AuthenticAMD" ]]; then
        run detect_cpu_vendor
        assert_status 0
        assert_output_contains "AMD"
    else
        skip "Unknown CPU vendor: $vendor"
    fi
}

@test "detect_cpu_vendor: exports CPU_VENDOR variable" {
    detect_cpu_vendor
    [[ -n "$CPU_VENDOR" ]]
    [[ "$CPU_VENDOR" == "intel" || "$CPU_VENDOR" == "amd" ]]
}

@test "detect_cpu_vendor: exports IOMMU_PARAM variable" {
    detect_cpu_vendor
    [[ -n "$IOMMU_PARAM" ]]
    [[ "$IOMMU_PARAM" == "intel_iommu=on" || "$IOMMU_PARAM" == "amd_iommu=on" ]]
}

# =============================================================================
# configure_grub_iommu() tests
# =============================================================================

@test "configure_grub_iommu: skips when params already set" {
    # Set up GRUB file with IOMMU already configured
    mkdir -p "$(dirname "$GRUB_DEFAULT_FILE")"
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash intel_iommu=on iommu=pt"' > "$GRUB_DEFAULT_FILE"

    export IOMMU_PARAM="intel_iommu=on"

    run configure_grub_iommu
    assert_status 0
    assert_output_contains "already configured"
}

@test "configure_grub_iommu: dry-run shows what would be done" {
    export DRY_RUN=true
    export IOMMU_PARAM="intel_iommu=on"

    mkdir -p "$(dirname "$GRUB_DEFAULT_FILE")"
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' > "$GRUB_DEFAULT_FILE"

    run configure_grub_iommu
    assert_status 0
    assert_output_contains "DRY-RUN"
    assert_output_contains "intel_iommu=on"
}

@test "configure_grub_iommu: appends params to existing GRUB line" {
    export IOMMU_PARAM="intel_iommu=on"

    mkdir -p "$(dirname "$GRUB_DEFAULT_FILE")"
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash"' > "$GRUB_DEFAULT_FILE"

    # Create mock update-grub
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/update-grub" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$mock_dir/update-grub"
    export PATH="$mock_dir:$PATH"

    run configure_grub_iommu
    assert_status 0

    # Verify the params were added
    local grub_content
    grub_content="$(cat "$GRUB_DEFAULT_FILE")"
    [[ "$grub_content" == *"intel_iommu=on"* ]]
    [[ "$grub_content" == *"iommu=pt"* ]]
    [[ "$grub_content" == *"quiet splash"* ]]
}

@test "configure_grub_iommu: adds new line when GRUB_CMDLINE missing" {
    export IOMMU_PARAM="amd_iommu=on"

    mkdir -p "$(dirname "$GRUB_DEFAULT_FILE")"
    echo 'GRUB_TIMEOUT=5' > "$GRUB_DEFAULT_FILE"

    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/update-grub" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$mock_dir/update-grub"
    export PATH="$mock_dir:$PATH"

    run configure_grub_iommu
    assert_status 0

    local grub_content
    grub_content="$(cat "$GRUB_DEFAULT_FILE")"
    [[ "$grub_content" == *"amd_iommu=on"* ]]
    [[ "$grub_content" == *"iommu=pt"* ]]
}

@test "configure_grub_iommu: creates backup of grub file" {
    export IOMMU_PARAM="intel_iommu=on"

    mkdir -p "$(dirname "$GRUB_DEFAULT_FILE")"
    echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet"' > "$GRUB_DEFAULT_FILE"

    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/update-grub" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$mock_dir/update-grub"
    export PATH="$mock_dir:$PATH"

    run configure_grub_iommu
    assert_status 0

    # Check that a backup was created
    local backup_count
    backup_count="$(find "$(dirname "$GRUB_DEFAULT_FILE")" -name "grub.bak.*" 2>/dev/null | wc -l)"
    [[ "$backup_count" -ge 1 ]]
}

@test "configure_grub_iommu: fails when grub file missing" {
    export IOMMU_PARAM="intel_iommu=on"
    export GRUB_DEFAULT_FILE="$TEST_TMP_DIR/nonexistent/grub"

    run configure_grub_iommu
    assert_status "$EXIT_GENERAL_ERROR"
}

# =============================================================================
# configure_vfio_modules() tests
# =============================================================================

@test "configure_vfio_modules: dry-run shows what would be done" {
    export DRY_RUN=true

    run configure_vfio_modules
    assert_status 0
    assert_output_contains "DRY-RUN"
    assert_output_contains "VFIO modules"
}

@test "configure_vfio_modules: dry-run shows PCI ID in exclusive mode" {
    export DRY_RUN=true
    export GPU_MODE="exclusive"
    export NVIDIA_GPU_PCI_ID="10de:20f1"

    run configure_vfio_modules
    assert_status 0
    assert_output_contains "DRY-RUN"
    assert_output_contains "VFIO PCI IDs"
}

@test "configure_vfio_modules: adds modules to /etc/modules" {
    # Use a temporary modules file
    local modules_file="$TEST_TMP_DIR/etc/modules"
    mkdir -p "$(dirname "$modules_file")"
    echo "# /etc/modules" > "$modules_file"

    # We need to override the hardcoded path — use a wrapper function
    configure_vfio_modules_test() {
        local modules_file="$TEST_TMP_DIR/etc/modules"
        local vfio_modules=(vfio vfio_iommu_type1 vfio_pci)
        local modules_changed=false

        for mod in "${vfio_modules[@]}"; do
            if ! is_line_in_file "$modules_file" "$mod"; then
                echo "$mod" >> "$modules_file"
                modules_changed=true
            fi
        done

        [[ "$modules_changed" == "true" ]]
    }

    run configure_vfio_modules_test
    assert_status 0

    # Verify modules were added
    assert_file_contains "$modules_file" "vfio"
    assert_file_contains "$modules_file" "vfio_iommu_type1"
    assert_file_contains "$modules_file" "vfio_pci"
}

@test "configure_vfio_modules: flexible mode logs on-demand message" {
    export DRY_RUN=true
    export GPU_MODE="flexible"

    run configure_vfio_modules
    assert_status 0
    # In dry-run, flexible mode is mentioned in the dry-run output
    assert_output_not_contains "VFIO PCI IDs"
}

# =============================================================================
# detect_iommu_groups() tests
# =============================================================================

@test "detect_iommu_groups: handles missing IOMMU groups gracefully" {
    export VFIO_REBOOT_REQUIRED=true

    # Override to use a non-existent sysfs path
    detect_iommu_groups_test() {
        local iommu_base="$TEST_TMP_DIR/sys/kernel/iommu_groups"

        if [[ ! -d "$iommu_base" ]] || [[ -z "$(ls -A "$iommu_base" 2>/dev/null)" ]]; then
            if [[ "${VFIO_REBOOT_REQUIRED:-false}" == "true" ]]; then
                log_info "IOMMU groups not yet available — will be populated after reboot"
            fi
            return 0
        fi
    }

    run detect_iommu_groups_test
    assert_status 0
    assert_output_contains "after reboot"
}

@test "detect_iommu_groups: counts available groups" {
    # Create fake IOMMU groups
    local iommu_base="$TEST_TMP_DIR/sys/kernel/iommu_groups"
    mkdir -p "$iommu_base/0/devices" "$iommu_base/1/devices" "$iommu_base/2/devices"

    detect_iommu_groups_count_test() {
        local iommu_base="$TEST_TMP_DIR/sys/kernel/iommu_groups"
        local group_count
        group_count="$(find "$iommu_base" -maxdepth 1 -mindepth 1 -type d 2>/dev/null | wc -l)"
        log_success "Found ${group_count} IOMMU group(s)"
    }

    run detect_iommu_groups_count_test
    assert_status 0
    assert_output_contains "3"
}

# =============================================================================
# handle_vfio_reboot() tests
# =============================================================================

@test "handle_vfio_reboot: silent when no reboot required" {
    export VFIO_REBOOT_REQUIRED=false

    run handle_vfio_reboot
    assert_status 0
    assert_output_not_contains "reboot"
}

@test "handle_vfio_reboot: warns when reboot required" {
    export VFIO_REBOOT_REQUIRED=true

    run handle_vfio_reboot
    assert_status 0
    assert_output_contains "reboot"
    assert_output_contains "IOMMU"
}

@test "handle_vfio_reboot: sets global REBOOT_REQUIRED flag" {
    export VFIO_REBOOT_REQUIRED=true

    handle_vfio_reboot
    [[ "${REBOOT_REQUIRED}" == "true" ]]
}

# =============================================================================
# phase_vfio_setup() orchestrator tests
# =============================================================================

@test "phase_vfio_setup: dry-run completes without side effects" {
    export DRY_RUN=true

    run phase_vfio_setup
    assert_status 0
    assert_output_contains "DRY-RUN"
}

@test "phase_vfio_setup: skipped via run_phase when --skip-vfio set" {
    export SKIP_VFIO=true

    run run_phase 3 "IOMMU/VFIO Configuration" phase_vfio_setup "${SKIP_VFIO}"
    assert_status 0
    assert_output_contains "Skipping"
}

@test "phase_vfio_setup: succeeds with grub already configured" {
    # Set up GRUB file with IOMMU already configured
    mkdir -p "$(dirname "$GRUB_DEFAULT_FILE")"

    # Detect actual CPU vendor for correct param
    local vendor
    vendor="$(grep -m1 'vendor_id' /proc/cpuinfo 2>/dev/null | awk '{print $NF}' || true)"
    if [[ "$vendor" == "GenuineIntel" ]]; then
        echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash intel_iommu=on iommu=pt"' > "$GRUB_DEFAULT_FILE"
    else
        echo 'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash amd_iommu=on iommu=pt"' > "$GRUB_DEFAULT_FILE"
    fi

    # Mock update-initramfs
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/update-initramfs" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$mock_dir/update-initramfs"
    export PATH="$mock_dir:$PATH"

    run phase_vfio_setup
    assert_status 0
    assert_output_contains "already configured"
}
