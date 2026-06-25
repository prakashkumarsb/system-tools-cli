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
echo -e "${RED}║  WARNING: This will uninstall everything from mac.sh    ║${NC}"
echo -e "${RED}╚══════════════════════════════════════════════════════════╝${NC}"
echo ""
read -rp "Are you sure you want to proceed? [y/N]: " confirm
[[ "$confirm" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 0; }

# Ask for sudo once and keep it alive for the duration of the script
sudo -v
while true; do sudo -n true; sleep 55; kill -0 "$$" || exit; done 2>/dev/null &

# ==============================================================================
# 1. REMOTE ACCESS
# ==============================================================================

step "Removing VS Code Tunnel service..."
CODE_CMD="/opt/homebrew/bin/code"
if [ ! -x "$CODE_CMD" ]; then
    CODE_CMD="$(command -v code 2>/dev/null || true)"
fi
if [ -n "$CODE_CMD" ]; then
    "$CODE_CMD" tunnel service uninstall 2>/dev/null || true
    info "VS Code Tunnel service removed"
else
    info "VS Code CLI not found, skipping tunnel service removal"
fi
sudo pmset -a disablesleep 0 2>/dev/null || true
info "System sleep re-enabled"

# ==============================================================================
# 2. TAILSCALE
# ==============================================================================

step "Removing Tailscale..."
if command -v tailscale &> /dev/null; then
    sudo tailscale down 2>/dev/null || true
    sudo launchctl bootout system /Library/LaunchDaemons/com.tailscale.tailscaled.plist 2>/dev/null || true
    sudo rm -f /Library/LaunchDaemons/com.tailscale.tailscaled.plist
    brew uninstall tailscale 2>/dev/null || true
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
# 4. OPENJDK SYMLINK
# ==============================================================================

step "Removing OpenJDK 21 symlink..."
sudo rm -f /Library/Java/JavaVirtualMachines/openjdk-21.jdk
info "OpenJDK symlink removed"

# ==============================================================================
# 5. ZSHRC CLEANUP
# ==============================================================================

step "Cleaning .zshrc entries..."
lines_to_remove=(
    'source /opt/homebrew/share/zsh-autosuggestions/zsh-autosuggestions.zsh'
    'source /opt/homebrew/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh'
    'source /opt/homebrew/share/zsh-history-substring-search/zsh-history-substring-search.zsh'
    'export ZSH_HIGHLIGHT_HIGHLIGHTERS_DIR=/opt/homebrew/share/zsh-syntax-highlighting/highlighters'
    'export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"'
    'export JAVA_HOME=$(/usr/libexec/java_home)'
    'export CPPFLAGS="-I/opt/homebrew/opt/openjdk@21/include"'
)

if [ -f ~/.zshrc ]; then
    for line in "${lines_to_remove[@]}"; do
        sed -i '' "\|${line}|d" ~/.zshrc
    done
    info ".zshrc entries removed"
fi

# ==============================================================================
# 6. GUI APPLICATIONS (CASKS)
# ==============================================================================

step "Uninstalling GUI applications..."

casks=(
    iterm2 visual-studio-code maccy stats jiggler lulu
    appcleaner cleanmymac little-snitch folder-preview-pro
    boring-notch microsoft-teams intellij-idea
    postman purevpn whatsapp "4k-video-downloader+"
)

for cask in "${casks[@]}"; do
    brew uninstall --cask "$cask" 2>/dev/null && info "Removed $cask" || true
done

# ==============================================================================
# 6b. APP CACHE, LOGS & DATA CLEANUP
# ==============================================================================

step "Clearing app caches, logs, and support files..."

# Bundle IDs / folder names for installed apps
app_identifiers=(
    "com.googlecode.iterm2"
    "com.microsoft.VSCode"
    "org.p0deje.Maccy"
    "eu.exelban.Stats"
    "com.sticktron.Jiggler"
    "FreeMacSoft.AppCleaner"
    "com.macpaw.CleanMyMac*"
    "at.obdev.LittleSnitch*"
    "com.quicklookplugins.FolderPreviewPro"
    "com.jordanbaird.Ice"
    "TheBoredTeam.boring-notch"
    "com.microsoft.teams*"
    "com.jetbrains.intellij*"
    "com.postmanlabs.mac"
    "com.purevpn.PureVPN"
    "net.whatsapp.WhatsApp*"
    "com.4kdownload.*"
    "com.tailscale.*"
    "io.orbstack.*"
    "com.docker.*"
    "com.objective-see.lulu*"
)

# Directories where apps leave data (user-level)
search_dirs=(
    "$HOME/Library/Caches"
    "$HOME/Library/Logs"
    "$HOME/Library/Application Support"
    "$HOME/Library/Preferences"
    "$HOME/Library/Saved Application State"
    "$HOME/Library/HTTPStorages"
    "$HOME/Library/WebKit"
)

for dir in "${search_dirs[@]}"; do
    [ -d "$dir" ] || continue
    for id in "${app_identifiers[@]}"; do
        # Use find with wildcard-safe matching
        find "$dir" -maxdepth 1 -name "$id" -exec rm -rf {} + 2>/dev/null || true
    done
done

# System-level directories (/Library)
system_search_dirs=(
    "/Library/Caches"
    "/Library/Logs"
    "/Library/Application Support"
    "/Library/Preferences"
)

for dir in "${system_search_dirs[@]}"; do
    [ -d "$dir" ] || continue
    for id in "${app_identifiers[@]}"; do
        sudo find "$dir" -maxdepth 1 -name "$id" -exec rm -rf {} + 2>/dev/null || true
    done
done

# /var/log app-specific logs
for id in "${app_identifiers[@]}"; do
    sudo find /var/log -maxdepth 1 -name "$id" -exec rm -rf {} + 2>/dev/null || true
done
sudo rm -rf /var/log/tailscale* 2>/dev/null || true
sudo rm -rf /var/log/orbstack* 2>/dev/null || true
sudo rm -rf /var/log/docker* 2>/dev/null || true

# System-level app support leftovers
sudo rm -rf "/Library/Application Support/Tailscale" 2>/dev/null || true
sudo rm -rf "/Library/Application Support/OrbStack" 2>/dev/null || true
sudo rm -rf "/Library/Application Support/LittleSnitch" 2>/dev/null || true
sudo rm -rf "/Library/Application Support/CleanMyMac"* 2>/dev/null || true

# Additional known paths
rm -rf "$HOME/Library/Application Support/iTerm2" 2>/dev/null || true
rm -rf "$HOME/Library/Application Support/Code" 2>/dev/null || true
rm -rf "$HOME/.vscode" 2>/dev/null || true
rm -rf "$HOME/Library/Application Support/Postman" 2>/dev/null || true
rm -rf "$HOME/Library/Application Support/JetBrains" 2>/dev/null || true
rm -rf "$HOME/.docker" 2>/dev/null || true
rm -rf "$HOME/.orbstack" 2>/dev/null || true
rm -rf "$HOME/.node_repl_history" 2>/dev/null || true
rm -rf "$HOME/.npm" 2>/dev/null || true
rm -rf "$HOME/.python_history" 2>/dev/null || true

info "App caches, logs, and support files cleared"

# ==============================================================================
# 7. CLI FORMULAS
# ==============================================================================

step "Uninstalling CLI formulas..."

formulas=(
    bash coreutils docker docker-compose git-lfs
    ice ipinfo-cli maven node orbstack pipx python3
    shellcheck sshpass watch wget zsh-autosuggestions
    zsh-history-substring-search zsh-syntax-highlighting rsync openjdk@21
)

for formula in "${formulas[@]}"; do
    brew uninstall "$formula" 2>/dev/null && info "Removed $formula" || true
done

# ==============================================================================
# 8. OH MY ZSH
# ==============================================================================

step "Removing Oh My Zsh..."
if [ -d "$HOME/.oh-my-zsh" ]; then
    rm -rf "$HOME/.oh-my-zsh"
    info "Oh My Zsh removed"
else
    info "Oh My Zsh not found, skipping"
fi

# ==============================================================================
# 9. HOMEBREW (OPTIONAL)
# ==============================================================================

echo ""
read -rp "Also uninstall Homebrew itself? [y/N]: " remove_brew
if [[ "$remove_brew" =~ ^[Yy]$ ]]; then
    step "Uninstalling Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/uninstall.sh)" -- --force
    sudo rm -rf /opt/homebrew
    info "Homebrew removed"
fi

echo ""
info "Uninstall complete. Open a new terminal for changes to take effect."
