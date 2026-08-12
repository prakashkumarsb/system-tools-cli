#!/bin/bash
set -euo pipefail

# ==============================================================================
# linux-rhel.sh — Setup script for RHEL/CentOS/Fedora/Rocky/AlmaLinux (dnf-based)
# Supports: RHEL 8/9, CentOS Stream 9, Fedora 39/40, Rocky 9, AlmaLinux 9
# ==============================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
step()  { echo -e "\n${GREEN}==>${NC} $1"; }

zshrc_add() {
    grep -qF "$1" ~/.zshrc 2>/dev/null || echo "$1" >> ~/.zshrc
}

# ------------------------------------------------------------------------------
# Distro detection helpers
# ------------------------------------------------------------------------------

. /etc/os-release
DISTRO_ID="${ID:-unknown}"
DISTRO_VERSION_MAJOR="${VERSION_ID%%.*}"

is_fedora()    { [[ "$DISTRO_ID" == "fedora" ]]; }
is_rhel9_plus(){ ! is_fedora && [[ "${DISTRO_VERSION_MAJOR:-0}" -ge 9 ]]; }
is_rhel8()     { ! is_fedora && [[ "${DISTRO_VERSION_MAJOR:-0}" -eq 8 ]]; }

# Docker repo: RHEL 9+ has its own repo; Rocky/Alma/CentOS use centos repo
get_docker_repo_url() {
    case "$DISTRO_ID" in
        rhel) echo "https://download.docker.com/linux/rhel/docker-ce.repo" ;;
        *)    echo "https://download.docker.com/linux/centos/docker-ce.repo" ;;
    esac
}

# Ask for sudo once and keep it alive
sudo -v
while true; do sudo -n true; sleep 55; kill -0 "$$" || exit; done 2>/dev/null &

# ==============================================================================
# 1. BASE CLI TOOLS & PACKAGES
# ==============================================================================

step "Updating packages..."
sudo dnf -y update

# ------------------------------------------------------------------------------
# EPEL + extra repos (non-Fedora only)
# bat, ripgrep, sshpass, shellcheck, wl-clipboard need EPEL
# ------------------------------------------------------------------------------
if ! is_fedora; then
    step "Enabling EPEL repository..."
    if ! rpm -q epel-release &>/dev/null; then
        sudo dnf -y install epel-release
    else
        info "EPEL already enabled"
    fi

    # CRB (RHEL 9 / Rocky 9 / Alma 9) or PowerTools (RHEL 8)
    if is_rhel9_plus; then
        sudo dnf config-manager --set-enabled crb 2>/dev/null || \
        sudo dnf config-manager --set-enabled codeready-builder-for-rhel-9-x86_64-rpms 2>/dev/null || true
        info "CRB repo enabled"
    elif is_rhel8; then
        sudo dnf config-manager --set-enabled powertools 2>/dev/null || \
        sudo dnf config-manager --set-enabled codeready-builder-for-rhel-8-x86_64-rpms 2>/dev/null || true
        info "PowerTools repo enabled"
    fi

    sudo dnf -y update
fi

# ------------------------------------------------------------------------------
# Node.js — default repos ship old versions; use NodeSource for Node 20 LTS
# ------------------------------------------------------------------------------
step "Setting up Node.js 20 LTS..."
if ! command -v node &>/dev/null || [[ "$(node -e 'process.stdout.write(process.version.split(".")[0].slice(1))')" -lt 18 ]]; then
    curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -
    info "NodeSource repo added"
else
    info "Node.js already installed ($(node --version))"
fi

# ------------------------------------------------------------------------------
# Docker (official dnf repo)
# ------------------------------------------------------------------------------
step "Installing Docker..."
if ! command -v docker &>/dev/null; then
    sudo dnf -y install dnf-plugins-core
    DOCKER_REPO=$(get_docker_repo_url)
    sudo dnf config-manager --add-repo "$DOCKER_REPO"
    sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo usermod -aG docker "$USER"
    info "Docker installed — log out and back in for group membership to take effect"
else
    info "Docker already installed"
fi

# ------------------------------------------------------------------------------
# Base CLI packages
# ------------------------------------------------------------------------------
step "Installing CLI tools..."

# Packages common to all RHEL-based distros (after EPEL is enabled)
packages=(
    bash coreutils curl
    git htop
    jq
    python3 python3-pip
    rsync sshpass
    wget zsh
)

# bat: in EPEL 9+ but not EPEL 8 — handle gracefully
if dnf info bat &>/dev/null 2>&1; then
    packages+=(bat)
else
    warn "bat not available in repos for this distro version — skipping"
