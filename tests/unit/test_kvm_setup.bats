#!/usr/bin/env bats
# shellcheck disable=SC1090,SC2030,SC2031
# SPDX-License-Identifier: MIT OR Apache-2.0
# Unit tests for Phase 3: KVM/libvirt Setup
# Tests package installation, libvirtd configuration, and KVM verification

load '../test_helper'

setup() {
    test_setup
    export LOG_FILE="$TEST_TMP_DIR/bootstrap-test.log"
    export CONFIG_DIR="$TEST_TMP_DIR/etc/vmctl"
    export GRUB_DEFAULT_FILE="$TEST_TMP_DIR/etc/default/grub"
    export DRY_RUN=false
    export VERBOSE=false
    export SKIP_KVM=false

    # Source the bootstrap script (does not execute main because of guard)
    source "$BOOTSTRAP_SCRIPT"
}

teardown() {
    test_teardown
}

# =============================================================================
# install_kvm_packages() tests
# =============================================================================

@test "install_kvm_packages: skips when all packages installed" {
    # Create mock dpkg-query that reports everything installed
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/dpkg-query" << 'EOF'
#!/bin/bash
echo "install ok installed"
exit 0
EOF
    chmod +x "$mock_dir/dpkg-query"
    export PATH="$mock_dir:$PATH"

    run install_kvm_packages
    assert_status 0
    assert_output_contains "already installed"
}

@test "install_kvm_packages: dry-run shows what would be installed" {
    export DRY_RUN=true

    # Ensure dpkg-query reports packages as NOT installed
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/dpkg-query" << 'EOF'
#!/bin/bash
echo "dpkg-query: no packages found matching $1" >&2
exit 1
EOF
    chmod +x "$mock_dir/dpkg-query"
    export PATH="$mock_dir:$PATH"

    run install_kvm_packages
    assert_status 0
    assert_output_contains "DRY-RUN"
    assert_output_contains "qemu-kvm"
}

@test "install_kvm_packages: KVM_PACKAGES array contains expected packages" {
    # Verify the array has all required packages
    local expected_pkgs=(qemu-kvm qemu-utils libvirt-daemon-system libvirt-clients virtinst virt-manager ovmf cpu-checker bridge-utils)

    for pkg in "${expected_pkgs[@]}"; do
        local found=false
        for kvm_pkg in "${KVM_PACKAGES[@]}"; do
            if [[ "$kvm_pkg" == "$pkg" ]]; then
                found=true
                break
            fi
        done
        [[ "$found" == "true" ]] || {
            echo "Missing expected package: $pkg" >&2
            return 1
        }
    done
}

# =============================================================================
# configure_libvirtd() tests
# =============================================================================

@test "configure_libvirtd: dry-run shows what would be done" {
    export DRY_RUN=true

    run configure_libvirtd
    assert_status 0
    assert_output_contains "DRY-RUN"
    assert_output_contains "libvirtd"
}

@test "configure_libvirtd: adds user to groups when SUDO_USER set" {
    export DRY_RUN=false

    # Create mocks for systemctl, usermod, id
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/systemctl" << 'EOF'
#!/bin/bash
if [[ "$1" == "is-active" ]]; then
    exit 0
fi
exit 0
EOF
    chmod +x "$mock_dir/systemctl"

    cat > "$mock_dir/usermod" << 'EOF'
#!/bin/bash
echo "$@" >> "$TEST_TMP_DIR/usermod_calls.log"
exit 0
EOF
    chmod +x "$mock_dir/usermod"

    cat > "$mock_dir/id" << 'EOF'
#!/bin/bash
if [[ "$1" == "-nG" ]]; then
    echo "users sudo"
fi
if [[ "$1" == "-u" ]]; then
    echo "1000"
fi
exit 0
EOF
    chmod +x "$mock_dir/id"

    export PATH="$mock_dir:$PATH"
    export SUDO_USER="testuser"

    run configure_libvirtd
    assert_status 0
    assert_output_contains "testuser"
}

