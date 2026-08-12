#!/bin/bash
set -euo pipefail

# ==============================================================================
# linux-debian.sh — Setup script for Debian/Ubuntu/MX Linux (apt-based)
# Supports: Debian 11/12, Ubuntu 22.04/24.04, MX Linux 23
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

# Returns 'debian' or 'ubuntu' — used for Docker repo URL
get_docker_distro_id() {
    . /etc/os-release
    case "${ID_LIKE:-$ID}" in
        *ubuntu*) echo "ubuntu" ;;
        *)        echo "debian"  ;;
    esac
}

# Returns the upstream Debian/Ubuntu codename suitable for apt repos
# MX Linux 23 → bookworm, MX Linux 21 → bullseye, etc.
get_distro_codename() {
    . /etc/os-release
    local codename="${VERSION_CODENAME:-}"
    # MX Linux: VERSION_CODENAME may be "libretto" (MX internal) — use DEBIAN_CODENAME instead
    if [[ "${ID:-}" == "mx" || -n "${DEBIAN_CODENAME:-}" ]]; then
        codename="${DEBIAN_CODENAME:-$codename}"
    fi
    # Last resort: parse from /etc/debian_version
    if [[ -z "$codename" && -f /etc/debian_version ]]; then
        local ver
        ver=$(cat /etc/debian_version)
        case "$ver" in
            12*|bookworm*) codename="bookworm" ;;
            11*|bullseye*) codename="bullseye" ;;
            10*|buster*)   codename="buster"   ;;
        esac
    fi
    echo "$codename"
}

# Returns host architecture in Docker/apt format (amd64, arm64, armhf)
get_arch() {
    dpkg --print-architecture
}

# Detects init system: 'systemd' or 'sysvinit'
get_init() {
    if pidof systemd &>/dev/null || [ -d /run/systemd/system ]; then
        echo "systemd"
    else
        echo "sysvinit"
    fi
}

# Ubuntu version number (e.g. 22, 24) — empty on non-Ubuntu
get_ubuntu_version() {
    . /etc/os-release
    if [[ "${ID:-}" == "ubuntu" ]]; then
        echo "${VERSION_ID%%.*}"
    else
        echo ""
    fi
}

# Ask for sudo once and keep it alive
sudo -v
while true; do sudo -n true; sleep 55; kill -0 "$$" || exit; done 2>/dev/null &

ARCH=$(get_arch)
INIT=$(get_init)

# ==============================================================================
# 1. BASE CLI TOOLS & PACKAGES
# ==============================================================================

step "Updating package lists..."
sudo apt-get update

# Install prerequisites
sudo apt-get install -y ca-certificates curl gnupg lsb-release wget software-properties-common

# ------------------------------------------------------------------------------
# Node.js — default apt repos ship EOL versions; use NodeSource for Node 20 LTS
# ------------------------------------------------------------------------------
step "Setting up Node.js 20 LTS repo..."
if ! command -v node &>/dev/null || [[ "$(node -e 'process.stdout.write(process.version.split(".")[0].slice(1))')" -lt 18 ]]; then
    curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -
    info "NodeSource repo added"
else
    info "Node.js already installed ($(node --version))"
fi

# ------------------------------------------------------------------------------
# Docker (official apt repo)
# ------------------------------------------------------------------------------
step "Installing Docker..."
if ! command -v docker &>/dev/null; then
    sudo install -m 0755 -d /etc/apt/keyrings
    DOCKER_DISTRO=$(get_docker_distro_id)
    DOCKER_CODENAME=$(get_distro_codename)

    curl -fsSL "https://download.docker.com/linux/${DOCKER_DISTRO}/gpg" \
        | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
    sudo chmod a+r /etc/apt/keyrings/docker.gpg

    echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] \
https://download.docker.com/linux/${DOCKER_DISTRO} ${DOCKER_CODENAME} stable" \
        | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null

    sudo apt-get update
    sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo usermod -aG docker "$USER"
    info "Docker installed — log out and back in for group membership to take effect"
else
    info "Docker already installed"
fi

# ------------------------------------------------------------------------------
# GitHub CLI (official apt repo)
# ------------------------------------------------------------------------------
step "Installing GitHub CLI (gh)..."
if ! command -v gh &>/dev/null; then
    sudo mkdir -p -m 755 /etc/apt/keyrings
    wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg \
        | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
    echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] \
https://cli.github.com/packages stable main" \
        | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y gh
else
    info "gh already installed"
fi

# ------------------------------------------------------------------------------
# Base CLI packages (common across all apt distros)
# ------------------------------------------------------------------------------
step "Installing CLI tools..."
packages=(
    bash coreutils curl
    git htop
    jq maven
    python3 python3-pip
    ripgrep rsync shellcheck sshpass
    watch wget
    zsh
)

# bat: package name is 'bat' on Ubuntu 20.04+ and Debian 11+
# Older versions may not have it — install with fallback
if apt-cache show bat &>/dev/null 2>&1; then
    packages+=(bat)
else
    warn "bat not available in apt — skipping (install manually if needed)"
fi

# nodejs: installed via NodeSource above
packages+=(nodejs)

# pipx: available in Ubuntu 23.04+, Debian 12+; use pip install on older
UBUNTU_VER=$(get_ubuntu_version)
if apt-cache show pipx &>/dev/null 2>&1; then
    packages+=(pipx)
else
    warn "pipx not in apt — will install via pip3"
    INSTALL_PIPX_VIA_PIP=true
fi

# openjdk-21-jdk: available in Ubuntu 23.10+, Debian 12+
# Ubuntu 22.04 needs deadsnakes PPA or manual install
if apt-cache show openjdk-21-jdk &>/dev/null 2>&1; then
    packages+=(openjdk-21-jdk)