fi

# ripgrep: in EPEL 8+, Fedora base
packages+=(ripgrep)

# shellcheck: in EPEL 8+
packages+=(shellcheck)

# nodejs (from NodeSource repo added above)
packages+=(nodejs)

# maven: in base repos on Fedora; needs EPEL or manual install on RHEL
if dnf info maven &>/dev/null 2>&1; then
    packages+=(maven)
else
    warn "maven not in repos — will install manually via binary"
    INSTALL_MAVEN_MANUALLY=true
fi

# Java 21
if dnf info java-21-openjdk-devel &>/dev/null 2>&1; then
    packages+=(java-21-openjdk-devel)
elif dnf info java-21-openjdk &>/dev/null 2>&1; then
    packages+=(java-21-openjdk)
else
    warn "java-21-openjdk-devel not available — trying java-latest-openjdk-devel"
    packages+=(java-latest-openjdk-devel)
fi

# pipx: named differently across versions
if is_fedora; then
    packages+=(pipx)
elif dnf info python3-pipx &>/dev/null 2>&1; then
    packages+=(python3-pipx)
else
    warn "pipx not in repos — will install via pip3"
    INSTALL_PIPX_VIA_PIP=true
fi

# wl-clipboard: only on Wayland/desktop systems; skip on headless
if [[ "${DISPLAY:-}${WAYLAND_DISPLAY:-}" != "" ]] || [[ "${XDG_SESSION_TYPE:-}" != "" ]]; then
    if dnf info wl-clipboard &>/dev/null 2>&1; then
        packages+=(wl-clipboard)
    fi
fi

sudo dnf -y install "${packages[@]}"

# Maven manual install (if not in repos)
if [[ "${INSTALL_MAVEN_MANUALLY:-false}" == "true" ]]; then
    MAVEN_VERSION="3.9.6"
    MAVEN_URL="https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"
    sudo curl -fsSL "$MAVEN_URL" -o /tmp/maven.tar.gz
    sudo tar -xz -C /opt -f /tmp/maven.tar.gz
    sudo ln -sfn "/opt/apache-maven-${MAVEN_VERSION}" /opt/maven
    sudo ln -sfn /opt/maven/bin/mvn /usr/local/bin/mvn
    rm -f /tmp/maven.tar.gz
    zshrc_add 'export M2_HOME=/opt/maven'
    zshrc_add 'export PATH="$M2_HOME/bin:$PATH"'
    info "Maven ${MAVEN_VERSION} installed to /opt/maven"
fi

# pipx fallback via pip3
if [[ "${INSTALL_PIPX_VIA_PIP:-false}" == "true" ]]; then
    sudo pip3 install pipx
    info "pipx installed via pip3"
fi

# ------------------------------------------------------------------------------
# GitHub CLI (official rpm repo)
# ------------------------------------------------------------------------------
step "Installing GitHub CLI (gh)..."
if ! command -v gh &>/dev/null; then
    sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
    sudo dnf -y install gh
else
    info "gh already installed"
fi

# ------------------------------------------------------------------------------
# git-lfs
# ------------------------------------------------------------------------------
step "Installing git-lfs..."
if ! command -v git-lfs &>/dev/null; then
    if dnf info git-lfs &>/dev/null 2>&1; then
        sudo dnf -y install git-lfs
    else
        # packagecloud fallback
        curl -fsSL https://packagecloud.io/install/repositories/github/git-lfs/script.rpm.sh | sudo bash
        sudo dnf -y install git-lfs
    fi
else
    info "git-lfs already installed"
fi

# ==============================================================================
# 2. ZSH & OH MY ZSH
# ==============================================================================

step "Checking Oh My Zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
    info "Oh My Zsh already installed"
fi

if [ "$SHELL" != "$(which zsh)" ]; then
    chsh -s "$(which zsh)"
    info "Default shell changed to zsh"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

[ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] || \
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
[ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] || \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
[ -d "$ZSH_CUSTOM/plugins/zsh-history-substring-search" ] || \
    git clone https://github.com/zsh-users/zsh-history-substring-search "$ZSH_CUSTOM/plugins/zsh-history-substring-search"

zshrc_add 'source $ZSH_CUSTOM/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh'
zshrc_add 'source $ZSH_CUSTOM/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh'
zshrc_add 'source $ZSH_CUSTOM/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh'

# ==============================================================================
# 3. GUI APPLICATIONS
# ==============================================================================

step "Installing VS Code..."
if ! command -v code &>/dev/null; then
    sudo rpm --import https://packages.microsoft.com/keys/microsoft.asc
    sudo tee /etc/yum.repos.d/vscode.repo > /dev/null << 'EOF'
