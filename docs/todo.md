# Project Todo

## Legend

- 🔴 Blocked
- 🟡 In Progress
- 🟢 Complete
- ⚪ Not Started

## Milestones

### v0.1.0 — MVP (Full Host Bootstrap + vmctl)

#### Phase 0: Repository Housekeeping

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| 🟢     | Remove all vs-tunnel content from repo           | Purged all references to VS Code tunnel         |
| 🟢     | Update README.md for new project scope           | Badges, description, usage, architecture        |
| 🟢     | Update CONTRIBUTING.md                           | Adjusted for Bash/KVM project                   |
| 🟢     | Update SECURITY.md                               | Adjusted contact and scope                      |
| 🟢     | Update CHANGELOG.md                              | Fresh start for v0.1.0                          |
| 🟢     | Update CODE_OF_CONDUCT.md                        | Reviewed — generic, no changes needed           |
| 🟢     | Update .github/copilot-instructions.md           | Reviewed — generic, no changes needed           |
| 🟢     | Update .github/CODEOWNERS                        | Adjusted ownership                              |
| 🟢     | Update .github/workflows/release.yml             | New artefact name `gpu-vm-bootstrap.sh`         |
| 🟢     | Update .github/workflows/test.yml                | Adjusted test matrix for new scripts            |
| 🟢     | Update .github/gh-scripts/*                      | Adjusted repo references                        |
| 🟢     | Update LICENSE files                             | Verified — correct for new project              |
| 🟢     | Update Makefile                                  | New targets for bootstrap + vmctl               |
| 🟢     | Update docs/testconcept.md                       | Adjusted for new test structure                 |
| 🟢     | Delete setup-vscode-tunnel.sh                    | Deleted, replaced by gpu-vm-bootstrap.sh        |

#### Phase 1: Bootstrap Script — Core Framework

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| 🟢     | Create `gpu-vm-bootstrap.sh` skeleton            | Argument parsing, logging, phase runner          |
| 🟢     | Implement argument parsing                       | `--skip-*`, `--gpu-mode`, `--dry-run`, `--yes`  |
| 🟢     | Implement logging framework                      | Timestamps, colours, log file output            |
| 🟢     | Implement pre-flight checks                      | Ubuntu 24.04 detection, root/sudo check, internet|
| 🟢     | Implement idempotency helpers                    | Check-if-installed functions                     |

#### Phase 2: Bootstrap Script — NVIDIA Setup

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| 🟢     | Detect GPU hardware                              | `lspci` parsing, PCI slot/ID extraction         |
| 🟢     | Install NVIDIA drivers                           | Official NVIDIA CUDA repo, `cuda-drivers`       |
| 🟢     | Install CUDA toolkit                             | `cuda-toolkit`, PATH configuration              |
| 🟢     | Install nvidia-container-toolkit                 | For containerised GPU workloads                 |
| 🟢     | Verify NVIDIA setup                              | `nvidia-smi` health check, reboot detection     |

#### Phase 3: Bootstrap Script — KVM/libvirt Setup

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| 🟢     | Install KVM/QEMU packages                        | 9 packages incl. `qemu-kvm`, `libvirt-daemon-system`, `ovmf` |
| 🟢     | Configure libvirtd                               | Enable service, user groups, default URI        |
| 🟢     | Verify KVM readiness                             | `kvm-ok`, module checks, `/dev/kvm`, `virsh`    |

#### Phase 4: Bootstrap Script — IOMMU/VFIO Configuration

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| 🟢     | Detect CPU vendor (Intel/AMD)                    | `/proc/cpuinfo` parsing, sets `IOMMU_PARAM`     |
| 🟢     | Configure GRUB for IOMMU                         | `intel_iommu=on` or `amd_iommu=on` + `iommu=pt` |
| 🟢     | Configure VFIO modules                           | `/etc/modules`, modprobe config, initramfs      |
| 🟢     | Detect IOMMU groups                              | Sysfs enumeration, GPU isolation check          |
| 🟢     | Handle reboot requirement                        | Inform user, support `--reboot` flag            |

#### Phase 5: Bootstrap Script — Bridge Network

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| 🟢     | Detect primary network interface                  | Auto-detect via default route, gather IP/GW/DNS |
| 🟢     | Create bridge interface                           | Netplan configuration for `br0` with backup     |
| 🟢     | Configure bridge with existing IP                 | Migrate host IP to bridge, static or DHCP       |
| 🟢     | Verify bridge connectivity                        | Interface state, IP, routing, gateway ping      |

#### Phase 6: Bootstrap Script — vmctl Installation

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| 🟢     | Install vmctl to `/usr/local/bin/`                | Idempotent install with version matching         |
| 🟢     | Create vmctl config directory                     | `/etc/vmctl/` for defaults                     |
| 🟢     | Verify vmctl is callable                          | Post-install `vmctl version` check               |

#### Phase 7: vmctl CLI — Core Framework

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| 🟢     | Create `vmctl` skeleton                           | Subcommand dispatcher, help text                |
| 🟢     | Implement `vmctl list`                            | `virsh list` wrapper with colour-coded states   |
| 🟢     | Implement `vmctl info <name>`                     | VM details (IP, GPU, UUID, vCPUs, memory)       |
| 🟢     | Implement `vmctl start <name>`                    | Start a stopped VM                              |
| 🟢     | Implement `vmctl stop <name>`                     | Graceful shutdown                               |
| 🟢     | Implement `vmctl delete <name>`                   | Remove VM + associated storage + NVRAM          |
| 🟢     | Implement `vmctl ssh <name>`                      | Guest agent + ARP IP detection, `exec ssh`      |

#### Phase 8: vmctl CLI — GPU Management

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| ⚪     | Implement `vmctl gpu status`                      | Show GPU PCI slot, current binding (host/VFIO)  |
| ⚪     | Implement `vmctl gpu attach <name>`               | Unbind from host driver, VFIO bind, hotplug to VM |
| ⚪     | Implement `vmctl gpu detach <name>`               | Detach from VM, rebind to host NVIDIA driver    |

#### Phase 9: vmctl CLI — Networking & Smart Defaults

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| ⚪     | Auto-detect networking mode                       | /32 direct-route vs standard subnet             |
| ⚪     | Standard mode: ARP scan for free IPs              | `nmap -sn` or `arping` on bridge subnet         |
| ⚪     | /32 mode: require `--mac` + `--ip`                | Exit with clear error if missing                |
| ⚪     | Auto-detect gateway from host                     | `ip route show default`, same for all VMs       |
| ⚪     | Smart defaults: vCPUs, memory, GPU, name          | 50% host CPUs/RAM, auto-increment names         |
| ⚪     | Implement `vmctl ip check`                        | ARP/nmap scan for free IPs (standard mode only) |
| ⚪     | Implement `vmctl ip list`                         | Show IPs assigned to managed VMs                |

#### Phase 10: vmctl CLI — Talos Linux Support

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| ⚪     | Fetch latest Talos version from GitHub API        | `siderolabs/talos` releases, cache result       |
| ⚪     | Detect GPU architecture for extension selection   | Turing+ → `nvidia-open-gpu-kernel-modules`, older → `nonfree-kmod-nvidia` |
| ⚪     | Build Image Factory schematic JSON                | Include chosen NVIDIA ext + `nvidia-container-toolkit` |
| ⚪     | POST schematic to Image Factory API               | `https://factory.talos.dev/schematics` → schematic ID |
| ⚪     | Download and cache Talos image                    | `nocloud-amd64.raw.xz`, cache in `/etc/vmctl/images/` |
| ⚪     | Implement `vmctl create talos`                    | Full VM: smart defaults, /32-aware networking, GPU |
| ⚪     | Generate Talos machine config                     | `controlplane.yaml` or `worker.yaml` with GPU settings |
| ⚪     | Document NVIDIA driver independence               | Host and VM drivers are decoupled via VFIO      |

#### Phase 11: vmctl CLI — Ubuntu Desktop Support

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| ⚪     | Download Ubuntu 25.10 ISO                         | Auto-fetch from official mirrors, cache locally |
| ⚪     | Create Cloud-Init config                          | User, SSH keys, packages, static IP if /32 mode |
| ⚪     | Implement `vmctl create ubuntu`                   | Full VM: smart defaults, /32-aware networking, GPU |

#### Phase 12: Testing

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| 🟢     | Unit tests for argument parsing                   | 38 tests in `test_argument_parsing.bats`        |
| 🟢     | Unit tests for helper functions                   | 258 total tests across 11 test files            |
| 🟢     | Unit tests for vmctl subcommands                  | 45 tests in `test_vmctl_cli.bats`               |
| ⚪     | Harness tests on real NVIDIA hardware              | Real drivers, KVM, VFIO on dedicated machine    |
| ⚪     | E2E test framework                                | Full bootstrap on real NVIDIA machine           |

#### Phase 13: CI/CD & Release

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| 🟢     | GitHub Actions: lint + unit tests                 | ShellCheck + Bats on every push, 3 required checks |
| ⚪     | GitHub Actions: release workflow                  | Build and publish `gpu-vm-bootstrap.sh`         |
| ⚪     | Create release artefact bundling                  | Single `gpu-vm-bootstrap.sh` with embedded vmctl|
| ⚪     | Documentation: final README review                | Installation, usage, examples                   |

## Backlog (Post v0.1.0)

| Priority | Task                                   | Complexity | Notes                              |
| -------- | -------------------------------------- | ---------- | ---------------------------------- |
| High     | vGPU/MIG support for supported GPUs    | High       | A100/H100 MIG, GRID vGPU          |
| High     | Multi-GPU support                      | Medium     | Select which GPU to passthrough    |
| Medium   | vmctl snapshot support                 | Low        | `vmctl snapshot create/restore`    |
| Medium   | vmctl template support                 | Medium     | Save VM configs as templates       |
| Medium   | Automatic Talos cluster bootstrap      | High       | Multi-node Talos cluster via vmctl |
| Low      | TUI interface for vmctl               | Medium     | Interactive VM management          |
| Low      | Monitoring/metrics export              | Medium     | GPU utilisation, VM health         |
| Low      | Ansible playbook alternative           | Medium     | For fleet deployment               |
