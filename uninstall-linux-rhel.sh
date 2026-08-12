#!/bin/bash
set -uo pipefail

# ==============================================================================
# uninstall-linux-rhel.sh — Uninstall script for RHEL/CentOS/Fedora/Rocky/AlmaLinux
# ==============================================================================

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
step()  { echo -e "\n${RED}[x]${NC} $1"; }

echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  WARNING: This will uninstall everything from linux-rhel.sh   ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
echo ""
read -rp "Are you sure you want to proceed? [y/N]: " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

sudo -v
while true; do sudo -n true; sleep 55; kill -0 "$$" || exit; done 2>/dev/null &

# ==============================================================================
# 1. REMOTE ACCESS
# ==============================================================================

step "Removing VS Code Tunnel service..."
CODE_CMD="$(command -v code 2>/dev/null || true)"
if [ -n "$CODE_CMD" ]; then
    "$CODE_CMD" tunnel service uninstall 2>/dev/null || true
    info "VS Code Tunnel service removed"
else
    info "VS Code CLI not found, skipping"
fi
sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true
info "System sleep/suspend re-enabled"

# ==============================================================================
# 2. TAILSCALE
# ==============================================================================

step "Removing Tailscale..."
if command -v tailscale &>/dev/null; then
    sudo tailscale down 2>/dev/null || true
    sudo systemctl disable tailscaled 2>/dev/null || true
    sudo systemctl stop tailscaled 2>/dev/null || true
    sudo dnf -y remove tailscale 2>/dev/null || true
    sudo rm -f /etc/yum.repos.d/tailscale.repo
    info "Tailscale removed"
else
    info "Tailscale not installed, skipping"
fi

# ==============================================================================
# 3. SSH SERVER
# ==============================================================================

step "Disabling SSH server..."
sudo systemctl disable sshd 2>/dev/null || true
sudo systemctl stop sshd 2>/dev/null || true
sudo dnf -y remove openssh-server 2>/dev/null || true
info "SSH server disabled and removed"

# ==============================================================================
# 4. GIT LFS
# ==============================================================================

step "Removing Git LFS system config..."
sudo git lfs uninstall --system 2>/dev/null || true
info "Git LFS system hooks removed"

# ==============================================================================
# 5. ZSHRC CLEANUP
# ==============================================================================

step "Cleaning .zshrc entries..."
lines_to_remove=(
    'source $ZSH_CUSTOM/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh'
    'source $ZSH_CUSTOM/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh'
    'source $ZSH_CUSTOM/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh'
    'export JAVA_HOME='
    'export PATH="$JAVA_HOME/bin:$PATH"'
)
if [ -f ~/.zshrc ]; then
    for line in "${lines_to_remove[@]}"; do
        sed -i "\|${line}|d" ~/.zshrc
    done
    info ".zshrc entries removed"
fi

# ==============================================================================
# 6. GUI APPLICATIONS
# ==============================================================================

step "Uninstalling VS Code..."
sudo dnf -y remove code 2>/dev/null && info "Removed VS Code" || true
sudo rm -f /etc/yum.repos.d/vscode.repo

# ==============================================================================
# 7. CLI PACKAGES
# ==============================================================================

step "Uninstalling CLI packages..."
packages=(
    bat gh git-lfs htop
    java-21-openjdk-devel jq maven nodejs npm
    python3-pip ripgrep rsync shellcheck sshpass
    wget wl-clipboard zsh
)
for pkg in "${packages[@]}"; do
    sudo dnf -y remove "$pkg" 2>/dev/null && info "Removed $pkg" || true
done

# gh dnf repo
sudo rm -f /etc/yum.repos.d/gh-cli.repo
info "gh repo removed"

# Docker
sudo systemctl stop docker 2>/dev/null || true
sudo systemctl disable docker 2>/dev/null || true
sudo dnf -y remove docker-ce docker-ce-cli containerd.io docker-compose-plugin 2>/dev/null || true
sudo rm -f /etc/yum.repos.d/docker-ce.repo
info "Docker removed"

# ==============================================================================
# 8. ZSH PLUGINS & OH MY ZSH
# ==============================================================================

step "Removing Zsh plugins and Oh My Zsh..."
rm -rf "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
rm -rf "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
rm -rf "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-history-substring-search"
rm -rf "$HOME/.oh-my-zsh"
info "Oh My Zsh and plugins removed"

if [ "$SHELL" != "/bin/bash" ]; then
    chsh -s /bin/bash
    info "Default shell restored to bash"
fi

step "Cleaning up..."
sudo dnf -y autoremove

echo ""
info "Uninstall complete. Open a new terminal for changes to take effect."
