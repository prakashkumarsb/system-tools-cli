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

echo -e "${RED}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  WARNING: This will uninstall everything from mac.sh    ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════╝${NC}"
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
CODE_CMD="/opt/homebrew/bin/code"
[ -x "$CODE_CMD" ] || CODE_CMD="$(command -v code 2>/dev/null || true)"
if [ -n "$CODE_CMD" ]; then
    run_cmd "$CODE_CMD" tunnel service uninstall 2>/dev/null || true
fi
run_cmd sudo pmset -a disablesleep 0 2>/dev/null || true

step "Removing Tailscale..."
if command -v tailscale &> /dev/null && [ "$DRY_RUN" = false ]; then
    sudo tailscale down 2>/dev/null || true
    sudo launchctl bootout system /Library/LaunchDaemons/com.tailscale.tailscaled.plist 2>/dev/null || true
    sudo rm -f /Library/LaunchDaemons/com.tailscale.tailscaled.plist
    brew uninstall tailscale 2>/dev/null || true
fi

step "Removing Git LFS system config..."
run_cmd sudo git lfs uninstall --system 2>/dev/null || true

step "Removing OpenJDK 21 symlink..."
run_cmd sudo rm -f /Library/Java/JavaVirtualMachines/openjdk-21.jdk

step "Cleaning .zshrc entries..."
lines_to_remove=(
    'source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh'
    'source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh'
    'source /opt/homebrew/share/zsh-history-substring-search/zsh-history-substring-search.zsh'
    'export ZSH_HIGHLIGHT_HIGHLIGHTERS_DIR=/opt/homebrew/share/zsh-syntax-highlighting/highlighters'
    'export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"'
    'export JAVA_HOME=$(/usr/libexec/java_home -v 21)'
    'export CPPFLAGS="-I/opt/homebrew/opt/openjdk@21/include"'
    'eval "$(starship init zsh)"'
)

if [ -f ~/.zshrc ] && [ "$DRY_RUN" = false ]; then
    for line in "${lines_to_remove[@]}"; do
        sed -i '' "\|${line}|d" ~/.zshrc
    done
fi

step "Uninstalling GUI applications..."
core_casks=(iterm2 visual-studio-code orbstack)
optional_casks=(maccy stats jiggler lulu appcleaner microsoft-teams postman whatsapp google-chrome brave-browser microsoft-edge ollama-app)
licensed_casks=(cleanmymac little-snitch folder-preview-pro "TheBoredTeam/boring-notch/boring-notch" intellij-idea purevpn "4k-video-downloader+")
casks=("${core_casks[@]}" "${optional_casks[@]}" "${licensed_casks[@]}")

for cask in "${casks[@]}"; do
    run_cmd brew uninstall --cask "$cask" 2>/dev/null || true
done

step "Uninstalling CLI formulas..."
formulas=(
    bash bat btop coreutils docker docker-compose gh git git-lfs
    htop ipinfo-cli jq maven node orbstack parallel pipx python3
    ripgrep shellcheck sshpass starship watch wget yq zsh-autosuggestions
    zsh-history-substring-search zsh-syntax-highlighting rsync openjdk@21
)

for formula in "${formulas[@]}"; do
    run_cmd brew uninstall "$formula" 2>/dev/null || true
done

step "Removing Oh My Zsh & Manifest..."
if [ -d "$HOME/.oh-my-zsh" ]; then
    run_cmd rm -rf "$HOME/.oh-my-zsh"
fi
run_cmd rm -f "$HOME/.config/setup/manifest.json"

info "Uninstall complete."
