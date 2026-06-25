# Machine Setup Scripts

Automated provisioning scripts for setting up development machines from scratch. Currently supports macOS and Linux (MX Linux/Debian).

## Supported Platforms

| Platform | Script | Status |
|----------|--------|--------|
| macOS (Apple Silicon) | `mac.sh` | ✅ Ready |
| Linux (MX Linux/Debian) | `linux.sh` | ✅ Ready |

## Quick Start

### macOS

**Install (one-liner):**

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/sb-pk/setup/main/mac.sh)"
```

**Uninstall (one-liner):**

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/sb-pk/setup/main/uninstall-mac.sh)"
```

### Linux (MX Linux/Debian)

**Install (one-liner):**

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/sb-pk/setup/main/linux.sh)"
```

**Uninstall (one-liner):**

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/sb-pk/setup/main/uninstall-linux.sh)"
```

**Or clone and run locally:**

```bash
git clone https://github.com/sb-pk/setup.git && cd setup
chmod +x mac.sh linux.sh
./mac.sh    # macOS
./linux.sh  # MX Linux/Debian
```

> **Note:** The script will prompt for your password (for `sudo` operations) and ask whether to install optional applications individually or in bulk.

## What Gets Installed

### macOS (`mac.sh`)

#### CLI Tools & Packages

| Category | Tools |
|----------|-------|
| Shell | bash, zsh-autosuggestions, zsh-syntax-highlighting, zsh-history-substring-search |
| Dev Tools | git, git-lfs, maven, node, python3, pipx, openjdk@21, shellcheck, wl-clipboard |
| Containers | docker, docker-compose, orbstack |
| Utilities | coreutils, watch, wget, rsync, sshpass, ipinfo-cli |
| Monitoring | ice |
| Networking | tailscale (optional) |
| Remote Access | VS Code Tunnel (optional) |

#### GUI Applications (Casks)

**Core (installed if missing; prompts before reinstalling if already present):**
- iTerm2, Visual Studio Code, Maccy, Stats, Jiggler, Lulu

**Optional (prompted):**
- AppCleaner, CleanMyMac, Little Snitch, Folder Preview Pro
- Boring Notch, Microsoft Teams, IntelliJ IDEA, Postman
- PureVPN, WhatsApp, 4K Video Downloader+

#### Environment Configuration

- Oh My Zsh installation
- Zsh plugin sourcing (autosuggestions, syntax highlighting, history substring search)
- OpenJDK 21 linked to system Java and added to PATH
- Git LFS initialized system-wide

#### System Services (optional)

- VS Code Tunnel service (remote development via `code tunnel service install`)
- Tailscale daemon installation and configuration (SSH, accept-routes, accept-dns)
- FileVault authenticated restart

### Linux (`linux.sh`)

#### CLI Tools & Packages

| Category | Tools |
|----------|-------|
| Shell | zsh, zsh-autosuggestions, zsh-syntax-highlighting, zsh-history-substring-search |
| Dev Tools | git, git-lfs, maven, nodejs, python3, pipx, openjdk-21-jdk, shellcheck |
| Containers | docker.io, docker-compose |
| Utilities | coreutils, htop, watch, wget, rsync, sshpass, curl |
| Networking | tailscale (optional) |
| Remote Access | VS Code Tunnel (optional) |

#### GUI Applications

**Core:**
- Visual Studio Code

#### Environment Configuration

- Oh My Zsh installation with plugins (cloned from git)
- OpenJDK 21 added to PATH via JAVA_HOME
- Git LFS initialized system-wide
- Zsh set as default shell

#### System Services (optional)

- VS Code Tunnel service (remote development via `code tunnel service install`)
- Tailscale daemon installation and configuration (SSH, accept-routes, accept-dns)

## Script Behavior

- **Idempotent:** Safe to re-run — won't duplicate `.zshrc` entries or reinstall Homebrew/Oh My Zsh if already present. Core GUI apps prompt before reinstalling.
- **Interactive:** Prompts before reinstalling core apps and before installing optional apps (bulk or individual selection).
- **Tailscale opt-in:** Asked once at the start; skipped entirely if declined.

## Prerequisites

- macOS on Apple Silicon (paths assume `/opt/homebrew`)
- Internet connection
- Admin (sudo) access

## Uninstalling

To reverse everything `mac.sh` installed:

```bash
chmod +x uninstall-mac.sh
./uninstall-mac.sh
```

This removes all formulas, casks, zshrc entries, Oh My Zsh, VS Code Tunnel service, Tailscale, Git LFS config, and the OpenJDK symlink. Homebrew removal is optional (prompted separately).

## Project Structure

```
setup/
├── mac.sh              # macOS setup script
├── uninstall-mac.sh    # macOS uninstall script
├── linux.sh            # MX Linux/Debian setup script
├── uninstall-linux.sh  # MX Linux/Debian uninstall script
├── LICENSE             # Apache 2.0
└── README.md           # This file
```

## Customization

Edit the arrays in `mac.sh` to add/remove packages:

- `formulas=( ... )` — CLI tools installed via `brew install`
- `optional_apps=( ... )` — GUI apps offered for optional installation
- Core casks line — GUI apps always installed

## License

Apache License 2.0 — see [LICENSE](LICENSE) for details.
