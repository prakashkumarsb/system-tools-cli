#!/bin/bash
set -uo pipefail

NON_INTERACTIVE=false
DRY_RUN=false

usage() {
    echo "Usage: $0 [OPTIONS]"
    echo ""
    echo "Options:"
    echo "  -y, --non-interactive  Run without interactive confirmation"
    echo "  --dry-run              Show actions without deleting"
    echo "  -h, --help             Show this help message"
    exit 0
}

while [[ $# -gt 0 ]]; do
    case "$1" in
        -y|--non-interactive) NON_INTERACTIVE=true; shift ;;
        --dry-run)           DRY_RUN=true; shift ;;
        -h|--help)            usage ;;
        *)                    echo "Unknown argument: $1"; usage ;;
    esac
done

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
step()  { echo -e "\n${RED}[x]${NC} $1"; }

run_cmd() {
    if [ "$DRY_RUN" = true ]; then
        info "[DRY-RUN] Would run: $*"
    else
        "$@"
    fi
}

echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  WARNING: This will uninstall everything from linux-rhel.sh   ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ "$NON_INTERACTIVE" = false ]; then
    read -rp "Are you sure you want to proceed? [y/N]: " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

if [ "$DRY_RUN" = false ]; then
    sudo -v
    while true; do sudo -n true; sleep 55; kill -0 "$$" || exit; done 2>/dev/null &
    SUDO_PID=$!
    trap 'kill "$SUDO_PID" 2>/dev/null || true' EXIT INT TERM
fi

step "Removing VS Code Tunnel service..."
CODE_CMD="$(command -v code 2>/dev/null || true)"
if [ -n "$CODE_CMD" ]; then
    run_cmd "$CODE_CMD" tunnel service uninstall 2>/dev/null || true
fi

step "Removing Tailscale..."
if command -v tailscale &>/dev/null && [ "$DRY_RUN" = false ]; then
    sudo tailscale down 2>/dev/null || true
    sudo systemctl disable tailscaled 2>/dev/null || true
    sudo systemctl stop tailscaled 2>/dev/null || true
    sudo dnf -y remove tailscale 2>/dev/null || true
    sudo rm -f /etc/yum.repos.d/tailscale.repo
fi

step "Disabling SSH server..."
if [ "$DRY_RUN" = false ]; then
    sudo systemctl disable sshd 2>/dev/null || true
    sudo systemctl stop sshd 2>/dev/null || true
    sudo dnf -y remove openssh-server 2>/dev/null || true
fi

step "Removing Git LFS system config..."
run_cmd sudo git lfs uninstall --system 2>/dev/null || true

step "Cleaning .zshrc entries..."
lines_to_remove=(
    'source $ZSH_CUSTOM/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh'
    'source $ZSH_CUSTOM/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh'
    'source $ZSH_CUSTOM/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh'
    'export JAVA_HOME='
    'export PATH="$JAVA_HOME/bin:$PATH"'
    'eval "$(starship init zsh)"'
)
if [ -f ~/.zshrc ] && [ "$DRY_RUN" = false ]; then
    for line in "${lines_to_remove[@]}"; do
        sed -i "\|${line}|d" ~/.zshrc
    done
fi

step "Uninstalling VS Code..."
if [ "$DRY_RUN" = false ]; then
    sudo dnf -y remove code 2>/dev/null || true
    sudo rm -f /etc/yum.repos.d/vscode.repo
fi

step "Uninstalling CLI packages..."
packages=(
    bat git git-lfs gh htop
    java-21-openjdk-devel jq maven nodejs npm
    parallel python3-pip ripgrep rsync shellcheck sshpass
    wget wl-clipboard zsh
)
for pkg in "${packages[@]}"; do
    run_cmd sudo dnf -y remove "$pkg" 2>/dev/null || true
done

step "Removing yq and starship..."
run_cmd sudo rm -f /usr/local/bin/yq /usr/local/bin/starship

step "Removing Zsh plugins, Oh My Zsh & Manifest..."
if [ "$DRY_RUN" = false ]; then
    rm -rf "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
    rm -rf "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
    rm -rf "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-history-substring-search"
    rm -rf "$HOME/.oh-my-zsh"
    rm -f "$HOME/.config/setup/manifest.json"
fi

info "Uninstall complete."
