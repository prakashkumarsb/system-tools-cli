#!/bin/bash
set -uo pipefail

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

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

init_cli_flags "$@"

step()  { echo -e "\n${RED}[x]${NC} $1"; }

echo -e "${RED}╔══════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  WARNING: This will uninstall everything from linux-debian.sh ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════════╝${NC}"
echo ""

if [ "$NON_INTERACTIVE" = false ]; then
    read -rp "Are you sure you want to proceed? [y/N]: " confirm || confirm="n"
    [[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }
fi

init_sudo_keepalive

step "Removing VS Code Tunnel service..."
CODE_CMD="$(command -v code 2>/dev/null || true)"
if [ -n "$CODE_CMD" ]; then
    run_cmd "$CODE_CMD" tunnel service uninstall 2>/dev/null || true
fi
if pidof systemd &>/dev/null && [ "$DRY_RUN" = false ]; then
    sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true
fi

step "Removing Docker..."
if [ "$DRY_RUN" = false ]; then
    if pidof systemd &>/dev/null; then
        sudo systemctl disable --now docker.service docker.socket containerd.service 2>/dev/null || true
    else
        sudo service docker stop 2>/dev/null || true
    fi
    sudo apt-get purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
fi

step "Removing Tailscale..."
if command -v tailscale &>/dev/null && [ "$DRY_RUN" = false ]; then
    sudo tailscale down 2>/dev/null || true
    if pidof systemd &>/dev/null; then
        sudo systemctl disable tailscaled 2>/dev/null || true
        sudo systemctl stop tailscaled 2>/dev/null || true
    fi
    sudo apt-get purge -y tailscale 2>/dev/null || true
fi

step "Disabling SSH server..."
if [ "$DRY_RUN" = false ]; then
    if pidof systemd &>/dev/null; then
        sudo systemctl disable ssh 2>/dev/null || true
        sudo systemctl stop ssh 2>/dev/null || true
    fi
    sudo apt-get purge -y openssh-server 2>/dev/null || true
fi

step "Removing Git LFS system config..."
run_cmd sudo git lfs uninstall --system 2>/dev/null || true

step "Removing desktop screensaver auto-lock configs..."
if [ "$DRY_RUN" = false ]; then
    rm -f "$HOME/.xscreensaver"
    rm -f "$HOME/.config/autostart/xscreensaver.desktop"
fi

step "Cleaning .zshrc entries..."
lines_to_remove=(
    'source $ZSH_CUSTOM/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh'
    'source $ZSH_CUSTOM/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh'
    'source $ZSH_CUSTOM/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh'
    'alias bat=batcat'
    'export PATH="$JAVA_HOME/bin:$PATH"'
    'eval "$(starship init zsh)"'
)
for line in "${lines_to_remove[@]}"; do
    zshrc_remove "$line"
done
zshrc_remove "export JAVA_HOME="

step "Uninstalling VS Code..."
if [ "$DRY_RUN" = false ]; then
    sudo apt-get purge -y code 2>/dev/null || true
fi

step "Removing third-party APT repositories, PPAs & keyrings..."
if [ "$DRY_RUN" = false ]; then
    sudo rm -f /etc/apt/sources.list.d/vscode.list
    sudo rm -f /usr/share/keyrings/packages.microsoft.gpg
    sudo rm -f /etc/apt/sources.list.d/github-cli.list
    sudo rm -f /etc/apt/keyrings/githubcli-archive-keyring.gpg
    sudo rm -f /etc/apt/sources.list.d/docker.list
    sudo rm -f /etc/apt/keyrings/docker.gpg
    sudo rm -f /etc/apt/sources.list.d/nodesource.list /etc/apt/keyrings/nodesource.gpg /etc/apt/sources.list.d/nodesource.sources
    sudo rm -f /etc/apt/sources.list.d/backports.list
    sudo rm -f /etc/apt/sources.list.d/openjdk-r-*.list /etc/apt/sources.list.d/openjdk-r-*.sources
    sudo rm -f /usr/local/bin/bat
fi

step "Uninstalling CLI packages..."
packages=(
    bat git git-lfs gh htop
    jq maven nodejs npm openjdk-21-jdk
    parallel pipx python3-pip ripgrep rsync
    shellcheck sshpass watch wget wl-clipboard zsh
)
for pkg in "${packages[@]}"; do
    run_cmd sudo apt-get purge -y "$pkg" 2>/dev/null || true
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
