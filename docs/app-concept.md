# Ubuntu 24.04 GPU VM Bootstrap

## Vision

A single curl command transforms any fresh Ubuntu 24.04 machine with internet access
into a fully GPU-capable virtualisation host — ready for PyTorch training on bare metal
and GPU-accelerated virtual machines running Talos Linux or Ubuntu Desktop.

## Problem Statement

Setting up a GPU-enabled Linux host for both direct PyTorch workloads and
GPU-passthrough VMs is a tedious, error-prone, multi-hour process involving
NVIDIA driver installation, IOMMU/VFIO configuration, bridge networking,
KVM setup, and Talos image generation. This project automates the entire
workflow into a single idempotent script.

## Target Audience

- ML/AI engineers who need GPU training environments on bare-metal Ubuntu
- DevOps engineers provisioning Kubernetes (Talos) clusters with GPU nodes
- Developers who need GPU-accelerated VMs for testing and development

## Core Features

- [ ] **One-liner bootstrap** — `curl | bash` from latest GitHub release
- [ ] **NVIDIA driver & CUDA setup** — Installs drivers, CUDA toolkit,
      `nvidia-container-toolkit`
- [ ] **KVM/libvirt virtualisation** — `qemu-kvm`, `libvirt-daemon`,
      `virt-install`, bridge networking
- [ ] **IOMMU/VFIO configuration** — Kernel parameters, VFIO modules,
      GPU passthrough readiness
- [ ] **Dual GPU mode** — Exclusive VFIO passthrough or flexible
      host-use with on-demand passthrough (unbind/rebind)
- [ ] **`vmctl` CLI helper** — Installed to `/usr/local/bin/vmctl`,
      wraps `virt-install`/`virsh` for simplified VM management
- [ ] **Talos Linux VM support** — Auto-fetches latest Talos version,
      generates NVIDIA-enabled image via Talos Image Factory
- [ ] **Ubuntu Desktop VM support** — Ubuntu 25.10 Desktop with
      Cloud-Init and GPU passthrough
- [ ] **Bridge networking** — Bridged network with per-VM IP addresses,
      automatic free-IP detection (ARP scan)

## Architecture Overview

```text
┌─────────────────────────────────────────────────────────────────┐
│                    Ubuntu 24.04 Host                            │
│                                                                 │
│  gpu-vm-bootstrap.sh (one-liner entry point)                    │
│  ├── Phase 1: System update & essential tools                   │
│  ├── Phase 2: NVIDIA driver + CUDA toolkit                     │
│  ├── Phase 3: KVM / libvirt / QEMU setup                       │
│  ├── Phase 4: IOMMU + VFIO configuration                       │
│  ├── Phase 5: Bridge network setup                              │
│  └── Phase 6: Install vmctl CLI                                 │
│                                                                 │
│  /usr/local/bin/vmctl                                           │
│  ├── vmctl create talos    → Talos Image Factory + virt-install │
│  ├── vmctl create ubuntu   → Ubuntu 25.10 + Cloud-Init          │
│  ├── vmctl list            → virsh list wrapper                 │
│  ├── vmctl delete <name>   → cleanup VM + storage               │
│  ├── vmctl gpu attach <vm> → VFIO bind + attach GPU to VM       │
│  ├── vmctl gpu detach <vm> → detach GPU + rebind to host        │
│  └── vmctl ip check        → scan for free IPs on bridge        │
│                                                                 │
│  ┌──────────────┐  ┌──────────────┐                             │
│  │  Talos VM    │  │ Ubuntu VM    │                              │
│  │  (K8s node)  │  │ (Desktop)    │                              │
│  │  GPU: VFIO   │  │ GPU: VFIO    │                              │
│  │  Net: Bridge │  │ Net: Bridge  │                              │
│  └──────────────┘  └──────────────┘                             │
└─────────────────────────────────────────────────────────────────┘
```

### Bootstrap Script Flow

