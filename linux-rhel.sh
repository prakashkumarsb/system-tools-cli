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

# ==============================================================================
# linux-rhel.sh — Setup script for RHEL/CentOS/Fedora/Rocky/AlmaLinux (dnf-based)
# ==============================================================================

# ==============================================================================
# CLI FLAGS, LOGGING & ENVIRONMENT
# ==============================================================================

init_cli_flags "$@"
init_logging "linux-rhel-setup"

. /etc/os-release 2>/dev/null || true
DISTRO_ID="${ID:-unknown}"
DISTRO_VERSION_MAJOR="${VERSION_ID%%.*}"

is_fedora()    { [[ "$DISTRO_ID" == "fedora" ]]; }
is_rhel9_plus(){ ! is_fedora && [[ "${DISTRO_VERSION_MAJOR:-0}" -ge 9 ]]; }
is_rhel8()     { ! is_fedora && [[ "${DISTRO_VERSION_MAJOR:-0}" -eq 8 ]]; }

get_docker_repo_url() {
    case "$DISTRO_ID" in
        fedora) echo "https://download.docker.com/linux/fedora/docker-ce.repo" ;;
        rhel)   echo "https://download.docker.com/linux/rhel/docker-ce.repo"   ;;
        *)      echo "https://download.docker.com/linux/centos/docker-ce.repo" ;;
    esac
}

init_sudo_keepalive

# ==============================================================================
# 1. BASE CLI TOOLS & PACKAGES
# ==============================================================================

step "Updating packages..."
run_cmd sudo dnf -y update

if ! is_fedora && [ "$DRY_RUN" = false ]; then
    step "Enabling EPEL repository..."
    if ! rpm -q epel-release &>/dev/null; then
        sudo dnf -y install epel-release
    fi

    if is_rhel9_plus; then
        sudo dnf config-manager --set-enabled crb 2>/dev/null || true
    elif is_rhel8; then
        sudo dnf config-manager --set-enabled powertools 2>/dev/null || true
    fi
    sudo dnf -y update
fi

step "Setting up Node.js 20 LTS..."
if ! command -v node &>/dev/null; then
    run_cmd bash -c "curl -fsSL https://rpm.nodesource.com/setup_20.x | sudo bash -"
fi

step "Installing Docker..."
if ! command -v docker &>/dev/null && [ "$DRY_RUN" = false ]; then
    sudo dnf -y install dnf-plugins-core
    DOCKER_REPO=$(get_docker_repo_url)
    sudo dnf config-manager --add-repo "$DOCKER_REPO"
    sudo dnf -y install docker-ce docker-ce-cli containerd.io docker-compose-plugin
    sudo systemctl enable docker
    sudo systemctl start docker
    sudo usermod -aG docker "$USER"
fi

step "Installing CLI tools..."
packages=(
    bash coreutils curl
    git htop
    jq parallel
    python3 python3-pip
    rsync sshpass
    wget zsh
)

if dnf info bat &>/dev/null 2>&1; then packages+=(bat); fi
packages+=(ripgrep)
packages+=(shellcheck)
packages+=(nodejs)

if dnf info maven &>/dev/null 2>&1; then
    packages+=(maven)
else
    INSTALL_MAVEN_MANUALLY=true
fi

if dnf info java-21-openjdk-devel &>/dev/null 2>&1; then
    packages+=(java-21-openjdk-devel)
elif dnf info java-21-openjdk &>/dev/null 2>&1; then
    packages+=(java-21-openjdk)
else
    packages+=(java-latest-openjdk-devel)
fi

if is_fedora; then
    packages+=(pipx)
elif dnf info python3-pipx &>/dev/null 2>&1; then
    packages+=(python3-pipx)
else
    INSTALL_PIPX_VIA_PIP=true
fi

if [[ "${DISPLAY:-}${WAYLAND_DISPLAY:-}" != "" ]] || [[ "${XDG_SESSION_TYPE:-}" != "" ]]; then
    if dnf info wl-clipboard &>/dev/null 2>&1; then
        packages+=(wl-clipboard)
    fi
fi

if [ "$DRY_RUN" = false ]; then
    sudo dnf -y install "${packages[@]}"
fi

if [[ "${INSTALL_MAVEN_MANUALLY:-false}" == "true" && "$DRY_RUN" = false ]]; then
    MAVEN_VERSION="3.9.6"
    MAVEN_URL="https://archive.apache.org/dist/maven/maven-3/${MAVEN_VERSION}/binaries/apache-maven-${MAVEN_VERSION}-bin.tar.gz"
    sudo curl -fsSL "$MAVEN_URL" -o /tmp/maven.tar.gz
    sudo tar -xz -C /opt -f /tmp/maven.tar.gz
    sudo ln -sfn "/opt/apache-maven-${MAVEN_VERSION}" /opt/maven
    sudo ln -sfn /opt/maven/bin/mvn /usr/local/bin/mvn
    rm -f /tmp/maven.tar.gz
