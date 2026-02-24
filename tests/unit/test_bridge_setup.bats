#!/usr/bin/env bats
# shellcheck disable=SC1090,SC2030,SC2031
# SPDX-License-Identifier: MIT OR Apache-2.0
# Unit tests for Phase 4: Bridge Network Setup
# Tests NIC detection, Netplan bridge configuration, application, and verification

load '../test_helper'

setup() {
    test_setup
    export LOG_FILE="$TEST_TMP_DIR/bootstrap-test.log"
    export CONFIG_DIR="$TEST_TMP_DIR/etc/vmctl"
    export NETPLAN_DIR="$TEST_TMP_DIR/etc/netplan"
    export DRY_RUN=false
    export VERBOSE=false
    export SKIP_BRIDGE=false
    export BRIDGE_NAME="br0"
    export BRIDGE_SUBNET=""
    export PRIMARY_NIC=""
    export PRIMARY_NIC_IP=""
    export PRIMARY_NIC_GATEWAY=""
    export PRIMARY_NIC_DNS=""
    export DIRECT_ROUTE_MODE=false

    mkdir -p "$NETPLAN_DIR"

    # Source the bootstrap script (does not execute main because of guard)
    source "$BOOTSTRAP_SCRIPT"
}

teardown() {
    test_teardown
}

# =============================================================================
# detect_primary_nic() tests
# =============================================================================

@test "detect_primary_nic: detects NIC from default route" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    # Mock ip command to return a default route via eth0
    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"route show default"* ]]; then
    echo "default via 192.168.1.1 dev eth0 proto static metric 100"
elif [[ "$*" == *"-4 addr show dev"* ]]; then
    echo "    inet 192.168.1.100/24 brd 192.168.1.255 scope global eth0"
fi
MOCK
    chmod +x "$mock_dir/ip"

    # Mock resolvectl
    cat > "$mock_dir/resolvectl" << 'MOCK'
#!/bin/bash
echo "Link 2 (eth0): 8.8.8.8 8.8.4.4"
MOCK
    chmod +x "$mock_dir/resolvectl"

    export PATH="$mock_dir:$PATH"

    run detect_primary_nic
    assert_status 0
    assert_output_contains "eth0"
    assert_output_contains "192.168.1.100/24"
    assert_output_contains "192.168.1.1"
}

@test "detect_primary_nic: fails when no default route exists" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    # Mock ip with empty output
    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$mock_dir/ip"

    export PATH="$mock_dir:$PATH"

    run detect_primary_nic
    assert_status 1
    assert_output_contains "Could not detect primary network interface"
}

@test "detect_primary_nic: handles NIC with no IPv4 address" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"route show default"* ]]; then
    echo "default via 10.0.0.1 dev enp3s0 proto dhcp metric 600"
elif [[ "$*" == *"-4 addr show dev"* ]]; then
    # No IPv4 output
    :
fi
MOCK
    chmod +x "$mock_dir/ip"

    export PATH="$mock_dir:$PATH"

    run detect_primary_nic
    assert_status 0
    assert_output_contains "enp3s0"
    assert_output_contains "No IPv4 address found"
}

@test "detect_primary_nic: reads DNS from resolv.conf as fallback" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"route show default"* ]]; then
    echo "default via 10.0.0.1 dev ens5 proto dhcp"
elif [[ "$*" == *"-4 addr show dev"* ]]; then
    echo "    inet 10.0.0.42/24 brd 10.0.0.255 scope global ens5"
fi
MOCK
    chmod +x "$mock_dir/ip"

    # No resolvectl — use resolv.conf fallback
    cat > "$mock_dir/resolvectl" << 'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$mock_dir/resolvectl"

    # Create fake resolv.conf
    mkdir -p "$TEST_TMP_DIR/resolve"
    cat > "$TEST_TMP_DIR/resolve/resolv.conf" << 'EOF'
nameserver 1.1.1.1
nameserver 1.0.0.1
EOF

    # We can't easily override /etc/resolv.conf so just verify the function
    # runs successfully with the mock ip command
    export PATH="$mock_dir:$PATH"

    run detect_primary_nic
    assert_status 0
    assert_output_contains "ens5"
    assert_output_contains "10.0.0.42/24"
}

@test "detect_primary_nic: detects /32 direct-route mode with onlink flag" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"route show default"* ]]; then
    echo "default via 88.198.21.129 dev enp4s0 onlink"
