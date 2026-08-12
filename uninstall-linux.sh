#!/bin/bash
set -euo pipefail

# ==============================================================================
# uninstall-linux.sh — Distro dispatcher for uninstall scripts
# ==============================================================================

GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
die()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }

if [ ! -f /etc/os-release ]; then
    die "/etc/os-release not found — cannot detect distro."
fi
. /etc/os-release

DISTRO_ID="${ID:-unknown}"
DISTRO_LIKE="${ID_LIKE:-}"

echo -e "${RED}"
echo "  Linux Uninstall — Distro Dispatcher"
echo "  Detected: ${PRETTY_NAME:-$DISTRO_ID}"
echo -e "${NC}"

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
            echo ""
            echo -e "${YELLOW}  ⚠ Unsupported Linux distribution: ${PRETTY_NAME:-$DISTRO_ID}${NC}"
            echo ""
            echo "  This script currently supports:"
            echo "    • Debian / Ubuntu / MX Linux                   (apt-based)"
            echo "    • RHEL / CentOS / Fedora / Rocky / AlmaLinux   (dnf-based)"
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

if [ ! -f "$TARGET" ]; then
    REPO_BASE="https://raw.githubusercontent.com/sb-pk/setup/main"
    warn "Local $SCRIPT not found — fetching from GitHub..."
    curl -fsSL "${REPO_BASE}/${SCRIPT}" | bash
    exit $?
fi

info "Running $SCRIPT for ${PRETTY_NAME:-$DISTRO_ID}..."
bash "$TARGET"