```text
gpu-vm-bootstrap.sh [OPTIONS]
  --skip-nvidia       Skip NVIDIA driver installation
  --skip-kvm          Skip KVM/libvirt setup
  --skip-vfio         Skip IOMMU/VFIO configuration
  --skip-bridge       Skip bridge network setup
  --bridge-name NAME  Bridge interface name (default: br0)
  --bridge-subnet     Bridge subnet (auto-detected if omitted)
  --gpu-mode MODE     "exclusive" | "flexible" (default: flexible)
  --dry-run           Show what would be done without executing
  --yes               Non-interactive mode, accept all defaults
```

### vmctl CLI Commands

```text
vmctl create talos [OPTIONS]
  --name NAME         VM name (default: talos-01)
  --cpus N            Number of CPUs (default: 4)
  --memory SIZE       Memory in MiB (default: 8192)
  --disk SIZE         Disk size in GiB (default: 50)
  --gpu               Attach GPU via VFIO passthrough
  --ip ADDRESS        Static IP (default: auto-detect free IP)
  --talos-version     Talos version (default: latest from GitHub)

vmctl create ubuntu [OPTIONS]
  --name NAME         VM name (default: ubuntu-desktop-01)
  --cpus N            Number of CPUs (default: 4)
  --memory SIZE       Memory in MiB (default: 8192)
  --disk SIZE         Disk size in GiB (default: 50)
  --gpu               Attach GPU via VFIO passthrough
  --ip ADDRESS        Static IP (default: auto-detect free IP)

vmctl list                  List all managed VMs
vmctl info <name>           Show VM details (IP, GPU, state)
vmctl start <name>          Start a VM
vmctl stop <name>           Gracefully stop a VM
vmctl delete <name>         Delete VM and associated storage
vmctl ssh <name>            SSH into a VM (Ubuntu VMs only; Talos uses talosctl)

vmctl gpu status            Show GPU binding state (host/VFIO)
vmctl gpu attach <name>     Unbind GPU from host, attach to VM
vmctl gpu detach <name>     Detach GPU from VM, rebind to host

vmctl ip check              Scan bridge subnet for free IPs
vmctl ip list               List IPs assigned to managed VMs
```

## Tech Stack

| Component        | Technology                        | Rationale                                               |
| ---------------- | --------------------------------- | ------------------------------------------------------- |
| Language         | Bash (POSIX-compatible where possible) | Zero dependencies, runs on any Ubuntu 24.04         |
| Virtualisation   | KVM/QEMU + libvirt                | Native Linux hypervisor, best GPU passthrough support   |
| GPU Drivers      | NVIDIA official repo              | Latest driver + CUDA support                            |
| GPU Passthrough  | VFIO-PCI                          | Standard Linux PCI passthrough mechanism                |
| Networking       | Linux Bridge + nmap               | Simple, scriptable, IP scanning for free addresses      |
| Testing          | Bats (Bash Automated Testing)     | Industry standard for Bash testing                      |
| Talos Images     | Talos Image Factory API           | Official way to build custom Talos images               |
| VM Management    | `vmctl` (custom Bash CLI)         | Thin wrapper around virsh/virt-install                  |
| CI/CD            | GitHub Actions                    | Automated testing and release                           |

## Non-Functional Requirements

- **Idempotency** — Running the bootstrap script multiple times must be safe
  and produce the same result
- **Offline resilience** — Script should detect already-installed components
  and skip them
- **No user interaction** — `--yes` flag for fully unattended operation
- **Logging** — Structured log output with timestamps, stored in
  `/var/log/gpu-vm-bootstrap.log`
- **Rollback hints** — On failure, script outputs what was changed and how
  to revert
- **Security** — No hardcoded credentials, minimal privilege escalation
  (sudo only where needed)
- **Compatibility** — Ubuntu 24.04 LTS (Noble Numbat), both AMD64 and ARM64
  where applicable
- **GPU compatibility** — NVIDIA GPUs with compute capability >= 5.0
  (Maxwell and newer)
