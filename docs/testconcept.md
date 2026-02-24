<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Test Concept for GPU VM Bootstrap

## Overview

Comprehensive test harness using bats-core with unit tests and
hardware-level harness testing on real NVIDIA GPU machines.

## Test Structure

```text
tests/
├── unit/
│   ├── bootstrap_args.bats        # Bootstrap script argument parsing
│   ├── bootstrap_helpers.bats     # Helper functions (detection, validation)
│   └── vmctl_args.bats            # vmctl argument parsing and subcommands
├── harness/
│   ├── nvidia_setup.bats          # NVIDIA driver installation (real hardware)
│   ├── kvm_setup.bats             # KVM/libvirt setup (real hardware)
│   ├── vfio_setup.bats            # IOMMU/VFIO configuration (real hardware)
│   ├── bridge_setup.bats          # Bridge network setup (real hardware)
│   └── vmctl_commands.bats        # vmctl create/list/delete (real virsh)
├── e2e/
│   └── full_bootstrap.bats        # Full bootstrap on real NVIDIA machine
├── fixtures/
│   └── (mocks and test data)
├── test_helper.bash
└── run_tests.sh
```

## Todo

### Unit Tests — Bootstrap Script

| Status | Test Case | Description |
| ------ | --------- | ----------- |
| ⚪ | `help_flag_shows_usage` | `--help` displays help text and exits 0 |
| ⚪ | `no_args_runs_all_phases` | No arguments runs complete bootstrap |
| ⚪ | `skip_nvidia_flag` | `--skip-nvidia` skips NVIDIA phase |
| ⚪ | `skip_kvm_flag` | `--skip-kvm` skips KVM phase |
| ⚪ | `skip_vfio_flag` | `--skip-vfio` skips VFIO phase |
| ⚪ | `skip_bridge_flag` | `--skip-bridge` skips bridge phase |
| ⚪ | `gpu_mode_exclusive` | `--gpu-mode exclusive` sets mode |
| ⚪ | `gpu_mode_flexible` | `--gpu-mode flexible` sets mode |
| ⚪ | `gpu_mode_invalid` | Invalid mode shows error |
| ⚪ | `dry_run_flag` | `--dry-run` shows actions without executing |
| ⚪ | `yes_flag` | `--yes` accepts all defaults |
| ⚪ | `bridge_name_custom` | `--bridge-name br1` sets bridge name |
| ⚪ | `invalid_flag_shows_help` | Unknown flag shows help |

### Unit Tests — Helper Functions

| Status | Test Case | Description |
| ------ | --------- | ----------- |
| ⚪ | `detect_ubuntu_2404` | Correctly identifies Ubuntu 24.04 |
| ⚪ | `detect_non_ubuntu_fails` | Non-Ubuntu distro exits with error |
| ⚪ | `detect_nvidia_gpu_present` | Detects NVIDIA GPU via lspci |
| ⚪ | `detect_nvidia_gpu_absent` | No GPU detected exits with warning |
| ⚪ | `detect_cpu_vendor_intel` | Identifies Intel CPU |
| ⚪ | `detect_cpu_vendor_amd` | Identifies AMD CPU |
| ⚪ | `check_already_installed` | Skips if component already present |
| ⚪ | `check_internet_connectivity` | Verifies internet access |

### Unit Tests — vmctl

| Status | Test Case | Description |
| ------ | --------- | ----------- |
| ⚪ | `vmctl_help` | `vmctl --help` shows usage |
| ⚪ | `vmctl_create_talos_args` | Parses create talos arguments |
| ⚪ | `vmctl_create_ubuntu_args` | Parses create ubuntu arguments |
| ⚪ | `vmctl_list_no_args` | `vmctl list` requires no arguments |
| ⚪ | `vmctl_delete_requires_name` | `vmctl delete` requires VM name |
| ⚪ | `vmctl_gpu_status` | `vmctl gpu status` parses correctly |
| ⚪ | `vmctl_gpu_attach_requires_name` | GPU attach requires VM name |
| ⚪ | `vmctl_ip_check` | `vmctl ip check` parses correctly |
| ⚪ | `vmctl_unknown_subcommand` | Unknown subcommand shows error |

### Harness Tests (Real NVIDIA Hardware)

Harness tests run on a dedicated NVIDIA GPU machine (e.g. Ubuntu 24.04 with
an NVIDIA GPU). The machine can be reset/reimaged after testing. These tests
validate real driver installation, KVM setup, VFIO binding, and VM lifecycle.

> **Note:** Harness tests are **not** run in CI. They are executed manually on
> a dedicated test machine. Docker cannot install NVIDIA drivers or configure
> KVM, so Docker-based integration tests are not feasible for this project.

| Status | Test Case | Description |
| ------ | --------- | ----------- |
| ⚪ | `nvidia_driver_install` | NVIDIA driver installation on real hardware |
| ⚪ | `cuda_toolkit_install` | CUDA toolkit installation on real hardware |
| ⚪ | `kvm_packages_install` | KVM/libvirt package installation |
| ⚪ | `iommu_grub_config` | GRUB IOMMU parameter modification |
| ⚪ | `vfio_module_config` | VFIO module configuration |
| ⚪ | `bridge_netplan_config` | Netplan bridge configuration |
| ⚪ | `vmctl_create_talos` | Talos VM creation with real virsh |
| ⚪ | `vmctl_create_ubuntu` | Ubuntu VM creation with real virsh |
| ⚪ | `vmctl_gpu_attach` | GPU attach with real VFIO operations |
| ⚪ | `vmctl_gpu_detach` | GPU detach with real driver rebind |
| ⚪ | `vmctl_ip_scan` | IP scan with real nmap |
| ⚪ | `talos_version_fetch` | Fetch latest Talos version from GitHub API |
| ⚪ | `talos_image_factory_request` | Image Factory API call construction |

### E2E Tests

| Status | Test Case | Description |
| ------ | --------- | ----------- |
| ⚪ | `bootstrap_fresh_install` | Full bootstrap on clean Ubuntu 24.04 (real NVIDIA machine) |
| ⚪ | `bootstrap_idempotent` | Second run changes nothing |
| ⚪ | `bootstrap_skip_flags` | Skip flags work correctly |
| ⚪ | `bootstrap_dry_run` | Dry run produces no changes |

### Infrastructure

| Status | Task | Description |
| ------ | ---- | ----------- |
| ⚪ | `test_helper.bash` | Common functions, setup/teardown |
| ⚪ | `run_tests.sh` | Main test runner script |
| ⚪ | `.github/workflows/test.yml` | CI pipeline for tests |
| ⚪ | `Makefile` | `make test` target |

## Dependencies

```bash
# Install bats-core
brew install bats-core  # macOS
# or
sudo apt-get install bats  # Ubuntu

# ShellCheck for linting
brew install shellcheck  # macOS
sudo apt-get install shellcheck  # Ubuntu
```

## Running Tests

```bash
# All tests (unit + e2e)
./tests/run_tests.sh

# Unit only (runs anywhere, no special hardware needed)
bats tests/unit/

# Harness tests (requires real NVIDIA GPU machine)
./tests/run_tests.sh harness

# E2E (requires real NVIDIA GPU machine)
bats tests/e2e/
```

## Notes

- Unit tests can run without Docker on macOS and Linux
- Harness tests require a dedicated NVIDIA GPU machine (Ubuntu 24.04)
- The harness test machine should be resettable (reimage/snapshot) after testing
- Docker-based integration tests are **not used** — NVIDIA drivers and KVM
  cannot be installed inside Docker containers
- E2E tests validate the full bootstrap on real hardware
- Tests must be idempotent and isolated
