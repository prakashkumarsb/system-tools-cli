#!/bin/bash
set -uo pipefail

RED='\033[0;31m'
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
step()  { echo -e "\n${RED}[x]${NC} $1"; }

echo -e "${RED}╔══════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  WARNING: This will uninstall everything from linux.sh  ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════╝${NC}"
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
    info "VS Code CLI not found, skipping tunnel service removal"
fi
sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true
info "System sleep/suspend re-enabled"

# ==============================================================================
# 2. TAILSCALE
# ==============================================================================

step "Removing Tailscale..."
if command -v tailscale &>/dev/null; then
    sudo tailscale down 2>/dev/null || true
    if pidof systemd &>/dev/null; then
        sudo systemctl disable tailscaled 2>/dev/null || true
        sudo systemctl stop tailscaled 2>/dev/null || true
    else
        sudo /etc/init.d/tailscaled stop 2>/dev/null || true
        sudo update-rc.d tailscaled remove 2>/dev/null || true
        sudo rm -f /etc/init.d/tailscaled
    fi
    sudo apt-get purge -y tailscale 2>/dev/null || true
    info "Tailscale removed"
else
    info "Tailscale not installed, skipping"
fi

# ==============================================================================
# 3. GIT LFS
# ==============================================================================

step "Removing Git LFS system config..."
sudo git lfs uninstall --system 2>/dev/null || true
info "Git LFS system hooks removed"

# ==============================================================================
# 4. ZSHRC CLEANUP
# ==============================================================================

step "Cleaning .zshrc entries..."
lines_to_remove=(
    'source $ZSH_CUSTOM/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh'
    'source $ZSH_CUSTOM/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh'
    'source $ZSH_CUSTOM/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh'
    'export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64'
    'export PATH="$JAVA_HOME/bin:$PATH"'
)

if [ -f ~/.zshrc ]; then
    for line in "${lines_to_remove[@]}"; do
        sed -i "\|${line}|d" ~/.zshrc
    done
    info ".zshrc entries removed"
fi

# ==============================================================================
# 5. GUI APPLICATIONS
# ==============================================================================

step "Uninstalling GUI applications..."
sudo apt-get purge -y code 2>/dev/null && info "Removed VS Code" || true
sudo rm -f /etc/apt/sources.list.d/vscode.list
sudo rm -f /usr/share/keyrings/packages.microsoft.gpg

# ==============================================================================
# 6. CLI PACKAGES
# ==============================================================================

step "Uninstalling CLI packages..."
packages=(
    docker.io docker-compose maven nodejs npm python3-pip pipx wl-clipboard
    openjdk-21-jdk shellcheck sshpass
)
for pkg in "${packages[@]}"; do
    sudo apt-get purge -y "$pkg" 2>/dev/null && info "Removed $pkg" || true
done

# ==============================================================================
# 7. ZSH PLUGINS & OH MY ZSH
# ==============================================================================

step "Removing Zsh plugins and Oh My Zsh..."
rm -rf "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
rm -rf "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
rm -rf "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-history-substring-search"
rm -rf "$HOME/.oh-my-zsh"
info "Oh My Zsh and plugins removed"

# Restore default shell
if [ "$SHELL" != "/bin/bash" ]; then
    chsh -s /bin/bash
    info "Default shell restored to bash"
fi

step "Cleaning up..."
sudo apt-get autoremove -y
sudo apt-get autoclean

echo ""
info "Uninstall complete. Open a new terminal for changes to take effect."