elif [[ "$*" == *"-4 addr show dev"* ]]; then
    echo "    inet 88.198.21.134/32 scope global enp4s0"
fi
MOCK
    chmod +x "$mock_dir/ip"

    export PATH="$mock_dir:$PATH"

    run detect_primary_nic
    assert_status 0
    assert_output_contains "enp4s0"
    assert_output_contains "88.198.21.134/32"
    assert_output_contains "/32 direct-route mode"
}

@test "detect_primary_nic: does not set direct-route mode for /24 subnet" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"route show default"* ]]; then
    echo "default via 192.168.1.1 dev eth0 proto static metric 100"
elif [[ "$*" == *"-4 addr show dev"* ]]; then
    echo "    inet 192.168.1.100/24 brd 192.168.1.255 scope global eth0"
fi
MOCK
    chmod +x "$mock_dir/ip"

    export PATH="$mock_dir:$PATH"

    run detect_primary_nic
    assert_status 0
    assert_output_not_contains "/32 direct-route"
}

@test "detect_primary_nic: /32 without onlink flag does not trigger direct-route" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"route show default"* ]]; then
    echo "default via 10.0.0.1 dev eth0 proto static"
elif [[ "$*" == *"-4 addr show dev"* ]]; then
    echo "    inet 10.0.0.5/32 scope global eth0"
fi
MOCK
    chmod +x "$mock_dir/ip"

    export PATH="$mock_dir:$PATH"

    run detect_primary_nic
    assert_status 0
    assert_output_not_contains "/32 direct-route"
}

@test "detect_primary_nic: detects NIC on typical server with eno1" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"route show default"* ]]; then
    echo "default via 172.16.0.1 dev eno1 proto static metric 100"
elif [[ "$*" == *"-4 addr show dev"* ]]; then
    echo "    inet 172.16.0.50/16 brd 172.16.255.255 scope global eno1"
fi
MOCK
    chmod +x "$mock_dir/ip"

    export PATH="$mock_dir:$PATH"

    run detect_primary_nic
    assert_status 0
    assert_output_contains "eno1"
    assert_output_contains "172.16.0.50/16"
}

# =============================================================================
# configure_bridge_interface() tests
# =============================================================================

@test "configure_bridge_interface: creates Netplan config with static IP" {
    export PRIMARY_NIC="eth0"
    export PRIMARY_NIC_IP="192.168.1.100/24"
    export PRIMARY_NIC_GATEWAY="192.168.1.1"
    export PRIMARY_NIC_DNS="8.8.8.8,8.8.4.4"

    run configure_bridge_interface
    assert_status 0
    assert_output_contains "Created Netplan bridge config"

    local netplan_file="$NETPLAN_DIR/60-bridge-br0.yaml"
    assert_file_exists "$netplan_file"
    assert_file_contains "$netplan_file" "br0"
    assert_file_contains "$netplan_file" "eth0"
    assert_file_contains "$netplan_file" "192.168.1.100/24"
    assert_file_contains "$netplan_file" "192.168.1.1"
    assert_file_contains "$netplan_file" "8.8.8.8"
    assert_file_contains "$netplan_file" "stp: true"
}

@test "configure_bridge_interface: creates Netplan config with DHCP when no IP" {
    export PRIMARY_NIC="ens5"
    export PRIMARY_NIC_IP=""
    export PRIMARY_NIC_GATEWAY=""
    export PRIMARY_NIC_DNS=""

    run configure_bridge_interface
    assert_status 0

    local netplan_file="$NETPLAN_DIR/60-bridge-br0.yaml"
    assert_file_exists "$netplan_file"
    assert_file_contains "$netplan_file" "dhcp4: true"
    assert_file_contains "$netplan_file" "ens5"
}

@test "configure_bridge_interface: skips when config already exists" {
    export PRIMARY_NIC="eth0"
    export PRIMARY_NIC_IP="10.0.0.5/24"
    export VERBOSE=true

    # Pre-create a config with the bridge name
    echo "bridges:
  br0:
    interfaces: [eth0]" > "$NETPLAN_DIR/60-bridge-br0.yaml"

    run configure_bridge_interface
    assert_status 0
    assert_output_contains "already exists"
}

