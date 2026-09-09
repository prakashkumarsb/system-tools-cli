#!/bin/bash
set -euo pipefail

# ==============================================================================
# test-local.sh — Local Docker Test Suite & Linter
# Runs ShellCheck and tests all scripts in Docker containers locally.
# ==============================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
step()  { echo -e "\n${GREEN}==>${NC} $1"; }
die()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" && pwd)"
cd "$SCRIPT_DIR"

# ==============================================================================
# 1. SHELLCHECK LINTING
# ==============================================================================

step "Running ShellCheck on all shell scripts..."
if command -v shellcheck &>/dev/null; then
    shellcheck -e SC1091,SC2016,SC2317 ./*.sh
    info "ShellCheck passed cleanly!"
else
    warn "shellcheck not installed on host — running via Docker..."
    docker run --rm -v "$(pwd)":/mnt koalaman/shellcheck:latest -e SC1091,SC2016,SC2317 ./*.sh
    info "Docker ShellCheck passed cleanly!"
fi

# ==============================================================================
# 2. LOCAL DOCKER MATRIX TESTS
# ==============================================================================

if ! command -v docker &>/dev/null; then
    die "Docker is not running or not installed on your system."
fi

step "Testing macOS scripts (local dry-run)..."
./mac.sh --dry-run -y >/dev/null
./uninstall-mac.sh --dry-run -y >/dev/null
info "mac.sh and uninstall-mac.sh dry-run passed!"

step "Testing Linux distro dispatcher in Docker containers..."

test_distro() {
    local distro=$1
    local pkg_cmd=$2
    info "Testing on $distro (setup + uninstall)..."
    docker run --rm -v "$(pwd)":/work -w /work "$distro" \
        bash -c "$pkg_cmd && ./linux.sh --dry-run -y && ./uninstall-linux.sh --dry-run -y" >/dev/null
    info "Passed on $distro!"
}

test_distro "ubuntu:24.04" "apt-get update && apt-get install -y sudo"
test_distro "debian:12"    "apt-get update && apt-get install -y sudo"
test_distro "debian:trixie" "apt-get update && apt-get install -y sudo"
test_distro "fedora:40"    "dnf install -y sudo"
test_distro "rockylinux:9" "dnf install -y sudo"

echo -e "\n${GREEN}=====================================================${NC}"
echo -e "${GREEN}  SUCCESS: All local Docker tests passed cleanly!    ${NC}"
echo -e "${GREEN}=====================================================${NC}\n"
