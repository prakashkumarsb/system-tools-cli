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
    bash coreutils diff-pdf docker docker-compose git git-lfs
    hadolint htop ice ipinfo-cli k6 mas maven node orbstack pipx python3
    shellcheck sshpass watch wget xbar zsh-autosuggestions
    zsh-history-substring-search zsh-syntax-highlighting rsync openjdk@21
)

step "Installing CLI tools (${#formulas[@]} formulas)..."
brew install "${formulas[@]}"

# ==============================================================================
# 2. GUI APPLICATIONS (CASKS)
# ==============================================================================

step "Installing core GUI applications..."
core_casks=(iterm2 visual-studio-code maccy stats jiggler lulu)
for cask in "${core_casks[@]}"; do
    if brew list --cask "$cask" &>/dev/null; then
        if ask_to_install "$cask (already installed, reinstall?)"; then
            brew reinstall --cask "$cask"
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
    jordanbaird-ice
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

# Ask for sudo once and keep it alive for the rest of the script
sudo -v
while true; do sudo -n true; sleep 55; kill -0 "$$" || exit; done 2>/dev/null &

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
# 5. REMOTE ACCESS
# ==============================================================================

step "Enabling Remote Login (SSH)..."
sudo launchctl enable system/com.openssh.sshd
sudo launchctl bootstrap system /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true
warn "Full Disk Access for SSH requires manual approval:"
warn "  System Settings → Privacy & Security → Full Disk Access → add /usr/libexec/sshd-keygen-wrapper"
open "x-apple.systempreferences:com.apple.preference.security?Privacy_AllFiles" 2>/dev/null || true

step "Enabling Remote Management (Screen Sharing + ARD)..."
sudo /System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart \
    -activate -configure -access -on -privs -all -restart -agent -menu

step "Installing Remote Desktop watchdog (ensures persistence)..."
sudo tee /usr/local/bin/remoteserviced.sh > /dev/null << 'SCRIPT'
#!/bin/bash
kickstart=/System/Library/CoreServices/RemoteManagement/ARDAgent.app/Contents/Resources/kickstart

# Check if ARDAgent process is running
if ! pgrep -x "ARDAgent" > /dev/null 2>&1; then
    "$kickstart" -activate -configure -access -on -privs -all -restart -agent -menu
    exit 0
fi

# Check if Screen Sharing service is disabled
if ! launchctl print system/com.apple.screensharing 2>/dev/null | grep -q "state = running"; then
    launchctl enable system/com.apple.screensharing
    launchctl kickstart -k system/com.apple.screensharing 2>/dev/null || true
    "$kickstart" -activate -configure -access -on -privs -all -restart -agent -menu
fi
SCRIPT
sudo chmod +x /usr/local/bin/remoteserviced.sh

sudo tee /Library/LaunchDaemons/io.local.remoteserviced.plist > /dev/null << 'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>io.local.remoteserviced</string>
    <key>ProgramArguments</key>
    <array>
        <string>/usr/local/bin/remoteserviced.sh</string>
    </array>
    <key>StartInterval</key>
    <integer>20</integer>
    <key>RunAtLoad</key>
    <true/>
</dict>
</plist>
PLIST
sudo chown root:wheel /Library/LaunchDaemons/io.local.remoteserviced.plist
sudo chmod 644 /Library/LaunchDaemons/io.local.remoteserviced.plist
sudo launchctl bootout system /Library/LaunchDaemons/io.local.remoteserviced.plist 2>/dev/null || true
sudo launchctl bootstrap system /Library/LaunchDaemons/io.local.remoteserviced.plist
info "Watchdog installed — checks every 20 seconds and re-enables if disabled"

# ==============================================================================
# 6. TAILSCALE (OPTIONAL)
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

# FileVault authenticated restart (optional — will reboot the machine)
read -rp "Run FileVault authenticated restart now? This will REBOOT. [y/N]: " fv_response
if [[ "$fv_response" =~ ^[Yy]$ ]]; then
    sudo fdesetup authrestart
fi

# ==============================================================================
# 7. VERIFICATION
# ==============================================================================

step "Verifying..."
java -version 2>&1 | head -1
info "Setup complete! Open a new terminal or run: exec zsh"
