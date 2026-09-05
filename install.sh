#!/usr/bin/env bash
#
# Personal Linux bootstrap script (Ubuntu/Debian only).
# Idempotent: safe to re-run. Installs software + shell/terminal config
# matching how this machine's owner sets things up.
#
# Usage: ./install.sh
#   or:  curl -fsSL <raw-url>/install.sh | bash

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$1"; }

apt_pkg_installed() { dpkg -s "$1" &>/dev/null; }

apt_install() {
  local pkgs=()
  for p in "$@"; do
    apt_pkg_installed "$p" || pkgs+=("$p")
  done
  if [ "${#pkgs[@]}" -gt 0 ]; then
    sudo apt-get install -y "${pkgs[@]}"
  fi
}

is_ubuntu_or_debian() {
  [ -f /etc/os-release ] && grep -qiE '^ID(_LIKE)?=.*(debian|ubuntu)' /etc/os-release
}

# ---------------------------------------------------------------------------
# preflight
# ---------------------------------------------------------------------------

if ! is_ubuntu_or_debian; then
  echo "This script targets Ubuntu/Debian (apt-based) systems only." >&2
  exit 1
fi

if [ "$(id -u)" -eq 0 ]; then
  echo "Run this as your normal user, not root (it uses sudo where needed)." >&2
  exit 1
fi

sudo -v

log "Updating apt package index"
sudo apt-get update

# ---------------------------------------------------------------------------
# base apt packages
# ---------------------------------------------------------------------------

log "Installing base packages"
apt_install \
  curl wget gnupg ca-certificates \
  git zsh unzip jq ripgrep tmux fzf fd-find neovim

# fd-find installs the binary as `fdfind`; symlink it to `fd`.
mkdir -p "$HOME/.local/bin"
if ! command -v fd &>/dev/null && [ -x /usr/bin/fdfind ]; then
  ln -sf /usr/bin/fdfind "$HOME/.local/bin/fd"
fi

log "Installing Ghostty terminal"
apt_install ghostty

# ---------------------------------------------------------------------------
# GitHub CLI (official repo — cli.github.com/manual/installation)
# ---------------------------------------------------------------------------

if ! command -v gh &>/dev/null; then
  log "Installing GitHub CLI"
  sudo mkdir -p -m 755 /etc/apt/keyrings
  out=$(mktemp)
  wget -nv -O "$out" https://cli.github.com/packages/githubcli-archive-keyring.gpg
  sudo cp "$out" /etc/apt/keyrings/githubcli-archive-keyring.gpg
  sudo chmod go+r /etc/apt/keyrings/githubcli-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/githubcli-archive-keyring.gpg] https://cli.github.com/packages stable main" \
    | sudo tee /etc/apt/sources.list.d/github-cli.list >/dev/null
  sudo apt-get update
  apt_install gh
fi

# ---------------------------------------------------------------------------
# Terraform (official HashiCorp repo — developer.hashicorp.com/terraform/install)
# ---------------------------------------------------------------------------

if ! command -v terraform &>/dev/null; then
  log "Installing Terraform"
  wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /usr/share/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(. /etc/os-release && echo "$VERSION_CODENAME") main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update
  apt_install terraform
fi

# ---------------------------------------------------------------------------
# Signal Desktop (official repo — signal.org/download/linux)
# ---------------------------------------------------------------------------

if ! command -v signal-desktop &>/dev/null; then
  log "Installing Signal Desktop"
  curl -fsSL https://updates.signal.org/desktop/apt/keys.asc | gpg --dearmor > /tmp/signal-desktop-keyring.gpg
  sudo cp /tmp/signal-desktop-keyring.gpg /usr/share/keyrings/signal-desktop-keyring.gpg
  curl -fsSL -o /tmp/signal-desktop.sources https://updates.signal.org/static/desktop/apt/signal-desktop.sources
  sudo cp /tmp/signal-desktop.sources /etc/apt/sources.list.d/signal-desktop.sources
  sudo apt-get update
  apt_install signal-desktop
fi

# ---------------------------------------------------------------------------
# Claude Desktop (official repo — code.claude.com/docs/en/desktop-linux)
# ---------------------------------------------------------------------------

if ! command -v claude-desktop &>/dev/null; then
  log "Installing Claude Desktop"
  sudo curl -fsSLo /usr/share/keyrings/claude-desktop-archive-keyring.asc https://downloads.claude.ai/claude-desktop/key.asc
  echo "deb [arch=amd64,arm64 signed-by=/usr/share/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" \
    | sudo tee /etc/apt/sources.list.d/claude-desktop.list >/dev/null
  sudo apt-get update
  apt_install claude-desktop
fi

# ---------------------------------------------------------------------------
# 1Password + 1Password CLI (official repo — support.1password.com/install-linux,
# developer.1password.com/docs/cli/get-started)
#
# Installed via apt, NOT snap: the 1Password SSH agent does not work with the
# Snap Store build.
# ---------------------------------------------------------------------------