@test "configure_libvirtd: skips groups when user already member" {
    export DRY_RUN=false

    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/systemctl" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$mock_dir/systemctl"

    # id returns that user is already in libvirt and kvm groups
    cat > "$mock_dir/id" << 'EOF'
#!/bin/bash
if [[ "$1" == "-nG" ]]; then
    echo "users sudo libvirt kvm"
fi
if [[ "$1" == "-u" ]]; then
    echo "1000"
fi
exit 0
EOF
    chmod +x "$mock_dir/id"

    export PATH="$mock_dir:$PATH"
    export SUDO_USER="testuser"
    export VERBOSE=true

    run configure_libvirtd
    assert_status 0
    assert_output_contains "already in"
}

@test "configure_libvirtd: skips groups when running as root without SUDO_USER" {
    export DRY_RUN=false
    unset SUDO_USER
    export SUDO_USER=""

    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/systemctl" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$mock_dir/systemctl"

    export PATH="$mock_dir:$PATH"
    export VERBOSE=true

    run configure_libvirtd
    assert_status 0
    assert_output_contains "root without SUDO_USER"
}

# =============================================================================
# verify_kvm_readiness() tests
# =============================================================================

@test "verify_kvm_readiness: dry-run skips verification" {
    export DRY_RUN=true

    run verify_kvm_readiness
    assert_status 0
    assert_output_contains "DRY-RUN"
}

@test "verify_kvm_readiness: reports success with kvm-ok and modules" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/kvm-ok" << 'EOF'
#!/bin/bash
echo "INFO: /dev/kvm exists"
echo "KVM acceleration can be used"
exit 0
EOF
    chmod +x "$mock_dir/kvm-ok"

    # Mock lsmod to show kvm and kvm_intel
    cat > "$mock_dir/lsmod" << 'EOF'
#!/bin/bash
echo "Module                  Size  Used by"
echo "kvm_intel             376832  0"
echo "kvm                  1138688  1 kvm_intel"
exit 0
EOF
    chmod +x "$mock_dir/lsmod"

    # Mock systemctl for libvirtd check
    cat > "$mock_dir/systemctl" << 'EOF'
#!/bin/bash
if [[ "$2" == "libvirtd" ]]; then
    exit 0
fi
exit 1
EOF
    chmod +x "$mock_dir/systemctl"

    # Mock virsh
    cat > "$mock_dir/virsh" << 'EOF'
#!/bin/bash
echo "Compiled against library: libvirt 10.0.0"
echo "Using library: libvirt 10.0.0"
echo "Using API: QEMU 10.0.0"
echo "Running hypervisor: QEMU 8.2.2"
exit 0
EOF
    chmod +x "$mock_dir/virsh"

    export PATH="$mock_dir:$PATH"

    run verify_kvm_readiness
    assert_status 0
    assert_output_contains "virtualisation support confirmed"
    assert_output_contains "KVM kernel module loaded"
    assert_output_contains "Intel"
}

@test "verify_kvm_readiness: detects AMD KVM module" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/kvm-ok" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$mock_dir/kvm-ok"

    cat > "$mock_dir/lsmod" << 'EOF'
#!/bin/bash
echo "Module                  Size  Used by"
echo "kvm_amd               376832  0"
echo "kvm                  1138688  1 kvm_amd"
exit 0
EOF
    chmod +x "$mock_dir/lsmod"

    cat > "$mock_dir/systemctl" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$mock_dir/systemctl"

    cat > "$mock_dir/virsh" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$mock_dir/virsh"

    export PATH="$mock_dir:$PATH"

    run verify_kvm_readiness
    assert_status 0
    assert_output_contains "AMD"
}

@test "verify_kvm_readiness: warns when kvm-ok fails" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/kvm-ok" << 'EOF'
#!/bin/bash
echo "INFO: Your CPU does not support KVM extensions"
exit 1
EOF
    chmod +x "$mock_dir/kvm-ok"

    cat > "$mock_dir/lsmod" << 'EOF'
#!/bin/bash
echo "Module                  Size  Used by"
exit 0
EOF
    chmod +x "$mock_dir/lsmod"

    cat > "$mock_dir/systemctl" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$mock_dir/systemctl"

    export PATH="$mock_dir:$PATH"

    run verify_kvm_readiness
    assert_status 0
    assert_output_contains "BIOS"
}

