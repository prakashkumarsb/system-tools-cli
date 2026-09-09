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

export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a

# ==============================================================================
# linux-debian.sh — Setup script for Debian/Ubuntu/MX Linux (apt-based)
# ==============================================================================

# ==============================================================================
# CLI FLAGS, LOGGING & ENVIRONMENT
# ==============================================================================

init_cli_flags "$@"
init_logging "linux-debian-setup"

get_docker_distro_id() {
    . /etc/os-release
    case "${ID:-}" in
        ubuntu) echo "ubuntu" ;;
        debian) echo "debian" ;;
        *)
            case "${ID_LIKE:-}" in
                *ubuntu*) echo "ubuntu" ;;
                *)        echo "debian"  ;;
            esac
            ;;
    esac
}

get_distro_codename() {
    . /etc/os-release
    local codename="${VERSION_CODENAME:-}"
    if [[ -n "${UBUNTU_CODENAME:-}" ]]; then
        codename="${UBUNTU_CODENAME}"
    elif [[ "${ID:-}" == "mx" || -n "${DEBIAN_CODENAME:-}" ]]; then
        codename="${DEBIAN_CODENAME:-$codename}"
    fi
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

get_arch() {
    dpkg --print-architecture 2>/dev/null || echo "amd64"
}

get_init() {
    if pidof systemd &>/dev/null || [ -d /run/systemd/system ]; then
        echo "systemd"
    else
        echo "sysvinit"
    fi
}

get_ubuntu_version() {
    . /etc/os-release
    if [[ "${ID:-}" == "ubuntu" ]]; then
        echo "${VERSION_ID%%.*}"
    else
        echo ""
    fi
}

init_sudo_keepalive

ARCH=$(get_arch)
INIT=$(get_init)

# ==============================================================================
# 1. BASE CLI TOOLS & PACKAGES
# ==============================================================================

step "Updating package lists..."
if [ "$DRY_RUN" = false ]; then
    sudo rm -f /etc/apt/sources.list.d/docker.list
    sudo apt-get update
    base_pkgs=(ca-certificates curl gnupg lsb-release wget)
    if apt-cache show software-properties-common &>/dev/null; then
        base_pkgs+=(software-properties-common)
    fi
    sudo apt-get install -y "${base_pkgs[@]}"
fi

step "Setting up Node.js 20 LTS repo..."
if ! command -v node &>/dev/null; then
    run_cmd bash -c "curl -fsSL https://deb.nodesource.com/setup_20.x | sudo -E bash -"
else
    info "Node.js already installed"
fi

step "Installing Docker..."
if ! command -v docker &>/dev/null; then
    if [ "$DRY_RUN" = false ]; then
        sudo rm -f /etc/apt/sources.list.d/docker.list
        sudo rm -f /etc/apt/keyrings/docker.gpg
        sudo install -m 0755 -d /etc/apt/keyrings
        DOCKER_DISTRO=$(get_docker_distro_id)
        DOCKER_CODENAME=$(get_distro_codename)
        curl -fsSL "https://download.docker.com/linux/${DOCKER_DISTRO}/gpg" | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/${DOCKER_DISTRO} ${DOCKER_CODENAME} stable" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        sudo apt-get update
        sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-compose-plugin
        sudo usermod -aG docker "$USER"
    fi
else
    info "Docker already installed"
fi

step "Installing GitHub CLI (gh)..."
if ! command -v gh &>/dev/null; then
    if [ "$DRY_RUN" = false ]; then
        sudo mkdir -p -m 755 /etc/apt/keyrings
        wget -qO- https://cli.github.com/packages/githubcli-archive-keyring.gpg | sudo tee /etc/apt/keyrings/githubcli-archive-keyring.gpg > /dev/null
        echo "deb [arch=${ARCH} signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" | sudo tee /etc/apt/sources.list.d/github-cli.list > /dev/null
        sudo apt-get update
        sudo apt-get install -y gh
    fi
else
    info "gh already installed"
fi

step "Installing CLI tools..."
packages=(
    bash coreutils curl
    git htop
    jq maven parallel
    python3 python3-pip
    ripgrep rsync shellcheck sshpass
    watch wget
    zsh
)

if apt-cache show bat &>/dev/null 2>&1; then
    packages+=(bat)
fi
packages+=(nodejs)

UBUNTU_VER=$(get_ubuntu_version)
if apt-cache show pipx &>/dev/null 2>&1; then
    packages+=(pipx)
else
    INSTALL_PIPX_VIA_PIP=true
fi

if apt-cache show openjdk-21-jdk &>/dev/null 2>&1; then
    packages+=(openjdk-21-jdk)
else
    if [[ "${UBUNTU_VER}" == "22" && "$DRY_RUN" = false ]]; then
        sudo add-apt-repository -y ppa:openjdk-r/ppa
        sudo apt-get update
        packages+=(openjdk-21-jdk)
    elif grep -qi debian /etc/os-release 2>/dev/null && [ "$DRY_RUN" = false ]; then
        CODENAME=$(get_distro_codename)
        echo "deb http://deb.debian.org/debian ${CODENAME}-backports main" | sudo tee /etc/apt/sources.list.d/backports.list > /dev/null
        sudo apt-get update
        packages+=(openjdk-21-jdk)
    fi
fi

. /etc/os-release 2>/dev/null || true
if [[ "${ID:-}" != "mx" ]]; then
    packages+=(wl-clipboard)
fi

if [ "$DRY_RUN" = false ]; then
    sudo apt-get install -y "${packages[@]}"
fi

if command -v batcat &>/dev/null && ! command -v bat &>/dev/null && [ "$DRY_RUN" = false ]; then
    sudo ln -sf "$(which batcat)" /usr/local/bin/bat
fi

if ! command -v git-lfs &>/dev/null && [ "$DRY_RUN" = false ]; then
    if apt-cache show git-lfs &>/dev/null 2>&1; then
        sudo apt-get install -y git-lfs
    else
        curl -fsSL https://packagecloud.io/install/repositories/github/git-lfs/script.deb.sh | sudo bash
        sudo apt-get install -y git-lfs
    fi
fi

if [[ "${INSTALL_PIPX_VIA_PIP:-false}" == "true" && "$DRY_RUN" = false ]]; then
    sudo pip3 install --break-system-packages pipx 2>/dev/null || sudo pip3 install pipx
fi

# ==============================================================================
# DEVOPS TOOLS: yq AND starship
# ==============================================================================

step "Installing yq & Starship..."
if ! command -v yq &>/dev/null; then
    if [ "$DRY_RUN" = false ]; then
        YQ_ARCH="${ARCH}"
        [[ "$YQ_ARCH" == "amd64" ]] && YQ_BIN="yq_linux_amd64" || YQ_BIN="yq_linux_${YQ_ARCH}"
        sudo wget -q "https://github.com/mikefarah/yq/releases/latest/download/${YQ_BIN}" -O /usr/local/bin/yq || true
        sudo chmod +x /usr/local/bin/yq 2>/dev/null || true
    fi
fi

if ! command -v starship &>/dev/null; then
    if [ "$DRY_RUN" = false ]; then
        curl -fsSL https://starship.rs/install.sh | sh -s -- -y || true
    fi
fi

# ==============================================================================
# 2. ZSH & OH MY ZSH
# ==============================================================================

step "Checking Oh My Zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    if [ "$DRY_RUN" = true ]; then
        info "[DRY-RUN] Would install Oh My Zsh"
    else
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
fi

if [ "$SHELL" != "$(command -v zsh || echo '/bin/zsh')" ] && [ "$DRY_RUN" = false ]; then
    chsh -s "$(command -v zsh)" || true
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

if [ "$DRY_RUN" = false ]; then
    [ -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ] || git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
    [ -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ] || git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
    [ -d "$ZSH_CUSTOM/plugins/zsh-history-substring-search" ] || git clone https://github.com/zsh-users/zsh-history-substring-search "$ZSH_CUSTOM/plugins/zsh-history-substring-search"
fi

zshrc_add 'source $ZSH_CUSTOM/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh'
zshrc_add 'source $ZSH_CUSTOM/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh'
zshrc_add 'source $ZSH_CUSTOM/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh'
if command -v batcat &>/dev/null; then
    zshrc_add 'alias bat=batcat'
fi
zshrc_add 'eval "$(starship init zsh)"'

# ==============================================================================
# 3. GUI APPLICATIONS
# ==============================================================================

step "Installing VS Code..."
if ! command -v code &>/dev/null && [ "$DRY_RUN" = false ]; then
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/packages.microsoft.gpg
    echo "deb [arch=${ARCH} signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list > /dev/null
    sudo apt-get update
    sudo apt-get install -y code
fi

# ==============================================================================
# 4. ENVIRONMENT CONFIGURATION
# ==============================================================================

step "Configuring Java environment..."
if command -v java &>/dev/null; then
    JAVA_BIN=$(readlink -f "$(which java)")
    JAVA_HOME_PATH=$(dirname "$(dirname "$JAVA_BIN")")
    zshrc_add "export JAVA_HOME=${JAVA_HOME_PATH}"
else
    zshrc_add 'export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64'
fi
zshrc_add 'export PATH="$JAVA_HOME/bin:$PATH"'

step "Initializing Git LFS..."
run_cmd sudo git lfs install --system

# ==============================================================================
# 5. LXQT XSCREENSAVER AUTO-LOCK
# ==============================================================================

# Detect LXQt desktop environment (Lubuntu, Debian+LXQt, Ubuntu+LXQt, MX Linux+LXQt, etc.)
# LXQt does not ship its own screensaver; xscreensaver is the standard choice for X11 sessions.
if dpkg -l | grep -q lxqt-core 2>/dev/null || [[ -n "${XDG_CURRENT_DESKTOP:-}" && "${XDG_CURRENT_DESKTOP}" == *"LXQt"* ]]; then
    step "Configuring xscreensaver auto-lock for LXQt..."
    if [ "$DRY_RUN" = false ]; then
        # Install xscreensaver if not present
        if ! command -v xscreensaver &>/dev/null; then
            sudo apt-get install -y xscreensaver
        fi
        # Create xscreensaver config with 5-minute blank + immediate lock
        cat << 'XSCREENSAVER_EOF' > ~/.xscreensaver
timeout:        0:05:00
lock:           True
lockTimeout:    0:00:00
XSCREENSAVER_EOF
        info "Created ~/.xscreensaver with 5-minute auto-lock"
        # Add xscreensaver daemon to LXQt autostart
        AUTOSTART_DIR="$HOME/.config/autostart"
        mkdir -p "$AUTOSTART_DIR"
        cat << 'AUTOSTART_EOF' > "$AUTOSTART_DIR/xscreensaver.desktop"
[Desktop Entry]
Type=Application
Name=XScreenSaver
Exec=xscreensaver -nosplash
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
AUTOSTART_EOF
        info "Added xscreensaver to autostart"
    else
        info "[DRY-RUN] Would configure xscreensaver auto-lock for LXQt"
    fi
fi

# ==============================================================================
# 5b. XFCE SCREENSAVER AUTO-LOCK (MX Linux / Xubuntu / Debian+XFCE)
# ==============================================================================

# Detect XFCE desktop environment
if [[ -n "${XDG_CURRENT_DESKTOP:-}" && "${XDG_CURRENT_DESKTOP}" == *"XFCE"* ]] || command -v xfce4-session &>/dev/null; then
    step "Configuring xfce4-screensaver auto-lock for XFCE..."
    if [ "$DRY_RUN" = false ]; then
        # Install xfce4-screensaver if not present (default on MX Linux)
        if ! command -v xfce4-screensaver &>/dev/null; then
            sudo apt-get install -y xfce4-screensaver
        fi

        # Configure via xfconf-query (XFCE's settings backend)
        # Enable screensaver
        xfconf-query -c xfce4-screensaver -p /saver/enabled -s true --create -t bool
        # Set idle timeout to 5 minutes (300 seconds)
        xfconf-query -c xfce4-screensaver -p /saver/idle-activation/delay -s 5 --create -t int
        # Enable lock on activation
        xfconf-query -c xfce4-screensaver -p /lock/enabled -s true --create -t bool
        # Lock immediately when screensaver activates (0 minutes delay)
        xfconf-query -c xfce4-screensaver -p /lock/saver-activation/delay -s 0 --create -t int
        # Also lock on suspend/sleep
        xfconf-query -c xfce4-screensaver -p /lock/sleep-activation/enabled -s true --create -t bool

        info "Configured xfce4-screensaver: 5-minute idle → immediate lock"
    else
        info "[DRY-RUN] Would configure xfce4-screensaver auto-lock for XFCE"
    fi
fi

# ==============================================================================
# 6. OPTIONAL SSH SERVER
# ==============================================================================

if [ "$NON_INTERACTIVE" = true ]; then
    ssh_response="n"
else
    read -rp "Do you want to install and configure SSH server? [y/N]: " ssh_response || ssh_response="n"
fi

if [[ "$ssh_response" =~ ^[Yy]$ && "$DRY_RUN" = false ]]; then
    step "Setting up SSH server..."
    sudo apt-get install -y openssh-server
    SSHD_CONFIG="/etc/ssh/sshd_config"
    sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG"
    sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/'               "$SSHD_CONFIG"
    sudo sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/'    "$SSHD_CONFIG"
    if command -v ufw &>/dev/null && sudo ufw status 2>/dev/null | grep -q "Status: active"; then
        sudo ufw allow ssh
    fi
    if [[ "$INIT" == "systemd" ]]; then
        sudo systemctl enable ssh 2>/dev/null || sudo systemctl enable sshd
        sudo systemctl restart ssh 2>/dev/null || sudo systemctl restart sshd
    else
        sudo update-rc.d ssh defaults 2>/dev/null || sudo update-rc.d sshd defaults
        sudo service ssh restart 2>/dev/null || sudo service sshd restart
    fi
fi

# ==============================================================================
# 7. TAILSCALE (OPTIONAL)
# ==============================================================================

if [ "$NON_INTERACTIVE" = true ]; then
    ts_response="n"
else
    read -rp "Do you want to install and configure Tailscale? [y/N]: " ts_response || ts_response="n"
fi

if [[ "$ts_response" =~ ^[Yy]$ && "$DRY_RUN" = false ]]; then
    step "Installing and configuring Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    if [[ "$INIT" == "systemd" ]]; then
        sudo systemctl enable tailscaled
        sudo systemctl start tailscaled
    fi
    sudo tailscale up --ssh --accept-routes --accept-dns || true
fi

# ==============================================================================
# 8. VS CODE TUNNEL
# ==============================================================================

if [ "$NON_INTERACTIVE" = true ]; then
    vst_response="n"
else
    read -rp "Do you want to enable VS Code Tunnel as a service? [y/N]: " vst_response || vst_response="n"
fi

if [[ "$vst_response" =~ ^[Yy]$ && "$DRY_RUN" = false ]]; then
    step "Setting up VS Code Tunnel as a service..."
    CODE_CMD="$(command -v code 2>/dev/null || true)"
    if [ -n "$CODE_CMD" ]; then
        default_name=$(hostname -s)
        tunnel_name="${default_name}"
        if [ "$NON_INTERACTIVE" = false ]; then
            read -rp "  Tunnel name [$default_name]: " input_name || input_name=""
            tunnel_name="${input_name:-$default_name}"
        fi
        "$CODE_CMD" tunnel service install --accept-server-license-terms --name "$tunnel_name"
        if [[ "$INIT" == "systemd" ]]; then
            sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
        fi
    fi
fi

# ==============================================================================
# 9. STATE MANIFEST & VERIFICATION
# ==============================================================================

step "Writing installation manifest..."
MANIFEST_DIR="$HOME/.config/setup"
if [ "$DRY_RUN" = false ]; then
    mkdir -p "$MANIFEST_DIR"
    if command -v jq &>/dev/null; then
        PKGS_JSON=$(printf '%s\n' "${packages[@]}" | jq -R . | jq -s .)
    else
        PKGS_JSON="[]"
    fi
    cat <<EOF > "$MANIFEST_DIR/manifest.json"
{
  "platform": "Debian/Ubuntu",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "packages": ${PKGS_JSON}
}
EOF
fi
info "State written to $MANIFEST_DIR/manifest.json"

step "Verifying..."
if [ "$DRY_RUN" = false ] && command -v java &>/dev/null; then
    java -version 2>&1 | head -1 || true
fi
info "Setup complete! Open a new terminal or run: exec zsh"