if ! apt_pkg_installed 1password || ! apt_pkg_installed 1password-cli; then
  log "Installing 1Password + 1Password CLI"
  curl -sS https://downloads.1password.com/linux/keys/1password.asc \
    | sudo gpg --dearmor --output /usr/share/keyrings/1password-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/usr/share/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" \
    | sudo tee /etc/apt/sources.list.d/1password.list >/dev/null
  sudo mkdir -p /etc/debsig/policies/AC2D62742012EA22/
  curl -sS https://downloads.1password.com/linux/debian/debsig/1password.pol \
    | sudo tee /etc/debsig/policies/AC2D62742012EA22/1password.pol >/dev/null
  sudo mkdir -p /usr/share/debsig/keyrings/AC2D62742012EA22
  curl -sS https://downloads.1password.com/linux/keys/1password.asc \
    | sudo gpg --dearmor --output /usr/share/debsig/keyrings/AC2D62742012EA22/debsig.gpg
  sudo apt-get update
  apt_install 1password 1password-cli
fi

# 1Password SSH agent: point ssh at its socket. Requires the desktop app's
# Settings > Developer > "Use the SSH Agent" to be turned on (manual, one-time).
SSH_DIR="$HOME/.ssh"
SSH_CONFIG="$SSH_DIR/config"
mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
touch "$SSH_CONFIG"
chmod 600 "$SSH_CONFIG"
if ! grep -q '1password/agent.sock' "$SSH_CONFIG"; then
  log "Configuring SSH to use the 1Password SSH agent"
  { printf 'Host *\n  IdentityAgent ~/.1password/agent.sock\n\n'; cat "$SSH_CONFIG"; } > "$SSH_CONFIG.tmp"
  mv "$SSH_CONFIG.tmp" "$SSH_CONFIG"
fi

# ---------------------------------------------------------------------------
# Docker (official repo — docs.docker.com/engine/install/ubuntu)
# ---------------------------------------------------------------------------

if ! command -v docker &>/dev/null; then
  log "Installing Docker"
  sudo install -m 0755 -d /etc/apt/keyrings
  sudo curl -fsSL https://download.docker.com/linux/ubuntu/gpg -o /etc/apt/keyrings/docker.asc
  sudo chmod a+r /etc/apt/keyrings/docker.asc
  sudo tee /etc/apt/sources.list.d/docker.sources >/dev/null <<EOF
