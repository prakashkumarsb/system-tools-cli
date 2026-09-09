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
# uninstall-linux.sh — Distro dispatcher for uninstall
# ==============================================================================

ARGS=("$@")

if [[ "${1:-}" =~ ^(-h|--help)$ ]]; then
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -y, --non-interactive  Run without interactive confirmation"
    echo "  --dry-run              Show actions without deleting"
    echo "  -h, --help             Show this help message"
    exit 0
fi

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

TARGET="${SCRIPT_DIR:+${SCRIPT_DIR}/}${SCRIPT}"

if [ ! -f "$TARGET" ]; then
    warn "Local $SCRIPT not found — fetching from GitHub..."
    bash -c "$(curl -fsSL "${REPO_BASE}/${SCRIPT}")" -- "${ARGS[@]}"
    exit $?
fi

info "Running $SCRIPT for ${PRETTY_NAME:-$DISTRO_ID}..."
bash "$TARGET" "${ARGS[@]}"
