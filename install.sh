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
  curl wget gnupg ca-certificates apt-transport-https software-properties-common \
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
install_snap 1password
install_snap code classic
install_snap kubectl classic

# ---------------------------------------------------------------------------
# AWS CLI v2 (official installer — installed under ~/.local, no sudo)
# ---------------------------------------------------------------------------

if ! command -v aws &>/dev/null; then
  log "Installing AWS CLI v2"
  tmp="$(mktemp -d)"
  curl -fsSL "https://awscli.amazonaws.com/awscli-exe-linux-$(uname -m).zip" -o "$tmp/awscliv2.zip"
  unzip -q "$tmp/awscliv2.zip" -d "$tmp"
  "$tmp/aws/install" --install-dir "$HOME/.local/share/aws-cli" --bin-dir "$HOME/.local/bin"
  rm -rf "$tmp"
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
# AWS SSO config (placeholder — fill in your real values afterward)
# ---------------------------------------------------------------------------

mkdir -p "$HOME/.aws"
if [ ! -f "$HOME/.aws/config" ]; then
  log "Writing placeholder AWS SSO config (edit ~/.aws/config with your real values)"
  cp "$REPO_DIR/aws/config.template" "$HOME/.aws/config"
fi

# ---------------------------------------------------------------------------
# done
# ---------------------------------------------------------------------------

log "Done."
cat <<'EOF'

Manual steps still needed:
  - Sign in: Brave sync, Steam, 1Password, Signal (link device via QR),
    Claude Desktop, VS Code, GitHub CLI (gh auth login).
  - Edit ~/.aws/config with your real SSO account ID / start URL, then
    run `aws sso login --profile <name>`.
  - SSH keys were intentionally not touched — restore/generate yours
    separately.
  - Log out and back in for the zsh default shell and docker group change
    to take effect.
  - Run `p10k configure` if you want to redo the prompt from scratch
    instead of using the bundled ~/.p10k.zsh.
EOF
