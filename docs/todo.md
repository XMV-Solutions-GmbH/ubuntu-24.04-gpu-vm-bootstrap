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
| 🟢     | Implement `vmctl gpu status`                      | PCI slots, vendor:device, driver, IOMMU groups  |
| 🟢     | Implement `vmctl gpu attach <name>`               | Unbind nvidia, bind vfio-pci, hostdev XML       |
| 🟢     | Implement `vmctl gpu detach <name>`               | Detach from VM, rebind to nvidia driver         |

#### Phase 9: vmctl CLI — Networking & Smart Defaults

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| 🟢     | Auto-detect networking mode                       | /32 direct-route via `onlink` in default route  |
| 🟢     | Standard mode: ARP scan for free IPs              | `nmap -sn` on bridge subnet via `vmctl ip check`|
| 🟢     | /32 mode: require `--mac` + `--ip`                | Exit with clear error if missing                |
| 🟢     | Auto-detect gateway from host                     | `ip route show default`, same for all VMs       |
| 🟢     | Smart defaults: vCPUs, memory, GPU, name          | 50% host CPUs/RAM, auto-increment names         |
| 🟢     | Implement `vmctl ip check`                        | ARP scan (standard) or /32 warning              |
| 🟢     | Implement `vmctl ip list`                         | Show IPs assigned to managed VMs                |

#### Phase 10: vmctl CLI — Talos Linux Support

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| 🟢     | Fetch latest Talos version from GitHub API        | `siderolabs/talos` releases, 1-hour cache       |
| 🟢     | Detect GPU architecture for extension selection   | Turing+ → `nvidia-open-gpu-kernel-modules`, older → `nonfree-kmod-nvidia` |
| 🟢     | Build Image Factory schematic JSON                | Chosen NVIDIA ext + `nvidia-container-toolkit`  |
| 🟢     | POST schematic to Image Factory API               | `https://factory.talos.dev/schematics` → ID     |
| 🟢     | Download and cache Talos image                    | `nocloud-amd64.raw.xz`, cache in `/etc/vmctl/images/` |
| 🟢     | Implement `vmctl create talos`                    | Smart defaults, /32 networking, GPU passthrough |
| 🟢     | Document NVIDIA driver independence               | Host and VM drivers are decoupled via VFIO      |

#### Phase 11: vmctl CLI — Ubuntu Desktop Support

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| 🟢     | Download Ubuntu ISO                               | User downloads manually, cached in `/etc/vmctl/images/` |
| 🟢     | Create Cloud-Init config                          | Static IP for /32, hostname, qemu-guest-agent   |
| 🟢     | Implement `vmctl create ubuntu`                   | ISO-based, Cloud-Init, GPU passthrough          |

#### Phase 14: Ubuntu Cloud Image & Live Testing (PR #20)

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| 🟢     | Switch to Cloud Image approach                    | `--import` with cloud image instead of `--cdrom` ISO |
| 🟢     | Auto-download Ubuntu cloud image                  | `_download_ubuntu_cloud_image()` with caching   |
| 🟢     | Default release to 25.10                          | Updated from 24.04 to 25.10                     |
| 🟢     | macvtap networking auto-detection                 | `_vm_net_args()` — macvtap fallback when no br0 |
| 🟢     | Host prefix-length detection                      | `_host_prefix_len()` for /32, /28, /24          |
| 🟢     | Cloud-Init with desktop packages                  | `ubuntu-desktop-minimal`, `xrdp`, `openssh-server` |
| 🟢     | Auto-install `genisoimage`                        | Added to KVM_PACKAGES + runtime install in vmctl |
| 🟢     | GPU grep pattern fix                              | Two-step grep (class code before vendor name)   |
| 🟢     | Live VM testing on Hetzner hardware               | VM created, SSH reachable, Cloud-Init working   |
| 🟢     | 6 new unit tests                                  | Cloud image URL, download, prefix detection     |