Types: deb
URIs: https://download.docker.com/linux/ubuntu
Suites: $(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
  sudo apt-get update
  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
  sudo usermod -aG docker "$USER"
  warn "Added $USER to the docker group — log out and back in for it to take effect."
fi

# ---------------------------------------------------------------------------
# snap packages
# ---------------------------------------------------------------------------

snap_installed() { snap list "$1" &>/dev/null; }

install_snap() {
  local name="$1" classic="${2:-}"
  if ! snap_installed "$name"; then
    log "Installing $name (snap)"
    if [ "$classic" = "classic" ]; then
      sudo snap install "$name" --classic
    else
      sudo snap install "$name"
    fi
  fi
}

install_snap brave
install_snap steam
install_snap code classic
install_snap kubectl classic

# ---------------------------------------------------------------------------
# AWS CLI v2 (official installer — defaults to a user-local ~/.local install,
# no sudo)
# ---------------------------------------------------------------------------

if ! command -v aws &>/dev/null; then
  log "Installing AWS CLI v2"
  curl -fsSL https://awscli.amazonaws.com/v2/install.sh | bash
fi

# ---------------------------------------------------------------------------
# uv (Python package/venv manager — official installer, installs to ~/.local/bin)
# ---------------------------------------------------------------------------

if ! command -v uv &>/dev/null; then
  log "Installing uv"
  curl -LsSf https://astral.sh/uv/install.sh | sh
fi

# ---------------------------------------------------------------------------
# Node.js via nvm (latest LTS)
# ---------------------------------------------------------------------------

export NVM_DIR="$HOME/.nvm"
if [ ! -d "$NVM_DIR" ]; then
  log "Installing nvm"
  curl -fsSL https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
fi
# shellcheck disable=SC1091
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
if ! command -v node &>/dev/null; then
  log "Installing Node.js LTS"
  nvm install --lts
  nvm alias default 'lts/*'
fi

# ---------------------------------------------------------------------------
# Claude Code CLI (official installer — code.claude.com)
# ---------------------------------------------------------------------------

if ! command -v claude &>/dev/null; then
  log "Installing Claude Code CLI"
  curl -fsSL https://claude.ai/install.sh | bash
fi

# ---------------------------------------------------------------------------
# zsh: oh-my-zsh + powerlevel10k + plugins + Nerd Font
# ---------------------------------------------------------------------------

if [ ! -d "$HOME/.oh-my-zsh" ]; then
  log "Installing oh-my-zsh"
  RUNZSH=no CHSH=no KEEP_ZSHRC=yes \
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

ZSH_CUSTOM="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}"

clone_if_missing() {
  local repo="$1" dest="$2"
  [ -d "$dest" ] || git clone --depth=1 "$repo" "$dest"
}

clone_if_missing https://github.com/romkatv/powerlevel10k.git "$ZSH_CUSTOM/themes/powerlevel10k"
clone_if_missing https://github.com/zsh-users/zsh-autosuggestions.git "$ZSH_CUSTOM/plugins/zsh-autosuggestions"
clone_if_missing https://github.com/zsh-users/zsh-syntax-highlighting.git "$ZSH_CUSTOM/plugins/zsh-syntax-highlighting"

log "Installing MesloLGS Nerd Font (for powerlevel10k icons)"
FONT_DIR="$HOME/.local/share/fonts"
mkdir -p "$FONT_DIR"
if ! fc-list | grep -qi "MesloLGS NF"; then
  base="https://github.com/romkatv/powerlevel10k-media/raw/master"
  for f in "MesloLGS NF Regular.ttf" "MesloLGS NF Bold.ttf" "MesloLGS NF Italic.ttf" "MesloLGS NF Bold Italic.ttf"; do
    curl -fsSL "$base/${f// /%20}" -o "$FONT_DIR/$f"
  done
  fc-cache -f "$FONT_DIR" >/dev/null
fi

# ---------------------------------------------------------------------------
# dotfiles
# ---------------------------------------------------------------------------

log "Deploying dotfiles"
cp "$REPO_DIR/zsh/.zshrc" "$HOME/.zshrc"
cp "$REPO_DIR/zsh/.p10k.zsh" "$HOME/.p10k.zsh"

mkdir -p "$HOME/.config/ghostty"
cp "$REPO_DIR/ghostty/config" "$HOME/.config/ghostty/config"

# ---------------------------------------------------------------------------
# default shell
# ---------------------------------------------------------------------------

if [ "$(getent passwd "$USER" | cut -d: -f7)" != "$(command -v zsh)" ]; then
  log "Setting zsh as default shell"
  sudo chsh -s "$(command -v zsh)" "$USER"
fi

# ---------------------------------------------------------------------------
# git identity (only prompts if running interactively and unset)
# ---------------------------------------------------------------------------

if [ -t 0 ] && [ -z "$(git config --global user.name || true)" ]; then
  log "Git identity not set"
  read -rp "Git user.name: " git_name
  read -rp "Git user.email: " git_email
  git config --global user.name "$git_name"
  git config --global user.email "$git_email"
fi

# ---------------------------------------------------------------------------
# AWS SSO config — pulled from a 1Password item if available, otherwise a
# placeholder template you fill in by hand. Expects a vault item named
# "AWS SSO" with fields "account_id", "role_name", "start_url" (see README).
# ---------------------------------------------------------------------------

OP_AWS_ITEM="op://Private/AWS SSO"

mkdir -p "$HOME/.aws"
if [ ! -f "$HOME/.aws/config" ]; then
  if command -v op &>/dev/null \
    && start_url=$(op read "$OP_AWS_ITEM/start_url" 2>/dev/null) \
    && account_id=$(op read "$OP_AWS_ITEM/account_id" 2>/dev/null) \
    && role_name=$(op read "$OP_AWS_ITEM/role_name" 2>/dev/null); then
    log "Populating ~/.aws/config from 1Password"
    sed -e "s|<SSO_START_URL>|$start_url|" -e "s|<ACCOUNT_ID>|$account_id|" -e "s|<SSO_ROLE_NAME>|$role_name|" \
      "$REPO_DIR/aws/config.template" > "$HOME/.aws/config"
  else
    log "Writing placeholder AWS SSO config (no 1Password item found — edit ~/.aws/config by hand, or set up the vault item, see README)"
    cp "$REPO_DIR/aws/config.template" "$HOME/.aws/config"
  fi
fi

# ---------------------------------------------------------------------------
# done
# ---------------------------------------------------------------------------

log "Done."
cat <<'EOF'

Manual steps still needed:
  - Sign in to 1Password — use "Sign in with QR code" if offered (scan with
    your phone) instead of typing the master password + secret key. Then in
    Settings > Developer turn on "Integrate with 1Password CLI" and
    "Use the SSH Agent". This is the one real login the rest below rides on.
  - Run `op plugin init gh` once to wire up `gh` via 1Password instead of
    OAuth. Add `source ~/.config/op/plugins.sh` to ~/.zshrc if the plugin
    setup doesn't do it for you.
  - If you haven't already, add your SSH key to a 1Password "SSH Key" vault
    item (Import existing, or generate a new one) — the agent then serves
    it over ~/.1password/agent.sock, no key file needed. Your existing
    ~/.ssh/id_ed25519 was left untouched either way.
  - Sign in: Brave sync, Steam, Signal (link device via QR), Claude Desktop,
    VS Code.
  - If ~/.aws/config still has <ACCOUNT_ID>/<SSO_ROLE_NAME>/<SSO_START_URL>
    placeholders, either fill them in by hand, or create a 1Password item
    named "AWS SSO" with fields account_id/role_name/start_url and re-run
    this script. Then `aws sso login --profile tp-site`.
  - Log out and back in for the zsh default shell and docker group change
    to take effect.
  - Run `p10k configure` if you want to redo the prompt from scratch
    instead of using the bundled ~/.p10k.zsh.
EOF