[code]
name=Visual Studio Code
baseurl=https://packages.microsoft.com/yumrepos/vscode
enabled=1
gpgcheck=1
gpgkey=https://packages.microsoft.com/keys/microsoft.asc
EOF
    sudo dnf -y install code
else
    info "VS Code already installed"
fi

# ==============================================================================
# 4. ENVIRONMENT CONFIGURATION
# ==============================================================================

step "Configuring Java environment..."
# Detect JAVA_HOME dynamically — works on both x86_64 and aarch64
JAVA_BIN=$(readlink -f "$(which java)" 2>/dev/null || true)
if [[ -n "$JAVA_BIN" ]]; then
    JAVA_HOME_PATH=$(dirname "$(dirname "$JAVA_BIN")")
    zshrc_add "export JAVA_HOME=${JAVA_HOME_PATH}"
else
    warn "Could not auto-detect JAVA_HOME — set it manually after install"
fi
zshrc_add 'export PATH="$JAVA_HOME/bin:$PATH"'

step "Initializing Git LFS..."
sudo git lfs install --system

# ==============================================================================
# 5. OPTIONAL SSH SERVER (remote access via password)
# ==============================================================================

read -rp "Do you want to install and configure SSH server (password authentication)? [y/N]: " ssh_response
if [[ "$ssh_response" =~ ^[Yy]$ ]]; then
    step "Setting up SSH server..."
    sudo dnf -y install openssh-server

    SSHD_CONFIG="/etc/ssh/sshd_config"
    sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG"
    sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/'               "$SSHD_CONFIG"
    sudo sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/'    "$SSHD_CONFIG"

    grep -q "^PasswordAuthentication" "$SSHD_CONFIG" || echo "PasswordAuthentication yes" | sudo tee -a "$SSHD_CONFIG" > /dev/null
    grep -q "^PermitRootLogin"        "$SSHD_CONFIG" || echo "PermitRootLogin no"           | sudo tee -a "$SSHD_CONFIG" > /dev/null
    grep -q "^PubkeyAuthentication"   "$SSHD_CONFIG" || echo "PubkeyAuthentication yes"     | sudo tee -a "$SSHD_CONFIG" > /dev/null

    # RHEL uses firewalld, not ufw
    if command -v firewall-cmd &>/dev/null && sudo firewall-cmd --state 2>/dev/null | grep -q running; then
        sudo firewall-cmd --permanent --add-service=ssh
        sudo firewall-cmd --reload
        info "Firewall: port 22 allowed via firewalld"
    fi

    # Service name is 'sshd' on RHEL-based (not 'ssh')
    sudo systemctl enable sshd
    sudo systemctl restart sshd

    info "SSH server running — connect with: ssh $(whoami)@$(hostname -I | awk '{print $1}')"
    warn "Make sure your user account has a password set: passwd $(whoami)"
fi

# ==============================================================================
# 6. TAILSCALE (OPTIONAL)
# ==============================================================================

read -rp "Do you want to install and configure Tailscale? [y/N]: " ts_response
if [[ "$ts_response" =~ ^[Yy]$ ]]; then
    step "Installing and configuring Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    sudo systemctl enable tailscaled
    sudo systemctl start tailscaled
    sudo tailscale up --ssh --accept-routes --accept-dns
fi

# ==============================================================================
# 7. VS CODE TUNNEL (runs last so user can authenticate interactively)
# ==============================================================================

read -rp "Do you want to enable VS Code Tunnel as a service? [y/N]: " vst_response
if [[ "$vst_response" =~ ^[Yy]$ ]]; then
    step "Setting up VS Code Tunnel as a service..."
    CODE_CMD="$(command -v code 2>/dev/null || true)"
    if [ -z "$CODE_CMD" ]; then
        warn "VS Code CLI (code) not found — skipping tunnel setup"
    else
        warn "Follow the authentication prompts below to complete tunnel setup"
        default_name=$(hostname -s)
        read -rp "  Tunnel name [$default_name]: " tunnel_name
        tunnel_name="${tunnel_name:-$default_name}"
        "$CODE_CMD" tunnel service install --accept-server-license-terms --name "$tunnel_name"
        info "VS Code Tunnel service installed and running"
        sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
        info "System sleep/suspend disabled to keep tunnel reachable"
    fi
fi

# ==============================================================================
# 8. VERIFICATION
# ==============================================================================

step "Verifying..."
java -version 2>&1 | head -1
info "Setup complete! Open a new terminal or run: exec zsh"
