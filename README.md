# Machine Setup Scripts

Automated provisioning scripts for setting up development machines from scratch. Supports macOS, Debian/Ubuntu/MX Linux, and RHEL/CentOS/Fedora/Rocky/AlmaLinux.

## Supported Platforms

| Platform | Script | Status |
|----------|--------|--------|
| macOS (Apple Silicon) | `mac.sh` | ✅ Ready |
| Debian / Ubuntu / MX Linux | `linux.sh` → `linux-debian.sh` | ✅ Ready |
| RHEL / CentOS / Fedora / Rocky / AlmaLinux | `linux.sh` → `linux-rhel.sh` | ✅ Ready |

> Other Linux distributions will exit with an unsupported message. Open an issue to request support.

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

### Linux

**Install (one-liner):**

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/sb-pk/setup/main/linux.sh)"
```

`linux.sh` auto-detects your distro and runs the appropriate script:
- Debian / Ubuntu / MX Linux → `linux-debian.sh` (apt)
- RHEL / CentOS / Fedora / Rocky / AlmaLinux → `linux-rhel.sh` (dnf)
- Anything else → exits with a friendly unsupported message

**Uninstall (one-liner):**

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/sb-pk/setup/main/uninstall-linux.sh)"
```

**Or clone and run locally:**

```bash
git clone https://github.com/sb-pk/setup.git && cd setup
chmod +x linux.sh
./linux.sh
```

> **Note:** The script will prompt for your password (for `sudo` operations) and ask whether to install optional applications individually or in bulk.

## What Gets Installed

### macOS (`mac.sh`)

#### CLI Tools & Packages

| Category | Tools |
|----------|-------|
| Shell | bash, zsh, zsh-autosuggestions, zsh-syntax-highlighting, zsh-history-substring-search, starship |
| Dev Tools | git, git-lfs, gh, maven, node, python3, pipx, openjdk@21, shellcheck |
| Containers | docker, docker-compose |
| Utilities | coreutils, bat, jq, yq, parallel, ripgrep, watch, wget, rsync, sshpass, ipinfo-cli |
| Monitoring | htop, btop |
| Networking | tailscale (optional) |
| Remote Access | SSH server (optional), VS Code Tunnel (optional) |

#### GUI Applications (Casks)

**Core (installed if missing; prompts before reinstalling if already present):**
- iTerm2, Visual Studio Code, OrbStack

**Optional (free, prompted):**
- Maccy, Stats, Jiggler, Lulu, AppCleaner
- Microsoft Teams, Postman, WhatsApp
- Google Chrome, Brave Browser, Microsoft Edge
- Ollama (local LLM runner)

**Licensed (require separate purchase, prompted separately):**
- CleanMyMac, Little Snitch, Folder Preview Pro, Boring Notch
- IntelliJ IDEA, PureVPN, 4K Video Downloader+

#### Environment Configuration

- Oh My Zsh installation
- Starship shell prompt initialization
- Zsh plugin sourcing (autosuggestions, syntax highlighting, history substring search)
- OpenJDK 21 linked to system Java and added to PATH
- Git LFS initialized system-wide

#### System Services (optional)

- SSH server (Remote Login) with password authentication enabled
- VS Code Tunnel service (remote development via `code tunnel service install`)
- Tailscale daemon installation and configuration (SSH, accept-routes, accept-dns)
- FileVault authenticated restart

---

### Linux — Debian / Ubuntu / MX Linux (`linux-debian.sh`)

#### CLI Tools & Packages

| Category | Tools |
|----------|-------|
| Shell | bash, zsh, zsh-autosuggestions, zsh-syntax-highlighting, zsh-history-substring-search, starship |
| Dev Tools | git, git-lfs, gh, maven, nodejs (Node 20 LTS), python3, pipx, openjdk-21-jdk, shellcheck |
| Containers | docker-ce, docker-compose-plugin (via Docker official apt repo) |
| Utilities | coreutils, bat, jq, yq, parallel, ripgrep, htop, watch, wget, rsync, sshpass, curl, wl-clipboard |
| Networking | tailscale (optional) |
| Remote Access | SSH server (optional), VS Code Tunnel (optional) |

#### GUI Applications

- Visual Studio Code (via Microsoft apt repo)

#### Environment Configuration

- Oh My Zsh + plugins (cloned from GitHub)
- Starship shell prompt initialization
- OpenJDK 21 added to PATH via JAVA_HOME (auto-detected, arch-aware)
- Git LFS initialized system-wide
- Zsh set as default shell
- `bat` alias (`batcat` → `bat`) added automatically
- Ubuntu 22.04: openjdk-21 installed via `openjdk-r/ppa`
- Debian 11: openjdk-21 installed via backports

#### System Services (optional)

- SSH server with password authentication, ufw port 22 opened (systemd + sysVinit supported)
- VS Code Tunnel service
- Tailscale (systemd + sysVinit supported for MX Linux)

---

### Linux — RHEL / CentOS / Fedora / Rocky / AlmaLinux (`linux-rhel.sh`)

#### CLI Tools & Packages

