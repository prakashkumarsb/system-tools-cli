#!/bin/bash
set -euo pipefail

# ==============================================================================
# HELPERS
# ==============================================================================

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

info()  { echo -e "${GREEN}[✓]${NC} $1"; }
warn()  { echo -e "${YELLOW}[!]${NC} $1"; }
step()  { echo -e "\n${GREEN}==>${NC} $1"; }

ask_to_install() {
    local app_name=$1
    read -rp "  Install $app_name? [y/N]: " response
    [[ "$response" =~ ^[Yy]$ ]]
}

# Append a line to ~/.zshrc only if it's not already present
zshrc_add() {
    grep -qF "$1" ~/.zshrc 2>/dev/null || echo "$1" >> ~/.zshrc
}

# ==============================================================================
# SUDO KEEP-ALIVE
# ==============================================================================

sudo -v
while true; do sudo -n true; sleep 55; kill -0 "$$" || exit; done 2>/dev/null &

# ==============================================================================
# 1. BASE CLI TOOLS & PACKAGES
# ==============================================================================

step "Checking Homebrew..."
if ! command -v brew &> /dev/null; then
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    eval "$(/opt/homebrew/bin/brew shellenv)"
else
    info "Homebrew already installed"
fi

step "Checking Oh My Zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
else
    info "Oh My Zsh already installed"
fi

step "Updating Homebrew..."
brew update

formulas=(
    bash coreutils docker docker-compose git git-lfs
    ice ipinfo-cli maven node orbstack pipx python3
    shellcheck sshpass watch wget zsh-autosuggestions
    zsh-history-substring-search zsh-syntax-highlighting rsync openjdk@21
)

step "Installing CLI tools (${#formulas[@]} formulas)..."
for formula in "${formulas[@]}"; do
    if brew list "$formula" &>/dev/null; then
        info "$formula already installed"
    else
        brew install "$formula"
    fi
done

# ==============================================================================
# 2. GUI APPLICATIONS (CASKS)
# ==============================================================================

step "Installing core GUI applications..."
core_casks=(iterm2 visual-studio-code maccy stats jiggler lulu)

# Check if a cask is already present (via Homebrew or manually installed .app)
cask_installed() {
    brew list --cask "$1" &>/dev/null && return 0
    local app_path
    app_path="$(brew info --cask "$1" 2>/dev/null | grep -o '/Applications/.*\.app' | head -1)"
    [[ -n "$app_path" && -d "$app_path" ]]
}

for cask in "${core_casks[@]}"; do
    if cask_installed "$cask"; then
        if ask_to_install "$cask (already installed, reinstall?)"; then
            brew reinstall --cask --force "$cask"
        else
            info "Skipping $cask"
        fi
    else
        brew install --cask "$cask"
    fi
done
curl -L https://iterm2.com/shell_integration/zsh -o ~/.iterm2_shell_integration.zsh

optional_apps=(
    appcleaner
    cleanmymac
    little-snitch
    folder-preview-pro
    "TheBoredTeam/boring-notch/boring-notch"
    microsoft-teams
    intellij-idea
    postman
    purevpn
    whatsapp
    "4k-video-downloader+"
)

step "Optional applications"
echo "Available:"
for app in "${optional_apps[@]}"; do echo "  - $app"; done
echo ""

read -rp "Install ALL optional apps at once? [y/N]: " bulk_response

if [[ "$bulk_response" =~ ^[Yy]$ ]]; then
    info "Installing all optional applications..."
    brew install --cask "${optional_apps[@]}"
else
    read -rp "Would you like to pick specific apps to install? [y/N]: " pick_response
    if [[ "$pick_response" =~ ^[Yy]$ ]]; then
        for app in "${optional_apps[@]}"; do
            ask_to_install "$app" && brew install --cask "$app" || true
        done
    else
        warn "Skipping all optional applications."
    fi
fi

# ==============================================================================
# 3. ENVIRONMENT CONFIGURATION
# ==============================================================================

step "Configuring Zsh plugins and environment..."

zshrc_add 'source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh'
zshrc_add 'source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh'
zshrc_add 'source /opt/homebrew/share/zsh-history-substring-search/zsh-history-substring-search.zsh'
zshrc_add 'export ZSH_HIGHLIGHT_HIGHLIGHTERS_DIR=/opt/homebrew/share/zsh-syntax-highlighting/highlighters'

# Remove default OMZ git plugin (we source plugins directly)
if grep -q "plugins=(git)" ~/.zshrc; then
    sed -i '' 's/plugins=(git)/plugins=()/g' ~/.zshrc
fi

# OpenJDK 21
step "Linking OpenJDK 21..."

sudo ln -sfn /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-21.jdk
zshrc_add 'export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"'
zshrc_add 'export JAVA_HOME=$(/usr/libexec/java_home)'
zshrc_add 'export CPPFLAGS="-I/opt/homebrew/opt/openjdk@21/include"'

# ==============================================================================
# 4. SYSTEM SERVICES
# ==============================================================================

step "Initializing Git LFS..."
sudo git lfs install --system

# ==============================================================================
# 5. TAILSCALE (OPTIONAL)
# ==============================================================================

read -rp "Do you want to install and configure Tailscale? [y/N]: " ts_response
if [[ "$ts_response" =~ ^[Yy]$ ]]; then
    step "Installing and configuring Tailscale..."
    brew install tailscale
    sudo tailscaled install-system-daemon
    sudo chown root:wheel /Library/LaunchDaemons/com.tailscale.tailscaled.plist
    sudo chmod 644 /Library/LaunchDaemons/com.tailscale.tailscaled.plist
    sudo launchctl bootout system /Library/LaunchDaemons/com.tailscale.tailscaled.plist 2>/dev/null || true
    sudo launchctl bootstrap system /Library/LaunchDaemons/com.tailscale.tailscaled.plist
    # Allow tailscaled through the macOS firewall
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /opt/homebrew/bin/tailscaled
    sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp /opt/homebrew/bin/tailscaled
    # Wait for daemon to be ready
    info "Waiting for Tailscale daemon to start..."
    until sudo tailscale status &>/dev/null; do sleep 1; done
    sudo tailscale up --ssh --accept-routes --accept-dns
fi

# ==============================================================================
# 6. VS CODE TUNNEL (runs last so user can authenticate interactively)
# ==============================================================================

read -rp "Do you want to enable VS Code Tunnel as a service? [y/N]: " vst_response
if [[ "$vst_response" =~ ^[Yy]$ ]]; then
    step "Setting up VS Code Tunnel as a service..."
    CODE_CMD="/opt/homebrew/bin/code"
    if [ ! -x "$CODE_CMD" ]; then
        CODE_CMD="/Applications/Visual Studio Code.app/Contents/Resources/app/bin/code"
    fi
    if [ ! -x "$CODE_CMD" ]; then
        CODE_CMD="$(command -v code 2>/dev/null || true)"
    fi
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
        sudo pmset -a disablesleep 1
        info "System sleep disabled (pmset disablesleep 1) to keep tunnel reachable"
    fi
fi

# ==============================================================================
# 7. VERIFICATION
# ==============================================================================

step "Verifying..."
java -version 2>&1 | head -1
info "Setup complete! Open a new terminal or run: exec zsh"

# FileVault authenticated restart (optional — will reboot the machine)
read -rp "Run FileVault authenticated restart now? This will REBOOT. [y/N]: " fv_response
if [[ "$fv_response" =~ ^[Yy]$ ]]; then
    sudo fdesetup authrestart
fi
