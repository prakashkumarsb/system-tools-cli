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
# CLI FLAGS, LOGGING & SUDO KEEP-ALIVE
# ==============================================================================

init_cli_flags "$@"
init_logging "mac-setup"
init_sudo_keepalive

ask_to_install() {
    local app_name=$1
    if [ "$NON_INTERACTIVE" = true ]; then
        return 0
    fi
    read -rp "  Install $app_name? [y/N]: " response || response="n"
    [[ "$response" =~ ^[Yy]$ ]]
}

# ==============================================================================
# 1. BASE CLI TOOLS & PACKAGES
# ==============================================================================

step "Checking Homebrew..."
if ! command -v brew &> /dev/null; then
    run_cmd /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    if [ "$DRY_RUN" = false ]; then
        eval "$(/opt/homebrew/bin/brew shellenv 2>/dev/null || /usr/local/bin/brew shellenv 2>/dev/null || true)"
    fi
else
    info "Homebrew already installed"
fi

step "Checking Oh My Zsh..."
if [ ! -d "$HOME/.oh-my-zsh" ]; then
    if [ "$DRY_RUN" = true ]; then
        info "[DRY-RUN] Would install Oh My Zsh"
    else
        sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)" "" --unattended
    fi
else
    info "Oh My Zsh already installed"
fi

step "Updating Homebrew..."
run_cmd brew update

formulas=(
    bash bat btop coreutils docker docker-compose gh git git-lfs
    htop ipinfo-cli jq maven node parallel pipx python3
    ripgrep shellcheck sshpass starship watch wget yq zsh-autosuggestions
    zsh-history-substring-search zsh-syntax-highlighting rsync openjdk@21
)

step "Installing CLI tools (${#formulas[@]} formulas)..."
installed_formulas=$(brew list --formula -1 2>/dev/null || true)
to_install=()
for formula in "${formulas[@]}"; do
    if echo "$installed_formulas" | grep -qx "$formula"; then
        info "$formula already installed"
    else
        to_install+=("$formula")
    fi
done

