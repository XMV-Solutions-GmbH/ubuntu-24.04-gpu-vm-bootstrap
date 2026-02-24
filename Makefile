# SPDX-License-Identifier: MIT OR Apache-2.0
# Makefile for Ubuntu 24.04 GPU VM Bootstrap
# Provides convenient targets for development and testing

.PHONY: all test test-unit test-e2e test-harness clean lint help

# Default target
all: lint test

# =============================================================================
# Testing
# =============================================================================

# Run all tests
test:
	@./tests/run_tests.sh all

# Run only unit tests (no Docker required)
test-unit:
	@./tests/run_tests.sh unit

# Run only E2E tests (requires Docker)
test-e2e:
	@./tests/run_tests.sh e2e

# Run harness tests on a real NVIDIA machine
test-harness:
	@./tests/run_tests.sh harness

# Run tests in parallel
test-parallel:
	@./tests/run_tests.sh --parallel all

# Run tests with verbose output
test-verbose:
	@./tests/run_tests.sh --verbose all

# =============================================================================
# Linting
# =============================================================================

# Lint shell scripts
lint:
	@echo "Linting shell scripts..."
	@if command -v shellcheck >/dev/null 2>&1; then \
		shellcheck gpu-vm-bootstrap.sh || true; \
		shellcheck vmctl || true; \
		shellcheck tests/run_tests.sh || true; \
		shellcheck tests/test_helper.bash || true; \
		echo "✓ Linting passed"; \
	else \
		echo "⚠ shellcheck not found, skipping lint"; \
	fi

# Lint Markdown files
lint-md:
	@echo "Linting Markdown files..."
	@if command -v markdownlint >/dev/null 2>&1; then \
		markdownlint docs/ README.md; \
		echo "✓ Markdown linting passed"; \
	else \
		echo "⚠ markdownlint not found, skipping Markdown lint"; \
	fi

# =============================================================================
# Development
# =============================================================================

# Install development dependencies
install-deps:
	@echo "Installing development dependencies..."
	@if [[ "$$(uname)" == "Darwin" ]]; then \
		brew install bats-core shellcheck markdownlint-cli; \
	else \
		echo "Please install: bats-core, shellcheck, markdownlint-cli"; \
	fi

# Format shell scripts (requires shfmt)
fmt:
	@echo "Formatting shell scripts..."
	@if command -v shfmt >/dev/null 2>&1; then \
		shfmt -w -i 4 gpu-vm-bootstrap.sh || true; \
		shfmt -w -i 4 vmctl || true; \
		shfmt -w -i 4 tests/run_tests.sh || true; \
		shfmt -w -i 4 tests/test_helper.bash || true; \
		echo "✓ Formatting complete"; \
	else \
		echo "⚠ shfmt not found, skipping format"; \
	fi

# =============================================================================
# Cleaning
# =============================================================================

# Clean test artefacts
clean:
	@echo "Cleaning test artefacts..."
	@rm -rf tests/reports/
	@rm -rf tests/tmp/
	@echo "✓ Clean complete"

# =============================================================================
# Help
# =============================================================================

help:
	@echo "Ubuntu 24.04 GPU VM Bootstrap - Makefile"
	@echo ""
	@echo "Testing targets:"
	@echo "  make test             Run all tests"
	@echo "  make test-unit        Run only unit tests"
	@echo "  make test-e2e         Run only E2E tests"
	@echo "  make test-harness     Run harness tests on real NVIDIA hardware"
	@echo "  make test-parallel    Run tests in parallel"
	@echo "  make test-verbose     Run tests with verbose output"
	@echo ""
	@echo "Development targets:"
	@echo "  make lint             Lint shell scripts"
	@echo "  make lint-md          Lint Markdown files"
	@echo "  make fmt              Format shell scripts"
	@echo "  make install-deps     Install dev dependencies"
	@echo ""
	@echo "Cleaning targets:"
	@echo "  make clean            Clean test artefacts"
	@echo ""
	@echo "Other:"
	@echo "  make help             Show this help"
