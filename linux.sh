#!/bin/bash
set -euo pipefail

# ==============================================================================
# HELPERS
# ==============================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
step()  { echo -e "\n${GREEN}==>${NC} $1"; }

ask_to_install() {
    local app_name=$1
    read -rp "  Install $app_name? [y/N]: " response
    [[ "$response" =~ ^[Yy]$ ]]
}

zshrc_add() {
    grep -qF "$1" ~/.zshrc 2>/dev/null || echo "$1" >> ~/.zshrc
}

# Ask for sudo once and keep it alive
sudo -v
while true; do sudo -n true; sleep 55; kill -0 "$$" || exit; done 2>/dev/null &

# ==============================================================================
# 1. BASE CLI TOOLS & PACKAGES
# ==============================================================================

step "Updating package lists..."
sudo apt-get update

step "Installing CLI tools..."
packages=(
    bash bat coreutils curl
    docker.io docker-compose-plugin
    git git-lfs gh htop
    jq maven nodejs npm
    openjdk-21-jdk pipx python3 python3-pip
    ripgrep rsync shellcheck sshpass
    watch wget wl-clipboard
    zsh
)
sudo apt-get install -y "${packages[@]}"

# ==============================================================================
# 2. ZSH & OH MY ZSH
# ==============================================================================

step "Checking Oh My Zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
    info "Oh My Zsh already installed"
fi

# Set zsh as default shell
if [ "$SHELL" != "$(which zsh)" ]; then
    chsh -s "$(which zsh)"
    info "Default shell changed to zsh"
fi

# Install zsh plugins
ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

if [ ! -d "$ZSH_CUSTOM/plugins/zsh-autosuggestions" ]; then
    git clone https://github.com/zsh-users/zsh-autosuggestions "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
fi
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting" ]; then
    git clone https://github.com/zsh-users/zsh-syntax-highlighting "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"
fi
if [ ! -d "$ZSH_CUSTOM/plugins/zsh-history-substring-search" ]; then
    git clone https://github.com/zsh-users/zsh-history-substring-search "$ZSH_CUSTOM/plugins/zsh-history-substring-search"
fi

zshrc_add 'source $ZSH_CUSTOM/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh'
zshrc_add 'source $ZSH_CUSTOM/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh'
zshrc_add 'source $ZSH_CUSTOM/plugins/zsh-history-substring-search/zsh-history-substring-search.zsh'

# ==============================================================================
# 3. GUI APPLICATIONS
# ==============================================================================

step "Installing VS Code..."
if ! command -v code &>/dev/null; then
    curl -fsSL https://packages.microsoft.com/keys/microsoft.asc | sudo gpg --dearmor -o /usr/share/keyrings/packages.microsoft.gpg
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/packages.microsoft.gpg] https://packages.microsoft.com/repos/code stable main" | sudo tee /etc/apt/sources.list.d/vscode.list
    sudo apt-get update
    sudo apt-get install -y code
else
    info "VS Code already installed"
fi

# ==============================================================================
# 4. ENVIRONMENT CONFIGURATION
# ==============================================================================

step "Configuring Java environment..."
zshrc_add 'export JAVA_HOME=/usr/lib/jvm/java-21-openjdk-amd64'
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

    # Enable password authentication
    SSHD_CONFIG="/etc/ssh/sshd_config"
    sudo sed -i 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG"
    sudo sed -i 's/^#*PermitRootLogin.*/PermitRootLogin no/' "$SSHD_CONFIG"
    sudo sed -i 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/' "$SSHD_CONFIG"

    # Append settings if they weren't already present
    grep -q "^PasswordAuthentication" "$SSHD_CONFIG" || echo "PasswordAuthentication yes" | sudo tee -a "$SSHD_CONFIG" > /dev/null
    grep -q "^PermitRootLogin" "$SSHD_CONFIG"       || echo "PermitRootLogin no"           | sudo tee -a "$SSHD_CONFIG" > /dev/null
    grep -q "^PubkeyAuthentication" "$SSHD_CONFIG"  || echo "PubkeyAuthentication yes"     | sudo tee -a "$SSHD_CONFIG" > /dev/null

    # Open firewall port 22 if ufw is active
    if command -v ufw &>/dev/null && sudo ufw status | grep -q "Status: active"; then
        sudo ufw allow ssh
        info "Firewall: port 22 allowed"
    fi

    # Enable and start sshd (systemd or sysVinit)
    if pidof systemd &>/dev/null; then
        sudo systemctl enable ssh
        sudo systemctl restart ssh
    else
        sudo update-rc.d ssh defaults
        sudo service ssh restart
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
    if pidof systemd &>/dev/null; then
        sudo systemctl enable tailscaled
        sudo systemctl start tailscaled
    else
        # sysVinit: create init script for boot persistence
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

        # Prevent sleep so the tunnel stays reachable
        if pidof systemd &>/dev/null; then
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
