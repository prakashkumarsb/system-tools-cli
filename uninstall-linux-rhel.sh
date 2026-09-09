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

init_cli_flags "$@"

step()  { echo -e "\n${RED}[x]${NC} $1"; }

echo -e "${RED}╔════════════════════════════════════════════════════════════════╗${NC}"
echo -e "${RED}║  WARNING: This will uninstall everything from linux-rhel.sh   ║${NC}"
echo -e "${RED}╚════════════════════════════════════════════════════════════════╝${NC}"
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
if [ "$DRY_RUN" = false ]; then
    sudo systemctl unmask sleep.target suspend.target hibernate.target hybrid-sleep.target 2>/dev/null || true
fi

step "Removing Docker..."
if [ "$DRY_RUN" = false ]; then
    sudo systemctl disable --now docker.service docker.socket containerd.service 2>/dev/null || true
    sudo dnf -y remove docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin 2>/dev/null || true
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
    'export M2_HOME=/opt/maven'
    'export PATH="$M2_HOME/bin:$PATH"'
    'export PATH="$JAVA_HOME/bin:$PATH"'
    'eval "$(starship init zsh)"'
)
for line in "${lines_to_remove[@]}"; do
    zshrc_remove "$line"
done
zshrc_remove "export JAVA_HOME="

step "Uninstalling VS Code..."
if [ "$DRY_RUN" = false ]; then
    sudo dnf -y remove code 2>/dev/null || true
fi

step "Removing third-party YUM repositories & manual installs..."
if [ "$DRY_RUN" = false ]; then
    sudo rm -f /etc/yum.repos.d/vscode.repo
    sudo rm -f /etc/yum.repos.d/gh-cli.repo
    sudo rm -f /etc/yum.repos.d/docker-ce.repo
    sudo rm -f /etc/yum.repos.d/nodesource*.repo
    sudo rm -rf /opt/maven /opt/apache-maven-* /usr/local/bin/mvn /tmp/maven.tar.gz
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