#### Phase 12: Testing

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| 🟢     | Unit tests for argument parsing                   | 38 tests in `test_argument_parsing.bats`        |
| 🟢     | Unit tests for helper functions                   | 303 total tests across 12 test files            |
| 🟢     | Unit tests for vmctl subcommands                  | 45 tests in `test_vmctl_cli.bats`               |
| 🟢     | Unit tests for GPU/create/networking              | 50 tests in `test_vmctl_gpu_create.bats`        |
| 🟢     | Total test count                                  | 351 tests (309 unit + 20 E2E + 22 harness)      |
| 🟢     | Harness tests on real NVIDIA hardware              | 22 tests in `test_live_gpu.bats`, 0 failures    |
| 🟢     | E2E test framework                                | 20 tests in `test_bootstrap_dryrun.bats`        |

#### Phase 13: CI/CD & Release

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| 🟢     | GitHub Actions: lint + unit tests                 | ShellCheck + Bats on every push, 3 required checks |
| 🟢     | GitHub Actions: release workflow                  | Fixed vmctl refs, artefact bundling correct      |
| 🟢     | Create release artefact bundling                  | Uploads `gpu-vm-bootstrap.sh` + `vmctl`          |
| 🟢     | Documentation: final README review                | Updated vmctl usage, examples, CHANGELOG v0.1.0  |

## Backlog (Post v0.1.0)

| Priority | Task                                   | Complexity | Notes                              |
| -------- | -------------------------------------- | ---------- | ---------------------------------- |
| High     | Fix bridge Netplan conflict (ISSUE-001)| Medium     | Move original configs instead of copy; rollback on failure; see `docs/issues.md` |
| High     | Unattended security updates            | Medium     | Configure `unattended-upgrades` for security patches, **exclude kernel** packages (`linux-image-*`, `linux-headers-*`, `linux-modules-*`) to protect NVIDIA DKMS drivers |
| High     | Conditional nightly reboot cronjob     | Low        | Cron at 02:00 `Europe/Berlin` — gracefully reboot **only** if `/var/run/reboot-required` exists; use `systemctl reboot` for clean VM shutdown |
| High     | GPU hot-plug `driver_override` safety  | Medium     | Reset `driver_override` in `_pci_unbind()` before rebinding to prevent kernel hangs |
| High     | vGPU/MIG support for supported GPUs    | High       | A100/H100 MIG, GRID vGPU          |
| High     | Multi-GPU support                      | Medium     | Select which GPU to passthrough    |
| Medium   | vmctl snapshot support                 | Low        | `vmctl snapshot create/restore`    |
| Medium   | vmctl template support                 | Medium     | Save VM configs as templates       |
| Medium   | Automatic Talos cluster bootstrap      | High       | Multi-node Talos cluster via vmctl |
| Low      | TUI interface for vmctl               | Medium     | Interactive VM management          |
| Low      | Monitoring/metrics export              | Medium     | GPU utilisation, VM health         |
| Low      | Ansible playbook alternative           | Medium     | For fleet deployment               |

#### Phase 15: Fix Bridge Netplan Conflict (ISSUE-001)

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| 🟢     | Move existing Netplan configs instead of copying  | `mv` statt `cp` in `configure_bridge_interface` |
| 🟢     | Rollback on `netplan try` failure                 | Restore originals, remove faulty bridge file    |
| 🟢     | Unit tests for move and rollback behaviour        | `test_bridge_setup.bats`                        |

#### Phase 16: Unattended Security Updates

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| 🟢     | Install and configure `unattended-upgrades`       | Automatic security patches                      |
| 🟢     | Blacklist kernel packages                         | `linux-image-*`, `linux-headers-*`, `linux-modules-*`, `linux-modules-extra-*` |
| 🟢     | Wire into `main()` as Phase 6                     | `run_phase 6`                                   |
| 🟢     | Unit tests for configuration                      | `test_unattended_upgrades.bats`                 |

#### Phase 17: Conditional Nightly Reboot

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| 🟢     | Create cron job in `/etc/cron.d/`                 | `TZ=Europe/Berlin`, 02:00, checks `/var/run/reboot-required` |
| 🟢     | Idempotency — skip if already present             | File-existence check                            |
| 🟢     | Wire into `main()` as Phase 7                     | `run_phase 7`                                   |
| 🟢     | Unit tests for cron configuration                 | `test_conditional_reboot.bats`                  |