if [ ${#to_install[@]} -gt 0 ]; then
    info "Installing ${#to_install[@]} missing formulas: ${to_install[*]}"
    run_cmd brew install "${to_install[@]}"
fi

# ==============================================================================
# 2. GUI APPLICATIONS (CASKS)
# ==============================================================================

step "Installing core GUI applications..."
core_casks=(iterm2 visual-studio-code orbstack)

cask_installed() {
    brew list --cask "$1" &>/dev/null && return 0
    local app_path
    app_path="$(brew info --cask "$1" 2>/dev/null | grep -o '/Applications/.*\.app' | head -1)"
    [[ -n "$app_path" && -d "$app_path" ]]
}

for cask in "${core_casks[@]}"; do
    if cask_installed "$cask"; then
        if ask_to_install "$cask (already installed, reinstall?)"; then
            run_cmd brew reinstall --cask --force "$cask"
        else
            info "Skipping $cask"
        fi
    else
        run_cmd brew install --cask "$cask"
    fi
done
run_cmd curl -L https://iterm2.com/shell_integration/zsh -o ~/.iterm2_shell_integration.zsh

optional_apps=(
    maccy
    stats
    jiggler
    lulu
    appcleaner
    microsoft-teams
    postman
    whatsapp
    google-chrome
    brave-browser
    microsoft-edge
    ollama-app
)

step "Optional applications"
echo "Available:"
for app in "${optional_apps[@]}"; do echo "  - $app"; done
echo ""

if [ "$NON_INTERACTIVE" = true ]; then
    bulk_response="y"
else
    read -rp "Install ALL optional apps at once? [y/N]: " bulk_response || bulk_response="n"
fi

if [[ "$bulk_response" =~ ^[Yy]$ ]]; then
    info "Installing all optional applications..."
    run_cmd brew install --cask "${optional_apps[@]}"
else
    read -rp "Would you like to pick specific apps to install? [y/N]: " pick_response || pick_response="n"
    if [[ "$pick_response" =~ ^[Yy]$ ]]; then
        for app in "${optional_apps[@]}"; do
            if ask_to_install "$app"; then
                run_cmd brew install --cask "$app" || true
            fi
        done
    else
        warn "Skipping all optional applications."
    fi
fi

# ==============================================================================
# 2b. LICENSED SOFTWARE (require separate purchase/license)
# ==============================================================================

licensed_apps=(
    cleanmymac
    little-snitch
    folder-preview-pro
    "TheBoredTeam/boring-notch/boring-notch"
    intellij-idea
    purevpn
    "4k-video-downloader+"
)

if [ "$NON_INTERACTIVE" = true ]; then
    lic_response="n"
else
    read -rp "Do you want to install licensed software? (require separate purchase) [y/N]: " lic_response || lic_response="n"
fi

if [[ "$lic_response" =~ ^[Yy]$ ]]; then
    step "Licensed software"
    echo "Available (these require a separate license/purchase):"
    for app in "${licensed_apps[@]}"; do echo "  - $app"; done
    echo ""

    read -rp "Install ALL licensed apps at once? [y/N]: " lic_bulk_response || lic_bulk_response="n"

    if [[ "$lic_bulk_response" =~ ^[Yy]$ ]]; then
        info "Installing all licensed applications..."
        run_cmd brew install --cask "${licensed_apps[@]}"
    else
        read -rp "Would you like to pick specific licensed apps to install? [y/N]: " lic_pick_response || lic_pick_response="n"
        if [[ "$lic_pick_response" =~ ^[Yy]$ ]]; then
            for app in "${licensed_apps[@]}"; do
                if ask_to_install "$app"; then
                    run_cmd brew install --cask "$app" || true
                fi
            done
        else
            warn "Skipping all licensed applications."
        fi
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
zshrc_add 'eval "$(starship init zsh)"'

if [ "$DRY_RUN" = false ] && grep -q "plugins=(git)" ~/.zshrc 2>/dev/null; then
    sed -i '' 's/plugins=(git)/plugins=()/g' ~/.zshrc
fi

step "Linking OpenJDK 21..."

run_cmd sudo ln -sfn /opt/homebrew/opt/openjdk@21/libexec/openjdk.jdk /Library/Java/JavaVirtualMachines/openjdk-21.jdk
zshrc_add 'export PATH="/opt/homebrew/opt/openjdk@21/bin:$PATH"'
zshrc_add 'export JAVA_HOME=$(/usr/libexec/java_home -v 21)'
zshrc_add 'export CPPFLAGS="-I/opt/homebrew/opt/openjdk@21/include"'

# ==============================================================================
# 4. SYSTEM SERVICES
# ==============================================================================

step "Initializing Git LFS..."
run_cmd sudo git lfs install --system

# ==============================================================================
# 5. OPTIONAL SSH SERVER
# ==============================================================================

if [ "$NON_INTERACTIVE" = true ]; then
    ssh_response="n"
else
    read -rp "Do you want to enable SSH server (Remote Login) with password authentication? [y/N]: " ssh_response || ssh_response="n"
fi

if [[ "$ssh_response" =~ ^[Yy]$ ]]; then
    step "Configuring SSH server (Remote Login)..."
    run_cmd sudo systemsetup -setremotelogin on
    SSHD_CONFIG="/etc/ssh/sshd_config"
    if [ "$DRY_RUN" = false ]; then
        [ -f "${SSHD_CONFIG}.bak" ] || sudo cp "$SSHD_CONFIG" "${SSHD_CONFIG}.bak"
        sudo sed -i '' 's/^#*PasswordAuthentication.*/PasswordAuthentication yes/' "$SSHD_CONFIG"
        sudo sed -i '' 's/^#*PermitRootLogin.*/PermitRootLogin no/'               "$SSHD_CONFIG"
        sudo sed -i '' 's/^#*PubkeyAuthentication.*/PubkeyAuthentication yes/'    "$SSHD_CONFIG"
        grep -q "^PasswordAuthentication" "$SSHD_CONFIG" || echo "PasswordAuthentication yes" | sudo tee -a "$SSHD_CONFIG" > /dev/null
        grep -q "^PermitRootLogin"        "$SSHD_CONFIG" || echo "PermitRootLogin no"           | sudo tee -a "$SSHD_CONFIG" > /dev/null
        grep -q "^PubkeyAuthentication"   "$SSHD_CONFIG" || echo "PubkeyAuthentication yes"     | sudo tee -a "$SSHD_CONFIG" > /dev/null
        sudo launchctl unload /System/Library/LaunchDaemons/ssh.plist 2>/dev/null || true
        sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist
    fi
    info "SSH server enabled"
fi

# ==============================================================================
# 6. TAILSCALE (OPTIONAL)
# ==============================================================================

if [ "$NON_INTERACTIVE" = true ]; then
    ts_response="n"
else
    read -rp "Do you want to install and configure Tailscale? [y/N]: " ts_response || ts_response="n"
fi

if [[ "$ts_response" =~ ^[Yy]$ ]]; then
    step "Installing and configuring Tailscale..."
    run_cmd brew install tailscale
    if [ "$DRY_RUN" = false ]; then
        sudo /opt/homebrew/bin/tailscaled install-system-daemon
        sudo chown root:wheel /Library/LaunchDaemons/com.tailscale.tailscaled.plist
        sudo chmod 644 /Library/LaunchDaemons/com.tailscale.tailscaled.plist
        sudo launchctl bootout system /Library/LaunchDaemons/com.tailscale.tailscaled.plist 2>/dev/null || true
        sudo launchctl bootstrap system /Library/LaunchDaemons/com.tailscale.tailscaled.plist
        sudo /usr/libexec/ApplicationFirewall/socketfilterfw --add /opt/homebrew/bin/tailscaled
        sudo /usr/libexec/ApplicationFirewall/socketfilterfw --unblockapp /opt/homebrew/bin/tailscaled
        retries=15
        while ! sudo tailscale status &>/dev/null && [ "$retries" -gt 0 ]; do
            sleep 1
            retries=$((retries - 1))
        done
        sudo tailscale up --ssh --accept-routes --accept-dns
    fi
fi

# ==============================================================================
# 7. VS CODE TUNNEL
# ==============================================================================

if [ "$NON_INTERACTIVE" = true ]; then
    vst_response="n"
else
    read -rp "Do you want to enable VS Code Tunnel as a service? [y/N]: " vst_response || vst_response="n"
fi

if [[ "$vst_response" =~ ^[Yy]$ ]]; then
    step "Setting up VS Code Tunnel as a service..."
    CODE_CMD="/opt/homebrew/bin/code"
    [ -x "$CODE_CMD" ] || CODE_CMD="$(command -v code 2>/dev/null || true)"
    if [ -n "$CODE_CMD" ]; then
        default_name=$(hostname -s)
        tunnel_name="${default_name}"
        if [ "$NON_INTERACTIVE" = false ]; then
            read -rp "  Tunnel name [$default_name]: " input_name || input_name=""
            tunnel_name="${input_name:-$default_name}"
        fi
        run_cmd "$CODE_CMD" tunnel service install --accept-server-license-terms --name "$tunnel_name"
        run_cmd sudo pmset -a disablesleep 1
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
        FORMULAS_JSON=$(printf '%s\n' "${formulas[@]}" | jq -R . | jq -s .)
        CASKS_JSON=$(printf '%s\n' "${core_casks[@]}" | jq -R . | jq -s .)
    else
        FORMULAS_JSON="[]"
        CASKS_JSON="[]"
    fi
    cat <<EOF > "$MANIFEST_DIR/manifest.json"
{
  "platform": "macOS",
  "timestamp": "$(date -u +"%Y-%m-%dT%H:%M:%SZ")",
  "formulas": ${FORMULAS_JSON},
  "core_casks": ${CASKS_JSON}
}
EOF
fi
info "State written to $MANIFEST_DIR/manifest.json"

step "Verifying..."
if [ "$DRY_RUN" = false ] && command -v java &>/dev/null; then
    java -version 2>&1 | head -1 || true
fi
info "Setup complete! Open a new terminal or run: exec zsh"
