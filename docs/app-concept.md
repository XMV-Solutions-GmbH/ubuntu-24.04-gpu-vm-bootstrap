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
vmctl create ubuntu [OPTIONS]

  All options below are optional — vmctl auto-detects sensible defaults.

  --name NAME         VM name (default: auto-increment, e.g. talos-01)
  --cpus N            vCPUs (default: 50% of host CPUs)
  --memory SIZE       Memory in MiB (default: 50% of host RAM)
  --disk SIZE         Disk size in GiB (default: 50)
  --no-gpu            Do NOT attach GPU (default: attach if VFIO-ready GPU found)
  --ip ADDRESS        Static IP (default: auto via ARP scan or DHCP)
  --mac ADDRESS       Virtual MAC address (required in /32 direct-route mode)
  --gateway ADDRESS   Gateway IP (default: auto-detect from host)
  --talos-version VER Talos version (default: latest from GitHub API)

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

### Smart Defaults

`vmctl create` is designed to require **zero mandatory parameters** in the
common case. Every value is auto-detected or derived from the host:

| Parameter | Auto-detection method | Default |
| --------- | --------------------- | ------- |
| Name | Increments per type | `talos-01`, `ubuntu-desktop-01` |
| vCPUs | `nproc` | 50% of host CPUs (min 2) |
| Memory | `free -m` | 50% of host RAM (min 2048 MiB) |
| Disk | Constant | 50 GiB |
| GPU | VFIO-ready GPU present? | Attach if available |
| Gateway | `ip route show default` | Same gateway as host |
| IP | ARP scan on bridge subnet | Next free IP |
| MAC | Random `52:54:00:xx:xx:xx` | Auto-generated |
| Talos ver. | GitHub API `siderolabs/talos` | Latest stable release |

### Networking Modes

vmctl detects the host networking mode automatically and adapts VM creation
accordingly.

#### Standard subnet mode (e.g. /24)

The bridge has a routable subnet. VMs get IPs via DHCP or static assignment.
MAC addresses are randomly generated. ARP works normally.

```bash
# Zero parameters — everything auto-detected
vmctl create talos
```

#### /32 direct-route mode (Hetzner, OVH, etc.)

The host has a /32 address with an on-link gateway. Additional IPs must be
ordered from the hosting provider and each additional IP requires a **virtual
MAC address** assigned in the provider's management panel (e.g. Hetzner Robot).
The provider routes traffic for that IP exclusively to the virtual MAC.

In this mode, vmctl **cannot** auto-assign IPs or MACs. It detects /32 mode
and prompts the user for the two values it cannot determine itself:

```bash
# vmctl detects /32 and exits with a clear error:
$ vmctl create talos
[ERROR] /32 direct-route mode detected.
        Additional IPs require a virtual MAC from your hosting provider.
        Please specify: vmctl create talos --mac 00:50:56:xx:xx:xx --ip x.x.x.x

# User provides the two required values:
$ vmctl create talos --mac 00:50:56:00:AB:CD --ip 88.198.21.135
```

The gateway is auto-detected from the host. Everything else uses smart
defaults. The VM receives a /32 static IP with the same on-link gateway
as the host.

### Talos Image Factory Integration

Talos Linux does not use a traditional package manager — NVIDIA drivers
are built into the OS image as **system extensions** via the
[Talos Image Factory](https://factory.talos.dev/) API.

#### NVIDIA driver independence

With VFIO passthrough, the host NVIDIA driver and the VM NVIDIA driver are
**completely independent**. The host unbinds its driver and binds VFIO-PCI;
the VM receives the raw PCI device and loads its own driver. The host could
run driver 550.x whilst the Talos VM runs 535.x — there is no coupling.

The NVIDIA driver version available inside Talos is determined by the Talos
version (each release ships compatible extension versions). vmctl does not
need to match the host driver.

#### Image build flow

```text
1. Detect host GPU architecture (Turing+? Maxwell? Etc.)
       ↓
2. Choose correct NVIDIA extension:
   - Turing+ (RTX 20xx, 30xx, 40xx, A100, etc.) → nvidia-open-gpu-kernel-modules
   - Older (Maxwell, Pascal, Volta)              → nonfree-kmod-nvidia
       ↓
3. Build schematic JSON:
   {
     "customization": {
       "systemExtensions": {
         "officialExtensions": [
           "siderolabs/nvidia-open-gpu-kernel-modules",
           "siderolabs/nvidia-container-toolkit"
         ]
       }
     }
   }
       ↓
4. POST to https://factory.talos.dev/schematics
   → Response: { "id": "<schematic-sha256>" }
       ↓
5. Download image:
   https://factory.talos.dev/image/<schematic-id>/<talos-version>/nocloud-amd64.raw.xz
       ↓
6. Decompress → use as VM disk with virt-install
```

#### Caching

Downloaded images and schematic IDs are cached in `/etc/vmctl/images/` to
avoid redundant downloads. The cache key is `{talos-version}-{schematic-id}`.

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
- **Smart defaults** — `vmctl create` requires zero parameters in the
  common case; /32 direct-route mode requires only `--mac` and `--ip`
