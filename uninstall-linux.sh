#!/bin/bash
set -euo pipefail

# ==============================================================================
# uninstall-linux.sh — Distro dispatcher for uninstall
# ==============================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
die()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }

ARGS=("$@")

if [ ! -f /etc/os-release ]; then
    die "/etc/os-release not found — cannot detect distro."
fi
. /etc/os-release

DISTRO_ID="${ID:-unknown}"
DISTRO_LIKE="${ID_LIKE:-}"

case "$DISTRO_ID" in
    debian|ubuntu|linuxmint|mx|mxlinux|pop|elementary|zorin|kali|raspbian)
        SCRIPT="uninstall-linux-debian.sh"
        ;;
    rhel|centos|fedora|rocky|almalinux|ol|scientific)
        SCRIPT="uninstall-linux-rhel.sh"
        ;;
    *)
        if [[ "$DISTRO_LIKE" == *"debian"* || "$DISTRO_LIKE" == *"ubuntu"* ]]; then
            SCRIPT="uninstall-linux-debian.sh"
        elif [[ "$DISTRO_LIKE" == *"rhel"* || "$DISTRO_LIKE" == *"fedora"* ]]; then
            SCRIPT="uninstall-linux-rhel.sh"
        else
            die "Unsupported Linux distribution: ${PRETTY_NAME:-$DISTRO_ID}"
        fi
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd || echo "")"
TARGET="${SCRIPT_DIR:+${SCRIPT_DIR}/}${SCRIPT}"

if [ ! -f "$TARGET" ]; then
    REPO_BASE="https://raw.githubusercontent.com/sb-pk/setup/main"
    warn "Local $SCRIPT not found — fetching from GitHub..."
    bash -c "$(curl -fsSL "${REPO_BASE}/${SCRIPT}")" -- "${ARGS[@]}"
    exit $?
fi

info "Running $SCRIPT for ${PRETTY_NAME:-$DISTRO_ID}..."
bash "$TARGET" "${ARGS[@]}"