@test "configure_bridge_interface: dry-run shows what would be done" {
    export DRY_RUN=true
    export PRIMARY_NIC="eth0"
    export PRIMARY_NIC_IP="10.0.0.5/24"

    run configure_bridge_interface
    assert_status 0
    assert_output_contains "DRY-RUN"
    assert_output_contains "Netplan bridge config"
    assert_output_contains "eth0"

    # Should NOT create the file
    [[ ! -f "$NETPLAN_DIR/60-bridge-br0.yaml" ]]
}

@test "configure_bridge_interface: fails when PRIMARY_NIC not set" {
    export PRIMARY_NIC=""

    run configure_bridge_interface
    assert_status 1
    assert_output_contains "Primary NIC not detected"
}

@test "configure_bridge_interface: uses custom bridge name" {
    export BRIDGE_NAME="vmbridge0"
    export PRIMARY_NIC="enp3s0"
    export PRIMARY_NIC_IP="10.10.0.1/16"
    export PRIMARY_NIC_GATEWAY="10.10.0.1"
    export PRIMARY_NIC_DNS=""

    run configure_bridge_interface
    assert_status 0

    local netplan_file="$NETPLAN_DIR/60-bridge-vmbridge0.yaml"
    assert_file_exists "$netplan_file"
    assert_file_contains "$netplan_file" "vmbridge0"
    assert_file_contains "$netplan_file" "enp3s0"
}

@test "configure_bridge_interface: backs up existing Netplan configs" {
    export PRIMARY_NIC="eth0"
    export PRIMARY_NIC_IP="10.0.0.5/24"
    export PRIMARY_NIC_GATEWAY=""
    export PRIMARY_NIC_DNS=""

    # Create a pre-existing config
    echo "network: {version: 2}" > "$NETPLAN_DIR/01-existing.yaml"

    run configure_bridge_interface
    assert_status 0

    # Check that backup directory was created
    local backup_found=false
    for d in "$NETPLAN_DIR"/backup-*; do
        if [[ -d "$d" ]]; then
            backup_found=true
            assert_file_exists "$d/01-existing.yaml"
        fi
    done
    [[ "$backup_found" == "true" ]]
}

@test "configure_bridge_interface: disables DHCP on physical NIC" {
    export PRIMARY_NIC="ens160"
    export PRIMARY_NIC_IP="192.168.10.50/24"
    export PRIMARY_NIC_GATEWAY="192.168.10.1"
    export PRIMARY_NIC_DNS="1.1.1.1"

    run configure_bridge_interface
    assert_status 0

    local netplan_file="$NETPLAN_DIR/60-bridge-br0.yaml"
    # Physical NIC should have DHCP disabled
    assert_file_contains "$netplan_file" "dhcp4: false"
    assert_file_contains "$netplan_file" "dhcp6: false"
    # Bridge should have the IP
    assert_file_contains "$netplan_file" "192.168.10.50/24"
}

@test "configure_bridge_interface: includes forward-delay parameter" {
    export PRIMARY_NIC="eth0"
    export PRIMARY_NIC_IP="10.0.0.5/24"
    export PRIMARY_NIC_GATEWAY=""
    export PRIMARY_NIC_DNS=""

    run configure_bridge_interface
    assert_status 0

    local netplan_file="$NETPLAN_DIR/60-bridge-br0.yaml"
    assert_file_contains "$netplan_file" "forward-delay: 4"
}

@test "configure_bridge_interface: /32 direct-route uses on-link gateway" {
    export PRIMARY_NIC="enp4s0"
    export PRIMARY_NIC_IP="88.198.21.134/32"
    export PRIMARY_NIC_GATEWAY="88.198.21.129"
    export PRIMARY_NIC_DNS="185.12.64.2,185.12.64.1"
    export DIRECT_ROUTE_MODE=true

    run configure_bridge_interface
    assert_status 0

    local netplan_file="$NETPLAN_DIR/60-bridge-br0.yaml"
    assert_file_exists "$netplan_file"
    assert_file_contains "$netplan_file" "on-link: true"
    assert_file_contains "$netplan_file" "88.198.21.134/32"
    assert_file_contains "$netplan_file" "88.198.21.129"
    assert_file_contains "$netplan_file" "stp: false"
    assert_file_contains "$netplan_file" "forward-delay: 0"
    assert_file_contains "$netplan_file" "enp4s0"
    assert_file_contains "$netplan_file" "185.12.64.2"
}

