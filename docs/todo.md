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
| ⚪     | Install KVM/QEMU packages                        | `qemu-kvm`, `libvirt-daemon`, `virt-install`    |
| ⚪     | Configure libvirtd                               | Enable service, user permissions                |
| ⚪     | Verify KVM readiness                             | `kvm-ok`, module checks                         |

#### Phase 4: Bootstrap Script — IOMMU/VFIO Configuration

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| ⚪     | Detect CPU vendor (Intel/AMD)                    | For correct IOMMU parameter                     |
| ⚪     | Configure GRUB for IOMMU                         | `intel_iommu=on` or `amd_iommu=on`              |
| ⚪     | Configure VFIO modules                           | `/etc/modules`, modprobe config                 |
| ⚪     | Detect IOMMU groups                              | For GPU isolation verification                  |
| ⚪     | Handle reboot requirement                        | Inform user, support `--reboot` flag            |

#### Phase 5: Bootstrap Script — Bridge Network

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| ⚪     | Detect primary network interface                  | Auto-detect active NIC                         |
| ⚪     | Create bridge interface                           | Netplan configuration for `br0`                |
| ⚪     | Configure bridge with existing IP                 | Migrate host IP to bridge                      |
| ⚪     | Verify bridge connectivity                        | Ensure no network loss                         |

#### Phase 6: Bootstrap Script — vmctl Installation

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| ⚪     | Install vmctl to `/usr/local/bin/`                | Download from release or copy from repo         |
| ⚪     | Create vmctl config directory                     | `/etc/vmctl/` for defaults                     |
| ⚪     | Verify vmctl is callable                          | Post-install check                              |

#### Phase 7: vmctl CLI — Core Framework

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| ⚪     | Create `vmctl` skeleton                           | Subcommand dispatcher, help text                |
| ⚪     | Implement `vmctl list`                            | `virsh list` wrapper with formatting            |
| ⚪     | Implement `vmctl info <name>`                     | VM details (IP, GPU, state, resources)          |
| ⚪     | Implement `vmctl start <name>`                    | Start a stopped VM                              |
| ⚪     | Implement `vmctl stop <name>`                     | Graceful shutdown                               |
| ⚪     | Implement `vmctl delete <name>`                   | Remove VM + associated storage                  |
| ⚪     | Implement `vmctl ssh <name>`                      | SSH wrapper (Ubuntu VMs only; Talos uses talosctl) |

#### Phase 8: vmctl CLI — GPU Management

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| ⚪     | Implement `vmctl gpu status`                      | Show GPU binding state                          |
| ⚪     | Implement `vmctl gpu attach <name>`               | Unbind from host, VFIO bind, attach to VM       |
| ⚪     | Implement `vmctl gpu detach <name>`               | Detach from VM, rebind to host driver           |

#### Phase 9: vmctl CLI — IP Management

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| ⚪     | Implement `vmctl ip check`                        | ARP/nmap scan for free IPs on bridge subnet     |
| ⚪     | Implement `vmctl ip list`                         | Show IPs assigned to managed VMs                |

#### Phase 10: vmctl CLI — Talos Linux Support

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| ⚪     | Fetch latest Talos version from GitHub API        | `siderolabs/talos` releases                     |
| ⚪     | Generate NVIDIA Talos image via Image Factory     | Include `nvidia-container-toolkit`, `nvidia-fabricmanager` extensions |
| ⚪     | Implement `vmctl create talos`                    | Full VM creation with GPU + bridge networking   |
| ⚪     | Generate Talos machine config                     | `controlplane.yaml` or `worker.yaml`            |

#### Phase 11: vmctl CLI — Ubuntu Desktop Support

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| ⚪     | Download Ubuntu 25.10 ISO                         | Auto-fetch from official mirrors                |
| ⚪     | Create Cloud-Init config                          | User, SSH keys, packages                        |
| ⚪     | Implement `vmctl create ubuntu`                   | Full VM creation with GPU + bridge networking   |

#### Phase 12: Testing

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| ⚪     | Unit tests for argument parsing                   | Bats tests for bootstrap script flags           |
| ⚪     | Unit tests for helper functions                   | Detection, validation, idempotency helpers      |
| ⚪     | Unit tests for vmctl subcommands                  | Argument parsing, input validation              |
| ⚪     | Harness tests on real NVIDIA hardware              | Real drivers, KVM, VFIO on dedicated machine    |
| ⚪     | E2E test framework                                | Full bootstrap on real NVIDIA machine           |

#### Phase 13: CI/CD & Release

| Status | Task                                             | Notes                                           |
| ------ | ------------------------------------------------ | ----------------------------------------------- |
| ⚪     | GitHub Actions: lint + unit tests                 | ShellCheck + Bats on every push                 |
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
