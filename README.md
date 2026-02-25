<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Ubuntu 24.04 GPU VM Bootstrap

[![CI](https://github.com/XMV-Solutions-GmbH/ubuntu-24.04-gpu-vm-bootstrap/actions/workflows/test.yml/badge.svg)](https://github.com/XMV-Solutions-GmbH/ubuntu-24.04-gpu-vm-bootstrap/actions/workflows/test.yml)
[![Licence](https://img.shields.io/badge/licence-MIT%2FApache--2.0-blue.svg)](LICENSE)
[![GitHub release](https://img.shields.io/github/v/release/XMV-Solutions-GmbH/ubuntu-24.04-gpu-vm-bootstrap)](https://github.com/XMV-Solutions-GmbH/ubuntu-24.04-gpu-vm-bootstrap/releases)
[![Contributions Welcome](https://img.shields.io/badge/contributions-welcome-brightgreen.svg)](CONTRIBUTING.md)

**One-command GPU workstation setup for Ubuntu 24.04.**

Installs NVIDIA drivers, CUDA toolkit, KVM/libvirt virtualisation, IOMMU/VFIO
GPU passthrough, bridge networking, and the `vmctl` CLI — all with a single
`curl | bash` command.

---

## Features

- **One-liner install** — `curl | bash` from latest GitHub release
- **NVIDIA GPU setup** — Drivers, CUDA toolkit, `nvidia-container-toolkit`
- **KVM virtualisation** — QEMU, libvirt, `virt-install` ready to go
- **GPU passthrough** — IOMMU/VFIO configuration for PCI passthrough
- **Dual GPU mode** — Exclusive VFIO passthrough or flexible host + VM sharing
- **Bridge networking** — Bridged network with automatic free-IP detection
- **`vmctl` CLI** — Simplified VM management (Talos Linux, Ubuntu Desktop)
- **Talos Linux support** — Auto-fetches latest version, generates NVIDIA-enabled
  image via Talos Image Factory
- **Ubuntu Desktop VMs** — Ubuntu 25.10 with Cloud-Init and GPU passthrough
- **Idempotent** — Safe to re-run, only changes what is needed

## Non-Goals

- Windows or macOS host support
- Non-systemd init systems
- Non-NVIDIA GPU support (AMD ROCm may follow later)

---

## Quick Start

```bash
# One-liner install (latest release)
curl -fsSL https://github.com/XMV-Solutions-GmbH/ubuntu-24.04-gpu-vm-bootstrap/releases/latest/download/gpu-vm-bootstrap.sh | sudo bash
```

```bash
# Or download and review first
curl -fsSL https://github.com/XMV-Solutions-GmbH/ubuntu-24.04-gpu-vm-bootstrap/releases/latest/download/gpu-vm-bootstrap.sh -o gpu-vm-bootstrap.sh
chmod +x gpu-vm-bootstrap.sh
less gpu-vm-bootstrap.sh   # Review the script
sudo ./gpu-vm-bootstrap.sh
```

### What happens

1. Updates system packages and installs essential tools
2. Installs NVIDIA drivers and CUDA toolkit
3. Sets up KVM/QEMU and libvirt
4. Configures IOMMU and VFIO for GPU passthrough
5. Creates a bridge network interface
6. Installs `vmctl` CLI to `/usr/local/bin/`

> **Note:** A reboot is required after first run to activate IOMMU and VFIO
> kernel parameters.

---

## Bootstrap Script Options

```text
gpu-vm-bootstrap.sh [OPTIONS]

Options:
  --skip-nvidia       Skip NVIDIA driver installation
  --skip-kvm          Skip KVM/libvirt setup
  --skip-vfio         Skip IOMMU/VFIO configuration
  --skip-bridge       Skip bridge network setup
  --bridge-name NAME  Bridge interface name (default: br0)
  --bridge-subnet     Bridge subnet (auto-detected if omitted)
  --gpu-mode MODE     "exclusive" | "flexible" (default: flexible)
  --dry-run           Show what would be done without executing
  --yes               Non-interactive mode, accept all defaults
  -h, --help          Display help message
```

---

## vmctl — VM Management CLI

After bootstrap, use `vmctl` to manage GPU-accelerated virtual machines:

```bash
# Create a Talos Linux VM with GPU passthrough (GPU attached by default)
vmctl create talos --name talos-01 --cpus 4 --memory 8192

# Create an Ubuntu Desktop VM (auto-detects CPUs, memory, and name)
vmctl create ubuntu

# Create a VM without GPU passthrough
vmctl create ubuntu --name headless-01 --no-gpu

# Specify a static IP and MAC address
vmctl create ubuntu --name desktop-01 --ip 192.168.1.100 --mac 52:54:00:ab:cd:ef

# List all VMs
vmctl list

# GPU management
vmctl gpu status              # Show GPU binding state
vmctl gpu attach talos-01     # Passthrough GPU to VM
vmctl gpu detach talos-01     # Return GPU to host

# IP management
vmctl ip check                # Scan for free IPs on bridge subnet
vmctl ip list                 # Show IPs assigned to VMs

# VM lifecycle
vmctl start desktop-01
vmctl stop desktop-01
vmctl ssh desktop-01          # Ubuntu VMs only (Talos uses talosctl)
vmctl delete desktop-01
```

---

## Requirements

- **OS:** Ubuntu 24.04 LTS (Noble Numbat)
- **GPU:** NVIDIA with compute capability >= 5.0 (Maxwell and newer)
- **CPU:** Intel VT-x/VT-d or AMD-V/AMD-Vi capable
- **Network:** Internet access for package downloads
- **Privileges:** Root or sudo access

---

## Testing

This project includes a comprehensive test suite using
[bats-core](https://github.com/bats-core/bats-core):

```bash
# Run all tests
make test

# Run only unit tests (no Docker required)
make test-unit

# Run harness tests on a real NVIDIA machine
make test-harness

# Lint shell scripts
make lint
```

---

## Documentation

- [App Concept](docs/app-concept.md) — Project vision, architecture, and CLI reference
- [Test Concept](docs/testconcept.md) — Testing strategy and test case overview
- [Todo](docs/todo.md) — Development roadmap and task tracking
- [How-to OSS](docs/howto-oss.md) — Open source repository setup guide

---

## Contributing

See [CONTRIBUTING.md](CONTRIBUTING.md) for guidelines.

## Security

See [SECURITY.md](SECURITY.md) for our security policy.

---

## Licence

Licensed under either of:

- Apache Licence, Version 2.0
  ([LICENSE-APACHE](LICENSE-APACHE) or <http://www.apache.org/licenses/LICENSE-2.0>)
- MIT licence
  ([LICENSE-MIT](LICENSE-MIT) or <http://opensource.org/licenses/MIT>)

at your option.

---

## Disclaimer

This project is **NOT** affiliated with NVIDIA, Canonical, or Sidero Labs.

NVIDIA drivers are downloaded from official NVIDIA repositories. Talos images
are generated via the official Talos Image Factory. This project merely
automates the setup process.

Provided AS-IS without warranty. Use at your own risk.
