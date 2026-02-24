<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.1.0] - 2026-02-25

### Added

- `gpu-vm-bootstrap.sh` — one-command host setup for Ubuntu 24.04
- `vmctl` CLI — simplified VM management tool
- NVIDIA driver and CUDA toolkit installation (Phase 1)
- KVM/QEMU/libvirt virtualisation setup (Phase 2)
- IOMMU/VFIO GPU passthrough configuration (Phase 3)
- Bridge network setup with automatic free-IP detection (Phase 4)
- Dual GPU mode support — exclusive VFIO or flexible host+VM sharing (Phase 5)
- Session safety — `tmux` auto-relaunch to survive SSH disconnects (Phase 6)
- Kernel headers fix — ensures `dkms` builds succeed after upgrade (Phase 7)
- `vmctl gpu status/attach/detach` — GPU binding management (Phase 8)
- `vmctl ip check/list` — IP address scanning and listing (Phase 8)
- Smart defaults — auto-detect CPUs, memory, VM names (Phase 9)
- Talos Linux VM creation with Image Factory integration (Phase 10)
- Ubuntu 25.10 Desktop VM creation with Cloud-Init (Phase 11)
- Comprehensive test suite with bats-core (300+ tests)
- Live harness tests for real NVIDIA GPU hardware (Phase 12)
- E2E dry-run tests for CI validation (Phase 12)
- CI/CD pipeline with GitHub Actions
- Release workflow with artefact bundling (Phase 13)
- Full OSS documentation (LICENCE, CONTRIBUTING, CODE\_OF\_CONDUCT, SECURITY)

[Unreleased]: https://github.com/XMV-Solutions-GmbH/ubuntu-24.04-gpu-vm-bootstrap/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/XMV-Solutions-GmbH/ubuntu-24.04-gpu-vm-bootstrap/releases/tag/v0.1.0
