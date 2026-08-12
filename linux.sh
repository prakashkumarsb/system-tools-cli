#!/bin/bash
set -euo pipefail

# ==============================================================================
# linux.sh — Distro dispatcher
# Detects the Linux distribution and runs the appropriate setup script.
# Supports: Debian, Ubuntu, MX Linux (apt) | RHEL, CentOS, Fedora, Rocky, Alma (dnf)
# ==============================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
die()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }

# Read /etc/os-release
if [ ! -f /etc/os-release ]; then
    die "/etc/os-release not found — cannot detect distro."
fi
. /etc/os-release

DISTRO_ID="${ID:-unknown}"
DISTRO_LIKE="${ID_LIKE:-}"

echo -e "${GREEN}"
echo "  Linux Setup — Distro Dispatcher"
echo "  Detected: ${PRETTY_NAME:-$DISTRO_ID}"
echo -e "${NC}"

# Determine which script to run
case "$DISTRO_ID" in
    debian|ubuntu|linuxmint|mx|mxlinux|pop|elementary|zorin|kali|raspbian)
        SCRIPT="linux-debian.sh"
        ;;
    rhel|centos|fedora|rocky|almalinux|ol|scientific)
        SCRIPT="linux-rhel.sh"
        ;;
    *)
        # Fall back to ID_LIKE
        if [[ "$DISTRO_LIKE" == *"debian"* || "$DISTRO_LIKE" == *"ubuntu"* ]]; then
            SCRIPT="linux-debian.sh"
        elif [[ "$DISTRO_LIKE" == *"rhel"* || "$DISTRO_LIKE" == *"fedora"* ]]; then
            SCRIPT="linux-rhel.sh"
        else
            echo ""
            echo -e "${YELLOW}  ⚠ Unsupported Linux distribution: ${PRETTY_NAME:-$DISTRO_ID}${NC}"
            echo ""
            echo "  This script currently supports:"
            echo "    • Debian / Ubuntu / MX Linux         (apt-based)"
            echo "    • RHEL / CentOS / Fedora / Rocky / AlmaLinux  (dnf-based)"
            echo ""
            echo "  If you believe your distro should be supported, please open an issue at:"
            echo "  https://github.com/sb-pk/setup/issues"
            echo ""
            exit 1
        fi
        ;;
esac

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${SCRIPT_DIR}/${SCRIPT}"

# If running via curl (no local file), fetch and run directly
if [ ! -f "$TARGET" ]; then
    REPO_BASE="https://raw.githubusercontent.com/sb-pk/setup/main"
    warn "Local $SCRIPT not found — fetching from GitHub..."
    curl -fsSL "${REPO_BASE}/${SCRIPT}" | bash
    exit $?
fi

info "Running $SCRIPT for ${PRETTY_NAME:-$DISTRO_ID}..."
bash "$TARGET"