fi

if [[ "${INSTALL_PIPX_VIA_PIP:-false}" == "true" && "$DRY_RUN" = false ]]; then
    sudo pip3 install pipx || true
fi

step "Installing GitHub CLI (gh)..."
if ! command -v gh &>/dev/null && [ "$DRY_RUN" = false ]; then
    sudo dnf config-manager --add-repo https://cli.github.com/packages/rpm/gh-cli.repo
    sudo dnf -y install gh
fi

step "Installing git-lfs..."
if ! command -v git-lfs &>/dev/null && [ "$DRY_RUN" = false ]; then
    if dnf info git-lfs &>/dev/null 2>&1; then
        sudo dnf -y install git-lfs
    else
        curl -fsSL https://packagecloud.io/install/repositories/github/git-lfs/script.rpm.sh | sudo bash
        sudo dnf -y install git-lfs
    fi
fi

# ==============================================================================
# DEVOPS TOOLS: yq AND starship
# ==============================================================================

step "Installing yq & Starship..."
if ! command -v yq &>/dev/null && [ "$DRY_RUN" = false ]; then
    ARCH_NAME=$(uname -m)
    [[ "$ARCH_NAME" == "x86_64" ]] && YQ_BIN="yq_linux_amd64" || YQ_BIN="yq_linux_arm64"
    sudo wget -q "https://github.com/mikefarah/yq/releases/latest/download/${YQ_BIN}" -O /usr/local/bin/yq || true
    sudo chmod +x /usr/local/bin/yq 2>/dev/null || true
fi

if ! command -v starship &>/dev/null && [ "$DRY_RUN" = false ]; then
    curl -fsSL https://starship.rs/install.sh | sh -s -- -y || true
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
if [ -d /opt/maven ]; then
    zshrc_add 'export M2_HOME=/opt/maven'
    zshrc_add 'export PATH="$M2_HOME/bin:$PATH"'
fi
zshrc_add 'eval "$(starship init zsh)"'

# ==============================================================================
# 3. GUI APPLICATIONS
# ==============================================================================

step "Installing VS Code..."
if ! command -v code &>/dev/null && [ "$DRY_RUN" = false ]; then
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
fi

# ==============================================================================
# 4. ENVIRONMENT CONFIGURATION
# ==============================================================================

step "Configuring Java environment..."
if command -v java &>/dev/null; then
    JAVA_BIN=$(readlink -f "$(which java)")
    JAVA_HOME_PATH=$(dirname "$(dirname "$JAVA_BIN")")
    zshrc_add "export JAVA_HOME=${JAVA_HOME_PATH}"
fi
zshrc_add 'export PATH="$JAVA_HOME/bin:$PATH"'

step "Initializing Git LFS..."
run_cmd sudo git lfs install --system

# ==============================================================================
# 5. OPTIONAL SSH SERVER
# ==============================================================================

if [ "$NON_INTERACTIVE" = true ]; then
    ssh_response="n"
else
    read -rp "Do you want to install and configure SSH server (password authentication)? [y/N]: " ssh_response || ssh_response="n"
fi

if [[ "$ssh_response" =~ ^[Yy]$ && "$DRY_RUN" = false ]]; then
    step "Setting up SSH server..."
    sudo dnf -y install openssh-server
    SSHD_CONFIG="/etc/ssh/sshd_config"
    sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG"
    sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/'               "$SSHD_CONFIG"
    sudo sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/'    "$SSHD_CONFIG"
    if command -v firewall-cmd &>/dev/null && sudo firewall-cmd --state 2>/dev/null | grep -q running; then
        sudo firewall-cmd --permanent --add-service=ssh
        sudo firewall-cmd --reload
    fi
    sudo systemctl enable sshd
    sudo systemctl restart sshd
fi

# ==============================================================================
# 6. TAILSCALE (OPTIONAL)
# ==============================================================================

if [ "$NON_INTERACTIVE" = true ]; then
    ts_response="n"
else
    read -rp "Do you want to install and configure Tailscale? [y/N]: " ts_response || ts_response="n"
fi

if [[ "$ts_response" =~ ^[Yy]$ && "$DRY_RUN" = false ]]; then
    step "Installing and configuring Tailscale..."
    curl -fsSL https://tailscale.com/install.sh | sh
    sudo systemctl enable tailscaled
    sudo systemctl start tailscaled
    sudo tailscale up --ssh --accept-routes --accept-dns || true
fi

# ==============================================================================
# 7. VS CODE TUNNEL
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
        sudo systemctl mask sleep.target suspend.target hibernate.target hybrid-sleep.target
    fi
fi

# ==============================================================================
# 8. STATE MANIFEST & VERIFICATION
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
  "platform": "RHEL/Fedora",
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
