#!/bin/bash
# ==============================================================================
# common.sh — Shared helpers and terminal configuration
# ==============================================================================

# Ensure terminal output renders newlines with carriage returns (prevents staircase effect)
fix_tty() {
    (
        trap '' SIGTTOU
        if [ -c /dev/tty ]; then
            stty onlcr < /dev/tty 2>/dev/null || true
        fi
        if [ -t 1 ]; then
            stty onlcr 2>/dev/null || true
        fi
    ) 2>/dev/null || true
}
fix_tty

# Terminal colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No Color

# Logging helpers
info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
die()   { echo -e "${RED}[✗]${NC} $1"; exit 1; }
step()  { echo -e "\n${GREEN}==>${NC} $1"; }

# Standardized CLI argument parser
init_cli_flags() {
    export NON_INTERACTIVE=false
    export DRY_RUN=false
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -y|--non-interactive) export NON_INTERACTIVE=true; shift ;;
            --dry-run)           export DRY_RUN=true; shift ;;
            -h|--help)
                echo "Usage: $0 [OPTIONS]"
                echo ""
                echo "Options:"
                echo "  -y, --non-interactive  Run without interactive prompts (assume yes)"
                echo "  --dry-run              Show actions without making changes"
                echo "  -h, --help             Show this help message"
                exit 0
                ;;
            *)
                echo "Unknown argument: $1"
                echo "Usage: $0 [-y|--non-interactive] [--dry-run] [-h|--help]"
                exit 1
                ;;
        esac
    done
}

# Unified XDG logging setup
init_logging() {
    local script_name="$1"
    local log_dir="$HOME/.local/state/setup"
    mkdir -p "$log_dir"
    local log_file
    log_file="$log_dir/${script_name}-$(date +%Y%m%d_%H%M%S).log"
    exec > >(tee -a "$log_file") 2>&1
    info "Logging execution output to $log_file"
}

# Managed Sudo Keep-Alive & Trap Registration
init_sudo_keepalive() {
    if [ "${DRY_RUN:-false}" = false ]; then
        sudo -v
        fix_tty
        while true; do sudo -n true; sleep 55; kill -0 "$$" || exit; done 2>/dev/null &
        SUDO_PID=$!
        # shellcheck disable=SC2317,SC2329
        cleanup_sudo() {
            local exit_code=$?
            kill "$SUDO_PID" 2>/dev/null || true
            fix_tty
            if [ "$exit_code" -ne 0 ]; then
                warn "Process exited with code $exit_code"
            fi
        }
        trap cleanup_sudo EXIT INT TERM
    fi
}

# Execution helpers
run_cmd() {
    if [ "${DRY_RUN:-false}" = true ]; then
        info "[DRY-RUN] Would run: $*"
    else
        "$@"
    fi
}

zshrc_add() {
    if [ "${DRY_RUN:-false}" = true ]; then
        info "[DRY-RUN] Would add to ~/.zshrc: $1"
    else
        grep -qF "$1" ~/.zshrc 2>/dev/null || echo "$1" >> ~/.zshrc
    fi
}

zshrc_remove() {
    local target="$1"
    if [ -f "$HOME/.zshrc" ]; then
        if [ "${DRY_RUN:-false}" = true ]; then
            info "[DRY-RUN] Would remove from ~/.zshrc: $target"
        else
            local tmp
            tmp=$(mktemp)
            grep -vF "$target" "$HOME/.zshrc" > "$tmp" && mv "$tmp" "$HOME/.zshrc"
        fi
    fi
}
