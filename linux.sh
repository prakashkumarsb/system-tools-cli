#!/bin/bash
set -euo pipefail

# Load common library: reference locally if present; fetch from GitHub if running remotely
export REPO_BASE="${REPO_BASE:-https://raw.githubusercontent.com/prakashkumarsb/system-tools-cli/main}"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-}")" 2>/dev/null && pwd || echo "")"
if [ -n "$SCRIPT_DIR" ] && [ -f "${SCRIPT_DIR}/common.sh" ]; then
    # shellcheck source=/dev/null
    . "${SCRIPT_DIR}/common.sh"
else
    # shellcheck source=/dev/null
    . <(curl -fsSL "${REPO_BASE}/common.sh")
fi
trap fix_tty EXIT

# ==============================================================================
# linux.sh — Distro dispatcher
# Detects the Linux distribution and runs the appropriate setup script.
# Supports: Debian, Ubuntu, MX Linux (apt) | RHEL, CentOS, Fedora, Rocky, Alma (dnf)
# ==============================================================================

# Forward all CLI arguments to delegate scripts
ARGS=("$@")

if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -y, --non-interactive  Run without interactive prompts (assume yes)"
    echo "  --dry-run              Show actions without making changes"
    echo "  -h, --help             Show this help message"
    exit 0
fi

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

case "$DISTRO_ID" in
    debian|ubuntu|linuxmint|mx|mxlinux|pop|elementary|zorin|kali|raspbian)
        SCRIPT="linux-debian.sh"
        ;;
    rhel|centos|fedora|rocky|almalinux|ol|scientific)
        SCRIPT="linux-rhel.sh"
        ;;
    *)
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
            echo "  https://github.com/prakashkumarsb/system-tools-cli/issues"
            echo ""
            exit 1
        fi
        ;;
esac

TARGET="${SCRIPT_DIR:+${SCRIPT_DIR}/}${SCRIPT}"

if [ ! -f "$TARGET" ]; then
    warn "Local $SCRIPT not found — fetching from GitHub..."
    bash -c "$(curl -fsSL "${REPO_BASE}/${SCRIPT}")" -- "${ARGS[@]}"
    exit $?
fi

info "Running $SCRIPT for ${PRETTY_NAME:-$DISTRO_ID}..."
bash "$TARGET" "${ARGS[@]}"