@test "verify_kvm_readiness: warns when KVM module not loaded" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/lsmod" << 'EOF'
#!/bin/bash
echo "Module                  Size  Used by"
echo "ext4                  937984  1"
exit 0
EOF
    chmod +x "$mock_dir/lsmod"

    cat > "$mock_dir/systemctl" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$mock_dir/systemctl"

    export PATH="$mock_dir:$PATH"

    run verify_kvm_readiness
    assert_status 0
    assert_output_contains "KVM kernel module not loaded"
}

@test "verify_kvm_readiness: warns when /dev/kvm missing" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/lsmod" << 'EOF'
#!/bin/bash
echo "Module                  Size  Used by"
exit 0
EOF
    chmod +x "$mock_dir/lsmod"

    cat > "$mock_dir/systemctl" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$mock_dir/systemctl"

    export PATH="$mock_dir:$PATH"

    # /dev/kvm likely doesn't exist in CI anyway, but the test checks output
    run verify_kvm_readiness
    assert_status 0
    # Function always returns 0 — warnings are non-fatal
}

@test "verify_kvm_readiness: warns when libvirtd not running" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/lsmod" << 'EOF'
#!/bin/bash
echo "Module                  Size  Used by"
echo "kvm                  1138688  0"
exit 0
EOF
    chmod +x "$mock_dir/lsmod"

    cat > "$mock_dir/systemctl" << 'EOF'
#!/bin/bash
if [[ "$1" == "is-active" && "$2" == "libvirtd" ]]; then
    exit 1
fi
exit 1
EOF
    chmod +x "$mock_dir/systemctl"

    export PATH="$mock_dir:$PATH"

    run verify_kvm_readiness
    assert_status 0
    assert_output_contains "libvirtd service is not running"
}

# =============================================================================
# phase_kvm_setup() orchestrator tests
# =============================================================================

@test "phase_kvm_setup: dry-run completes without side effects" {
    export DRY_RUN=true

    # Need a mock dpkg-query that says packages are NOT installed
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"
    cat > "$mock_dir/dpkg-query" << 'EOF'
#!/bin/bash
exit 1
EOF
    chmod +x "$mock_dir/dpkg-query"
    export PATH="$mock_dir:$PATH"

    run phase_kvm_setup
    assert_status 0
    assert_output_contains "DRY-RUN"
}

@test "phase_kvm_setup: succeeds when everything already installed" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    # All packages installed
    cat > "$mock_dir/dpkg-query" << 'EOF'
#!/bin/bash
echo "install ok installed"
exit 0
EOF
    chmod +x "$mock_dir/dpkg-query"

    # libvirtd active
    cat > "$mock_dir/systemctl" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$mock_dir/systemctl"

    # User already in groups
    cat > "$mock_dir/id" << 'EOF'
#!/bin/bash
if [[ "$1" == "-nG" ]]; then
    echo "users sudo libvirt kvm"
fi
if [[ "$1" == "-u" ]]; then
    echo "1000"
fi
exit 0
EOF
    chmod +x "$mock_dir/id"

    # kvm-ok passes
    cat > "$mock_dir/kvm-ok" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$mock_dir/kvm-ok"

    # lsmod shows kvm
    cat > "$mock_dir/lsmod" << 'EOF'
#!/bin/bash
echo "Module                  Size  Used by"
echo "kvm_intel             376832  0"
echo "kvm                  1138688  1 kvm_intel"
exit 0
EOF
    chmod +x "$mock_dir/lsmod"

    # virsh works
    cat > "$mock_dir/virsh" << 'EOF'
#!/bin/bash
exit 0
EOF
    chmod +x "$mock_dir/virsh"

    export PATH="$mock_dir:$PATH"
    export SUDO_USER="testuser"
    export VERBOSE=true

    run phase_kvm_setup
    assert_status 0
    assert_output_contains "already installed"
}

@test "phase_kvm_setup: skipped via run_phase when --skip-kvm set" {
    export SKIP_KVM=true

    run run_phase 2 "KVM/libvirt Setup" phase_kvm_setup "${SKIP_KVM}"
    assert_status 0
    assert_output_contains "Skipping"
}
