<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
# Contributing to ubuntu-24.04-gpu-vm-bootstrap

Thank you for your interest in contributing!

## Code of Conduct

By participating in this project, you agree to abide by our
[Code of Conduct](CODE_OF_CONDUCT.md).

## Getting Started

### Prerequisites

- Bash 4.0+
- [bats-core](https://github.com/bats-core/bats-core) (for running tests)
- [ShellCheck](https://www.shellcheck.net/) (for linting)

### Setup

```bash
git clone https://github.com/XMV-Solutions-GmbH/ubuntu-24.04-gpu-vm-bootstrap.git
cd ubuntu-24.04-gpu-vm-bootstrap

# Install test dependencies (macOS)
brew install bats-core shellcheck markdownlint-cli

# Run tests
make test
```

## Development Guidelines

### Code Style

- Use [ShellCheck](https://www.shellcheck.net/) for shell script linting
- Follow British English spelling conventions
- Use 4-space indentation in shell scripts
- Functions should be documented with a comment header

### SPDX Headers

Every source file must start with an SPDX header:

```bash
#!/usr/bin/env bash
# SPDX-License-Identifier: MIT OR Apache-2.0
```

For Markdown files:

```markdown
<!-- SPDX-License-Identifier: MIT OR Apache-2.0 -->
```

### Documentation

- All public scripts must have usage documentation
- Include examples where helpful
- Update the README.md for user-facing changes

### Testing

- Unit tests are mandatory for all new functionality
- Harness tests validate against real NVIDIA hardware
- Run `make test` before submitting a PR

```bash
# Run all tests
make test

# Run only unit tests
make test-unit

# Run harness tests (requires real NVIDIA GPU machine)
make test-harness
```

## Pull Request Process

1. **Fork** the repository
2. **Create a feature branch** from `main`
3. **Make your changes** with clear, atomic commits
4. **Run all checks** (lint, test)
5. **Open a Pull Request** with a clear description
6. **Wait for CI** to pass
7. **Address review feedback**

### Commit Messages

Follow [Conventional Commits](https://www.conventionalcommits.org/):

```text
feat: add NVIDIA driver installation phase
fix: resolve bridge network IP detection
docs: update vmctl usage examples
chore: update dependencies
test: add unit tests for GPU detection
ci: update GitHub Actions workflow
```

## Types of Contributions

- Bug reports
- Feature requests
- Documentation improvements
- Test coverage
- Code improvements

## Questions?

Open an issue or start a discussion!