| Category | Tools |
|----------|-------|
| Shell | bash, zsh, zsh-autosuggestions, zsh-syntax-highlighting, zsh-history-substring-search, starship |
| Dev Tools | git, git-lfs, gh, maven, nodejs (Node 20 LTS), python3, pipx, java-21-openjdk-devel, shellcheck |
| Containers | docker-ce, docker-compose-plugin (via Docker official dnf repo) |
| Utilities | coreutils, bat (RHEL 9+/Fedora), jq, yq, parallel, ripgrep, htop, wget, rsync, sshpass, curl, wl-clipboard |
| Networking | tailscale (optional) |
| Remote Access | SSH server (optional), VS Code Tunnel (optional) |

#### GUI Applications

- Visual Studio Code (via Microsoft yum repo)

#### Environment Configuration

- EPEL + CRB/PowerTools enabled automatically on RHEL 8/9, Rocky, AlmaLinux
- NodeSource Node 20 LTS repo added
- Oh My Zsh + plugins (cloned from GitHub)
- OpenJDK 21 added to PATH via JAVA_HOME (auto-detected, arch-aware)
- Git LFS initialized system-wide
- Zsh set as default shell
- Maven installed from binary if not in repos (RHEL 8)
- `pipx` falls back to `pip3 install` if not in EPEL

#### System Services (optional)

- SSH server (`sshd`) with password authentication, firewalld port 22 opened
- VS Code Tunnel service
- Tailscale

---

## Command Line Options

All setup and uninstall scripts accept standard CLI flags for automated or dry-run execution:

| Flag | Long Option | Description |
|------|-------------|-------------|
| `-y` | `--non-interactive` | Bypasses interactive prompts (auto-accepts optional app bulk installs; skips licensed/SSH prompts) |
| | `--dry-run` | Preview actions and command execution without making system changes |
| `-h` | `--help` | Display script usage information and options |

```bash
# Example: Non-interactive dry run
./mac.sh --dry-run -y
./linux.sh --dry-run -y
```

## Script Behavior

- **Idempotent:** Safe to re-run — skips already-installed tools, won't duplicate `.zshrc` entries or reinstall Oh My Zsh/Homebrew if already present.
- **Interactive:** Prompts before reinstalling core apps, before optional apps (bulk or individual), and before licensed software.
- **Distro-aware:** Package names, repos, service names, firewall commands, and Java paths all adapt to the detected distro and version.
- **Arch-aware:** JAVA_HOME and VS Code repo use detected architecture — works on both x86_64 and arm64.
- **Init-aware (Debian):** SSH, Tailscale, and VS Code Tunnel correctly handle both systemd (Ubuntu, Debian) and sysVinit (MX Linux).
- **Tailscale opt-in:** Prompted once; skipped entirely if declined.

## Prerequisites

| Platform | Requirement |
|----------|-------------|
| macOS | Apple Silicon (paths assume `/opt/homebrew`) |
| All | Internet connection |
| All | Admin (`sudo`) access |

## Uninstalling

### macOS

```bash
chmod +x uninstall-mac.sh
./uninstall-mac.sh
```

Removes all formulas, casks, zshrc entries, Oh My Zsh, VS Code Tunnel service, SSH config, Tailscale, Git LFS config, and the OpenJDK symlink. Homebrew removal is optional (prompted separately).

### Linux

```bash
bash -c "$(curl -fsSL https://raw.githubusercontent.com/sb-pk/setup/main/uninstall-linux.sh)"
```

Auto-detects distro and runs `uninstall-linux-debian.sh` or `uninstall-linux-rhel.sh` accordingly. Removes all packages, repos, keyrings, Oh My Zsh, zshrc entries, Docker, SSH server, and Tailscale.

## Project Structure

```
setup/
├── mac.sh                    # macOS setup script
├── uninstall-mac.sh          # macOS uninstall script
├── linux.sh                  # Distro dispatcher (auto-detects and delegates)
├── linux-debian.sh           # Debian / Ubuntu / MX Linux setup (apt)
├── linux-rhel.sh             # RHEL / CentOS / Fedora / Rocky / Alma setup (dnf)
├── uninstall-linux.sh        # Distro dispatcher for uninstall
├── uninstall-linux-debian.sh # Debian / Ubuntu / MX Linux uninstall
├── uninstall-linux-rhel.sh   # RHEL / CentOS / Fedora / Rocky / Alma uninstall
├── LICENSE                   # Apache 2.0
└── README.md                 # This file
```

## Customization

### macOS

Edit the arrays in `mac.sh`:

- `formulas=( ... )` — CLI tools installed via `brew install`
- `core_casks=( ... )` — GUI apps always installed (prompts if already present)
- `optional_apps=( ... )` — Free GUI apps offered for optional installation
- `licensed_apps=( ... )` — Paid GUI apps offered for optional installation

### Linux

Edit the `packages=( ... )` array in `linux-debian.sh` or `linux-rhel.sh` to add/remove packages.

## License

Apache License 2.0 — see [LICENSE](LICENSE) for details.