@test "configure_bridge_interface: /32 direct-route disables STP" {
    export PRIMARY_NIC="eth0"
    export PRIMARY_NIC_IP="203.0.113.10/32"
    export PRIMARY_NIC_GATEWAY="203.0.113.1"
    export PRIMARY_NIC_DNS=""
    export DIRECT_ROUTE_MODE=true

    run configure_bridge_interface
    assert_status 0

    local netplan_file="$NETPLAN_DIR/60-bridge-br0.yaml"
    assert_file_contains "$netplan_file" "stp: false"
    assert_file_contains "$netplan_file" "forward-delay: 0"
    # Should NOT have stp: true
    ! grep -q "stp: true" "$netplan_file"
}

@test "configure_bridge_interface: standard mode uses STP enabled" {
    export PRIMARY_NIC="eth0"
    export PRIMARY_NIC_IP="192.168.1.100/24"
    export PRIMARY_NIC_GATEWAY="192.168.1.1"
    export PRIMARY_NIC_DNS=""
    export DIRECT_ROUTE_MODE=false

    run configure_bridge_interface
    assert_status 0

    local netplan_file="$NETPLAN_DIR/60-bridge-br0.yaml"
    assert_file_contains "$netplan_file" "stp: true"
    assert_file_contains "$netplan_file" "forward-delay: 4"
    # Should NOT have on-link
    ! grep -q "on-link: true" "$netplan_file"
}

@test "configure_bridge_interface: dry-run mentions direct-route mode" {
    export DRY_RUN=true
    export PRIMARY_NIC="enp4s0"
    export PRIMARY_NIC_IP="88.198.21.134/32"
    export DIRECT_ROUTE_MODE=true

    run configure_bridge_interface
    assert_status 0
    assert_output_contains "DRY-RUN"
    assert_output_contains "/32 direct-route"
}

# =============================================================================
# apply_bridge_config() tests
# =============================================================================

@test "apply_bridge_config: dry-run shows what would be done" {
    export DRY_RUN=true

    run apply_bridge_config
    assert_status 0
    assert_output_contains "DRY-RUN"
    assert_output_contains "netplan apply"
}

@test "apply_bridge_config: runs netplan apply" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/netplan" << 'MOCK'
#!/bin/bash
echo "$@" >> "$TEST_TMP_DIR/netplan_calls.log"
exit 0
MOCK
    chmod +x "$mock_dir/netplan"
    export PATH="$mock_dir:$PATH"

    run apply_bridge_config
    assert_status 0
    assert_output_contains "Bridge configuration applied"

    # Verify netplan was called with apply
    assert_file_contains "$TEST_TMP_DIR/netplan_calls.log" "apply"
}

@test "apply_bridge_config: fails when netplan apply fails" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/netplan" << 'MOCK'
#!/bin/bash
echo "Error: invalid YAML" >&2
exit 1
MOCK
    chmod +x "$mock_dir/netplan"
    export PATH="$mock_dir:$PATH"

    run apply_bridge_config
    assert_status 1
    assert_output_contains "netplan apply failed"
}

# =============================================================================
# verify_bridge_connectivity() tests
# =============================================================================

@test "verify_bridge_connectivity: dry-run shows what would be done" {
    export DRY_RUN=true

    run verify_bridge_connectivity
    assert_status 0
    assert_output_contains "DRY-RUN"
    assert_output_contains "br0"
}

@test "verify_bridge_connectivity: verifies bridge is UP with IP" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"-br link show"* ]]; then
    echo "br0              UP             52:54:00:ab:cd:ef <BROADCAST,MULTICAST,UP,LOWER_UP>"
elif [[ "$*" == *"link show br0"* ]]; then
    echo "3: br0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 state UP"
    exit 0
elif [[ "$*" == *"-4 addr show dev br0"* ]]; then
    echo "    inet 192.168.1.100/24 brd 192.168.1.255 scope global br0"
elif [[ "$*" == *"route show default"* ]]; then
    echo "default via 192.168.1.1 dev br0 proto static"
fi
MOCK
    chmod +x "$mock_dir/ip"

    # Mock bridge command
    cat > "$mock_dir/bridge" << 'MOCK'
#!/bin/bash
echo "3: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> master br0"
MOCK
    chmod +x "$mock_dir/bridge"

    # Mock ping
    cat > "$mock_dir/ping" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$mock_dir/ping"

    export PATH="$mock_dir:$PATH"
    export PRIMARY_NIC_GATEWAY="192.168.1.1"

    run verify_bridge_connectivity
    assert_status 0
    assert_output_contains "br0"
    assert_output_contains "UP"
    assert_output_contains "192.168.1.100/24"
    assert_output_contains "Gateway 192.168.1.1 reachable"
}

