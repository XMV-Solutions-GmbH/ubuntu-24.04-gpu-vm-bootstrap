<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Security Policy

## Supported Versions

| Version | Supported          |
| ------- | ------------------ |
| 0.x.x   | :white_check_mark: |

## Reporting a Vulnerability

If you discover a security vulnerability, please do **not** open a public issue.

### How to Report

1. **Email**: Send details to **oss@xmv.de**
2. **Subject**: `[SECURITY] ubuntu-24.04-gpu-vm-bootstrap: <brief description>`
3. **Include**:
   - Description of the vulnerability
   - Steps to reproduce
   - Potential impact
   - Suggested fix (if any)

### What to Expect

- **Acknowledgement**: Within 48 hours
- **Initial assessment**: Within 7 days
- **Resolution timeline**: Depends on severity, typically 30–90 days

### Disclosure Policy

- We follow
  [responsible disclosure](https://en.wikipedia.org/wiki/Responsible_disclosure)
- We will coordinate with you on disclosure timing
- Credit will be given in the security advisory (unless you prefer anonymity)

## Security Considerations

This script:

- Executes commands with root privileges on the host system
- Installs NVIDIA drivers and kernel modules
- Modifies GRUB boot parameters (IOMMU)
- Configures kernel modules (VFIO)
- Modifies network configuration (bridge interface)
- Downloads packages from official Ubuntu and NVIDIA repositories
- Creates and manages KVM virtual machines

### Best Practices

- Always review the script before running it on production systems
- Use `--dry-run` to preview changes before applying
- Ensure your system has a recovery mechanism (console access) before
  modifying network or boot configuration
- Keep NVIDIA drivers and CUDA toolkit updated for security patches

## Dependencies

We regularly update dependencies via Dependabot. Security updates are
prioritised.
