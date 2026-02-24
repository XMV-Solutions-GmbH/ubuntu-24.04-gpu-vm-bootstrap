#!/bin/bash
# SPDX-License-Identifier: MIT OR Apache-2.0
# Main test runner for GPU VM Bootstrap
# Executes all test suites and generates reports
# shellcheck disable=SC2034,SC2317

set -e

# Colours for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Test configuration
BATS_PARALLEL="${BATS_PARALLEL:-false}"
BATS_JOBS="${BATS_JOBS:-4}"

VERBOSE="${VERBOSE:-false}"

# Output directory for reports
REPORT_DIR="$SCRIPT_DIR/reports"
mkdir -p "$REPORT_DIR"

# =============================================================================
# Helper Functions
# =============================================================================

print_header() {
    echo ""
    echo -e "${BLUE}========================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}========================================${NC}"
    echo ""
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${CYAN}ℹ $1${NC}"
}

check_dependencies() {
    print_header "Checking Dependencies"

    local missing=()

    # Check for bats
    if ! command -v bats &>/dev/null; then
        missing+=("bats-core")
    else
        print_success "bats-core: $(bats --version)"
    fi

    # Check for Docker (optional for e2e tests)
    if ! command -v docker &>/dev/null; then
        print_warning "Docker not found — e2e tests will be skipped"
    else
        if docker info &>/dev/null; then
            print_success "Docker: $(docker --version | head -1)"
        else
            print_warning "Docker daemon not running — e2e tests will be skipped"
        fi
    fi

    if [[ ${#missing[@]} -gt 0 ]]; then
        print_error "Missing dependencies: ${missing[*]}"
        echo ""
        echo "Install with:"
        echo "  brew install bats-core  # macOS"
        echo "  apt-get install bats    # Debian/Ubuntu"
        exit 1
    fi

    print_success "All required dependencies found"
}

run_unit_tests() {
    print_header "Running Unit Tests"

    local bats_args=()

    if [[ "$VERBOSE" == "true" ]]; then
        bats_args+=("--verbose-run")
    fi

    if [[ "$BATS_PARALLEL" == "true" ]]; then
        bats_args+=("--jobs" "$BATS_JOBS")
    fi

    bats_args+=("--tap")
    bats_args+=("$SCRIPT_DIR/unit/")

    if bats "${bats_args[@]}" | tee "$REPORT_DIR/unit-tests.tap"; then
        print_success "Unit tests passed"
        return 0
    else
        print_error "Unit tests failed"
        return 1
    fi
}

run_e2e_tests() {
    print_header "Running E2E Tests"

    local bats_args=()

    if [[ "$VERBOSE" == "true" ]]; then
        bats_args+=("--verbose-run")
    fi

    bats_args+=("--tap")
    bats_args+=("$SCRIPT_DIR/e2e/")

    if bats "${bats_args[@]}" | tee "$REPORT_DIR/e2e-tests.tap"; then
        print_success "E2E tests passed"
        return 0
    else
        print_error "E2E tests failed"
        return 1
    fi
}

run_harness_tests() {
    print_header "Running Harness Tests (Real NVIDIA Hardware)"

    # Harness tests require a real NVIDIA GPU machine
    if ! command -v nvidia-smi &>/dev/null; then
        print_warning "nvidia-smi not found — harness tests require a real NVIDIA GPU machine"
        print_info "Run these tests on a dedicated NVIDIA host that can be reset after testing"
        return 0
    fi

    print_info "NVIDIA GPU detected: $(nvidia-smi --query-gpu=name --format=csv,noheader 2>/dev/null | head -1)"

    local bats_args=()

    if [[ "$VERBOSE" == "true" ]]; then
        bats_args+=("--verbose-run")
    fi

    bats_args+=("--tap")
    bats_args+=("$SCRIPT_DIR/harness/")

    if bats "${bats_args[@]}" | tee "$REPORT_DIR/harness-tests.tap"; then
        print_success "Harness tests passed"
        return 0
    else
        print_error "Harness tests failed"
        return 1
    fi
}

generate_summary() {
    print_header "Test Summary"

    local total=0
    local passed=0
    local failed=0

    for tap_file in "$REPORT_DIR"/*.tap; do
        if [[ -f "$tap_file" ]]; then
            local file_total
            local file_passed
            local file_failed

            file_total=$(grep -c -E "^ok |^not ok " "$tap_file" 2>/dev/null) || file_total=0
            file_passed=$(grep -c -E "^ok " "$tap_file" 2>/dev/null) || file_passed=0
            file_failed=$(grep -c -E "^not ok " "$tap_file" 2>/dev/null) || file_failed=0

            total=$((total + file_total))
            passed=$((passed + file_passed))
            failed=$((failed + file_failed))

            echo "  $(basename "$tap_file" .tap): $file_passed/$file_total passed"
        fi
    done

    echo ""
    echo -e "${CYAN}Total: $passed/$total tests passed${NC}"

    if [[ $failed -gt 0 ]]; then
        echo -e "${RED}$failed tests failed${NC}"
        return 1
    else
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    fi
}

show_help() {
    echo "GPU VM Bootstrap — Test Runner"
    echo ""
    echo "Usage: $0 [options] [test-type]"
    echo ""
    echo "Test types:"
    echo "  all           Run all tests (unit + e2e)"
    echo "  unit          Run only unit tests"
    echo "  e2e           Run only E2E tests"
    echo "  harness       Run harness tests on real NVIDIA hardware"
    echo ""
    echo "Options:"
    echo "  -p, --parallel    Run tests in parallel"
    echo "  -j, --jobs N      Number of parallel jobs (default: 4)"
    echo "  -v, --verbose     Verbose output"
    echo "  -h, --help        Show this help"
}

# =============================================================================
# Main
# =============================================================================

main() {
    local test_type="all"

    while [[ $# -gt 0 ]]; do
        case "$1" in
            -p|--parallel)
                BATS_PARALLEL=true
                shift
                ;;
            -j|--jobs)
                BATS_JOBS="$2"
                shift 2
                ;;
            -v|--verbose)
                VERBOSE=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            unit|e2e|harness|all)
                test_type="$1"
                shift
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    print_header "GPU VM Bootstrap — Test Suite"
    echo "Test type: $test_type"
    echo "Parallel: $BATS_PARALLEL"
    echo ""

    check_dependencies

    local exit_code=0

    case "$test_type" in
        unit)
            run_unit_tests || exit_code=1
            ;;
        e2e)
            run_e2e_tests || exit_code=1
            ;;
        harness)
            run_harness_tests || exit_code=1
            ;;
        all)
            run_unit_tests || exit_code=1
            run_e2e_tests || exit_code=1
            ;;
    esac

    generate_summary || exit_code=1

    exit $exit_code
}

main "$@"