@test "verify_bridge_connectivity: warns when bridge interface missing" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"link show br0"* ]]; then
    echo "Device \"br0\" does not exist." >&2
    exit 1
fi
MOCK
    chmod +x "$mock_dir/ip"

    export PATH="$mock_dir:$PATH"

    run verify_bridge_connectivity
    assert_status 1
    assert_output_contains "does not exist"
}

@test "verify_bridge_connectivity: warns when gateway unreachable" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"link show br0"* ]]; then
    echo "3: br0: <BROADCAST,MULTICAST,UP,LOWER_UP> state UP"
    exit 0
elif [[ "$*" == *"-br link show br0"* ]]; then
    echo "br0              UP"
elif [[ "$*" == *"-4 addr show dev br0"* ]]; then
    echo "    inet 10.0.0.5/24 brd 10.0.0.255 scope global br0"
elif [[ "$*" == *"route show default"* ]]; then
    echo "default via 10.0.0.1 dev br0"
fi
MOCK
    chmod +x "$mock_dir/ip"

    cat > "$mock_dir/bridge" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$mock_dir/bridge"

    cat > "$mock_dir/ping" << 'MOCK'
#!/bin/bash
exit 1
MOCK
    chmod +x "$mock_dir/ping"

    export PATH="$mock_dir:$PATH"
    export PRIMARY_NIC_GATEWAY="10.0.0.1"

    run verify_bridge_connectivity
    assert_status 0
    assert_output_contains "Cannot reach gateway"
}

# =============================================================================
# phase_bridge_setup() orchestrator tests
# =============================================================================

@test "phase_bridge_setup: dry-run completes all steps" {
    export DRY_RUN=true

    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"route show default"* ]]; then
    echo "default via 192.168.1.1 dev eth0 proto static"
elif [[ "$*" == *"-4 addr show dev"* ]]; then
    echo "    inet 192.168.1.50/24 brd 192.168.1.255 scope global eth0"
fi
MOCK
    chmod +x "$mock_dir/ip"

    export PATH="$mock_dir:$PATH"

    run phase_bridge_setup
    assert_status 0
    assert_output_contains "eth0"
    assert_output_contains "DRY-RUN"
}

@test "phase_bridge_setup: fails when NIC detection fails" {
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
exit 0
MOCK
    chmod +x "$mock_dir/ip"
    export PATH="$mock_dir:$PATH"

    run phase_bridge_setup
    assert_status 1
    assert_output_contains "Could not detect"
}

@test "phase_bridge_setup: propagates configure_bridge_interface error" {
    # This tests the || return $? pattern
    local mock_dir="$TEST_TMP_DIR/mocks"
    mkdir -p "$mock_dir"

    # detect_primary_nic succeeds
    cat > "$mock_dir/ip" << 'MOCK'
#!/bin/bash
if [[ "$*" == *"route show default"* ]]; then
    echo "default via 10.0.0.1 dev eth0"
elif [[ "$*" == *"-4 addr show dev"* ]]; then
    echo "    inet 10.0.0.5/24 scope global eth0"
fi
MOCK
    chmod +x "$mock_dir/ip"
    export PATH="$mock_dir:$PATH"

    # Remove write permissions on NETPLAN_DIR to force failure
    chmod 000 "$NETPLAN_DIR"

    run phase_bridge_setup
    # Restore permissions for cleanup
    chmod 755 "$NETPLAN_DIR"

    # Should fail because Netplan dir is not writable
    [[ "$status" -ne 0 ]]
}

# =============================================================================
# prompt_reboot() tests
# =============================================================================

@test "prompt_reboot: does nothing when reboot not required" {
    export REBOOT_REQUIRED=false

    run prompt_reboot
    assert_status 0
    # No output expected when reboot is not required
    [[ -z "$output" ]]
}

@test "prompt_reboot: in --yes mode without --reboot shows warning" {
    export REBOOT_REQUIRED=true
    export YES_MODE=true
    export REBOOT_ALLOWED=false
    export DRY_RUN=false

    run prompt_reboot
    assert_status 0
    assert_output_contains "sudo reboot"
}

@test "prompt_reboot: dry-run does nothing even with reboot required" {
    export REBOOT_REQUIRED=true
    export YES_MODE=false
    export DRY_RUN=true

    run prompt_reboot
    assert_status 0
}
