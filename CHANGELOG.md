<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- Project initialisation with bootstrap script skeleton
- `gpu-vm-bootstrap.sh` — main entry point for host setup
- `vmctl` CLI — VM management helper tool
- NVIDIA driver and CUDA toolkit installation phase
- KVM/QEMU/libvirt virtualisation setup phase
- IOMMU/VFIO GPU passthrough configuration phase
- Bridge network setup phase
- Talos Linux VM creation with Image Factory integration
- Ubuntu 25.10 Desktop VM creation with Cloud-Init
- Dual GPU mode support (exclusive VFIO / flexible host+VM)
- Comprehensive test suite with bats-core
- CI/CD pipeline with GitHub Actions
- Full OSS documentation (LICENCE, CONTRIBUTING, CODE\_OF\_CONDUCT, SECURITY)

[Unreleased]: https://github.com/XMV-Solutions-GmbH/ubuntu-24.04-gpu-vm-bootstrap/compare/main...HEAD