else
    warn "openjdk-21-jdk not in default apt — adding backports/PPA..."
    if [[ "${UBUNTU_VER}" == "22" ]]; then
        sudo add-apt-repository -y ppa:openjdk-r/ppa
        sudo apt-get update
        packages+=(openjdk-21-jdk)
    elif grep -qi debian /etc/os-release; then
        # Debian 11 (bullseye): use backports
        CODENAME=$(get_distro_codename)
        echo "deb http://deb.debian.org/debian ${CODENAME}-backports main" \
            | sudo tee /etc/apt/sources.list.d/backports.list > /dev/null
        sudo apt-get update
        packages+=(openjdk-21-jdk)
    fi
fi

# wl-clipboard: only useful on Wayland — install anyway, harmless on X11
# Skip on MX Linux where it's unnecessary
. /etc/os-release
if [[ "${ID:-}" != "mx" ]]; then
    packages+=(wl-clipboard)
fi

sudo apt-get install -y "${packages[@]}"

# bat on Debian/Ubuntu is installed as 'batcat' — create alias
if command -v batcat &>/dev/null && ! command -v bat &>/dev/null; then
    zshrc_add 'alias bat=batcat'
    info "Added bat=batcat alias"
fi

# git-lfs (via packagecloud or apt)
if ! command -v git-lfs &>/dev/null; then
    if apt-cache show git-lfs &>/dev/null 2>&1; then
        sudo apt-get install -y git-lfs
    else
        curl -fsSL https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | sudo bash
        sudo apt-get install -y git-lfs
    fi
fi

# pipx fallback via pip3
if [[ "${INSTALL_PIPX_VIA_PIP:-false}" == "true" ]]; then
    sudo pip3 install --break-system-packages pipx 2>/dev/null || sudo pip3 install pipx
    info "pipx installed via pip3"
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
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc \
        | sudo gpg --dearmor -o /usr/share/keyrings/packages.microsoft.gpg
    # Use detected arch — VS Code supports amd64 and arm64
    echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/packages.microsoft.gpg] \
https://packages.microsoft.com/repos/code stable main" \
        | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y code
else
    info "VS Code already installed"
fi

# ==============================================================================
# 4. ENVIRONMENT CONFIGURATION
# ==============================================================================

step "Configuring Java environment..."
# Detect JAVA_HOME dynamically to support both amd64 and arm64
JAVA_BIN=$(readlink -f "$(which java)" 2>/dev/null || true)
if [[ -n "$JAVA_BIN" ]]; then
    JAVA_HOME_PATH=$(dirname "$(dirname "$JAVA_BIN")")
    zshrc_add "export JAVA_HOME=${JAVA_HOME_PATH}"
else
    # Fallback — works on amd64 Debian/Ubuntu
    zshrc_add 'export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64'
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
    sudo apt-get install -y openssh-server

    SSHD_CONFIG="/etc/ssh/sshd_config"
    sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG"
    sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/'               "$SSHD_CONFIG"
    sudo sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/'    "$SSHD_CONFIG"

    grep -q "^PasswordAuthentication" "$SSHD_CONFIG" || echo "PasswordAuthentication yes" | sudo tee -a "$SSHD_CONFIG" > /dev/null
    grep -q "^PermitRootLogin"        "$SSHD_CONFIG" || echo "PermitRootLogin no"           | sudo tee -a "$SSHD_CONFIG" > /dev/null
    grep -q "^PubkeyAuthentication"   "$SSHD_CONFIG" || echo "PubkeyAuthentication yes"     | sudo tee -a "$SSHD_CONFIG" > /dev/null

    if command -v ufw &>/dev/null && sudo ufw status 2>/dev/null | grep -q "Status: active"; then
        sudo ufw allow ssh
        info "Firewall: port 22 allowed"
    fi

    # Service name is 'ssh' on Debian/Ubuntu, handle both init systems
    if [[ "$INIT" == "systemd" ]]; then
        sudo systemctl enable ssh 2>/dev/null || sudo systemctl enable sshd
        sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd
    else
        sudo update-rc.d ssh defaults 2>/dev/null || sudo update-rc.d sshd defaults
        sudo service ssh restart 2>/dev/null || sudo service sshd restart
    fi

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
    if [[ "$INIT" == "systemd" ]]; then
        sudo systemctl enable tailscaled
        sudo systemctl start tailscaled
    else
        sudo tee /etc/init.d/tailscaled > /dev/null << 'INITSCRIPT'
#!/bin/sh
### BEGIN INIT INFO
# Provides:          tailscaled
# Required-Start:    $network $remote_fs
# Required-Stop:     $network $remote_fs
# Default-Start:     2 3 4 5
# Default-Stop:      0 1 6
# Description:       Tailscale daemon
### END INIT INFO
DAEMON=/usr/sbin/tailscaled
PIDFILE=/var/run/tailscaled.pid
case "$1" in
    start)  start-stop-daemon --start --background --make-pidfile --pidfile "$PIDFILE" --exec "$DAEMON" ;;
    stop)   start-stop-daemon --stop --pidfile "$PIDFILE" --retry 5 ;;
    restart) "$0" stop; "$0" start ;;
    *)      echo "Usage: $0 {start|stop|restart}"; exit 1 ;;
esac
INITSCRIPT
        sudo chmod +x /etc/init.d/tailscaled
        sudo update-rc.d tailscaled defaults
        sudo /etc/init.d/tailscaled start
    fi
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
        if [[ "$INIT" == "systemd" ]]; then
            sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
        fi
        info "System sleep/suspend disabled to keep tunnel reachable"
    fi
fi

# ==============================================================================
# 8. VERIFICATION
# ==============================================================================

step "Verifying..."
java -version 2>&1 | head -1
info "Setup complete! Open a new terminal or run: exec zsh"
