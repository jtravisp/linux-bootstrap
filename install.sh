#!/usr/bin/env bash
#
# Personal Linux bootstrap script (Ubuntu/Debian only).
# Idempotent: safe to re-run. Installs software + shell/terminal config
# matching how this machine's owner sets things up.
#
# Usage: ./install.sh
#   or:  curl -fsSL <raw-url>/install.sh | bash

set -euo pipefail

# ${BASH_SOURCE[0]} is unset when the script runs via `curl ... | bash` (no
# file on disk to source from) — under `set -u` that's a hard crash unless
# guarded. REPO_DIR is empty in that case; steps that need a local checkout
# (dotfiles, aws/config.template) check for that and skip with a warning
# instead of failing.
if [ -n "${BASH_SOURCE[0]:-}" ] && [ -f "${BASH_SOURCE[0]}" ]; then
  REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
else
  REPO_DIR=""
fi

# ---------------------------------------------------------------------------
# helpers
# ---------------------------------------------------------------------------

log()  { printf '\n\033[1;34m==>\033[0m %s\n' "$1"; }
warn() { printf '\033[1;33m!!\033[0m %s\n' "$1"; }

# Idempotent by construction: --no-upgrade leaves already-installed packages
# alone (no re-install, no upgrade) and only acts on the ones that are missing.
apt_install() {
  sudo apt-get install -y --no-upgrade "$@"
}

is_ubuntu_or_debian() {
  [ -f /etc/os-release ] && grep -qiE '^ID(_LIKE)?=.*(debian|ubuntu)' /etc/os-release
}

# `whoami` under `set -u`: $USER isn't guaranteed to be exported (it isn't under
# `sudo -u`, `env -i`, or a systemd unit), and an unset $USER would be a hard
# crash rather than a fallback.
USER_NAME="$(id -un)"

# Third-party apt repos lag new Ubuntu releases by weeks — bootstrapping a
# brand new machine is exactly when a distro is newest, so this is the most
# likely way the script breaks. Probe the running release's codename against
# the repo and fall back to the newest suite the repo actually publishes,
# rather than adding a source that 404s and takes `apt-get update` down with
# it. Order is newest-first; the current codename is tried before any of them.
repo_suite() {
  local base_url="$1" codename fallback
  codename="$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}")"
  for fallback in "$codename" resolute questing plucky noble jammy; do
    if curl -fsS -o /dev/null "$base_url/dists/$fallback/Release" 2>/dev/null; then
      [ "$fallback" = "$codename" ] || \
        warn "This repo has no '$codename' suite yet; using '$fallback' instead." >&2
      echo "$fallback"
      return 0
    fi
  done
  warn "Could not find a usable suite at $base_url; falling back to '$codename'." >&2
  echo "$codename"
}

# Never clobber a real file in $HOME without leaving the old one behind — this
# script is meant to be re-run, and a re-run shouldn't silently eat local edits.
backup_if_real_file() {
  local target="$1"
  if [ -e "$target" ] && [ ! -L "$target" ]; then
    local stamp
    stamp="$(date +%Y%m%d%H%M%S)"
    warn "Backing up existing $target -> $target.bak.$stamp"
    mv "$target" "$target.bak.$stamp"
  fi
}

# 1Password vault item ~/.aws/config gets populated from — see README's
# "1Password vault items" section.
OP_AWS_ITEM="op://Private/AWS SSO"

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
  git zsh unzip jq ripgrep tmux fzf fd-find neovim \
  fontconfig

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
  sudo mkdir -p -m 755 /etc/apt/keyrings
  wget -O - https://apt.releases.hashicorp.com/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/hashicorp-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/hashicorp-archive-keyring.gpg] https://apt.releases.hashicorp.com $(repo_suite https://apt.releases.hashicorp.com) main" \
    | sudo tee /etc/apt/sources.list.d/hashicorp.list >/dev/null
  sudo apt-get update
  apt_install terraform
fi

# ---------------------------------------------------------------------------
# Signal Desktop (official repo — signal.org/download/linux)
# ---------------------------------------------------------------------------

if ! command -v signal-desktop &>/dev/null; then
  log "Installing Signal Desktop"
  sudo mkdir -p -m 755 /etc/apt/keyrings
  # mktemp, not fixed /tmp names: these get copied into system dirs as root,
  # and a predictable path in a world-writable dir is a symlink attack waiting
  # to happen on a shared machine.
  sig_key=$(mktemp); sig_src=$(mktemp)
  curl -fsSL https://updates.signal.org/desktop/apt/keys.asc | gpg --dearmor > "$sig_key"
  sudo cp "$sig_key" /etc/apt/keyrings/signal-desktop-keyring.gpg
  sudo chmod go+r /etc/apt/keyrings/signal-desktop-keyring.gpg
  curl -fsSL -o "$sig_src" https://updates.signal.org/static/desktop/apt/signal-desktop.sources
  # Signal's own .sources points at /usr/share/keyrings/; rewrite it to match
  # where this script actually puts locally-managed keys.
  sed -i 's|/usr/share/keyrings/|/etc/apt/keyrings/|' "$sig_src"
  sudo cp "$sig_src" /etc/apt/sources.list.d/signal-desktop.sources
  rm -f "$sig_key" "$sig_src"
  sudo apt-get update
  apt_install signal-desktop
fi

# ---------------------------------------------------------------------------
# Claude Desktop (official repo — code.claude.com/docs/en/desktop-linux)
# ---------------------------------------------------------------------------

if ! command -v claude-desktop &>/dev/null; then
  log "Installing Claude Desktop"
  sudo mkdir -p -m 755 /etc/apt/keyrings
  sudo curl -fsSLo /etc/apt/keyrings/claude-desktop-archive-keyring.asc https://downloads.claude.ai/claude-desktop/key.asc
  echo "deb [arch=amd64,arm64 signed-by=/etc/apt/keyrings/claude-desktop-archive-keyring.asc] https://downloads.claude.ai/claude-desktop/apt/stable stable main" \
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

if ! command -v 1password &>/dev/null || ! command -v op &>/dev/null; then
  log "Installing 1Password + 1Password CLI"
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -sS https://downloads.1password.com/linux/keys/1password.asc \
    | sudo gpg --dearmor --output /etc/apt/keyrings/1password-archive-keyring.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/1password-archive-keyring.gpg] https://downloads.1password.com/linux/debian/$(dpkg --print-architecture) stable main" \
    | sudo tee /etc/apt/sources.list.d/1password.list >/dev/null
  # debsig-verify's policy/keyring dirs are fixed locations mandated by that
  # tool, unrelated to the apt keyring convention above — left as-is.
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
  # Appended, not prepended: ssh takes the FIRST value it obtains for each
  # keyword, so a `Host *` block at the top of the file would silently win over
  # every per-host IdentityAgent/IdentityFile added later. `Host *` belongs last.
  printf '\nHost *\n  IdentityAgent ~/.1password/agent.sock\n' >> "$SSH_CONFIG"
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
Suites: $(repo_suite https://download.docker.com/linux/ubuntu)
Components: stable
Architectures: $(dpkg --print-architecture)
Signed-By: /etc/apt/keyrings/docker.asc
EOF
  sudo apt-get update
  apt_install docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
fi

# Outside the install guard on purpose: if docker was already present but this
# user isn't in the group yet (installed by other means, or a previous run that
# died before this point), a re-run should still fix it.
if getent group docker >/dev/null && ! id -nG "$USER_NAME" | grep -qw docker; then
  log "Adding $USER_NAME to the docker group"
  sudo usermod -aG docker "$USER_NAME"
  warn "Log out and back in for docker group membership to take effect."
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
# Node.js (NodeSource apt repo — deb.nodesource.com)
#
# NODE_MAJOR tracks the current LTS line; bump it when a new LTS lands.
# NodeSource publishes a single distro-independent "nodistro" suite, so unlike
# the HashiCorp/Docker repos there's no release codename to match.
# ---------------------------------------------------------------------------

NODE_MAJOR=24

if ! dpkg -s nodejs &>/dev/null; then
  log "Installing Node.js ${NODE_MAJOR}.x"
  sudo mkdir -p -m 755 /etc/apt/keyrings
  curl -fsSL https://deb.nodesource.com/gpgkey/nodesource-repo.gpg.key \
    | sudo gpg --dearmor --yes -o /etc/apt/keyrings/nodesource.gpg
  sudo chmod go+r /etc/apt/keyrings/nodesource.gpg
  echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/nodesource.gpg] https://deb.nodesource.com/node_${NODE_MAJOR}.x nodistro main" \
    | sudo tee /etc/apt/sources.list.d/nodesource.list >/dev/null
  sudo apt-get update
  apt_install nodejs
fi

# nvm used to provide node here. It cost ~1.15s of every shell start, so it is
# no longer installed or sourced — but an old install left behind still works
# and will shadow the apt node, so say so rather than silently leaving two.
if [ -d "$HOME/.nvm" ]; then
  warn "$HOME/.nvm is left over from the old nvm setup and is no longer used. Remove it with: rm -rf ~/.nvm"
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

# Symlinked, not copied: the checkout is the source of truth, so a tweak made
# on the machine shows up as a diff in this repo instead of quietly drifting
# away from it. Any pre-existing real file is moved aside first, never eaten.
link_dotfile() {
  local src="$1" dest="$2"
  if [ -L "$dest" ] && [ "$(readlink -f "$dest")" = "$(readlink -f "$src")" ]; then
    return 0
  fi
  backup_if_real_file "$dest"
  ln -sfn "$src" "$dest"
}

if [ -n "$REPO_DIR" ]; then
  log "Linking dotfiles from $REPO_DIR"
  link_dotfile "$REPO_DIR/zsh/.zshrc"      "$HOME/.zshrc"
  link_dotfile "$REPO_DIR/zsh/.p10k.zsh"   "$HOME/.p10k.zsh"

  mkdir -p "$HOME/.config/ghostty"
  link_dotfile "$REPO_DIR/ghostty/config"  "$HOME/.config/ghostty/config"
else
  warn "No local checkout found (ran via curl | bash) — skipping dotfiles (.zshrc, .p10k.zsh, Ghostty config). Clone the repo and run ./install.sh directly to get these."
fi

# ---------------------------------------------------------------------------
# default shell
# ---------------------------------------------------------------------------

if [ "$(getent passwd "$USER_NAME" | cut -d: -f7)" != "$(command -v zsh)" ]; then
  log "Setting zsh as default shell"
  sudo chsh -s "$(command -v zsh)" "$USER_NAME"
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

mkdir -p "$HOME/.aws"

# A config that still has <PLACEHOLDERS> in it is not a real config — treat it
# as absent so a later run (once 1Password is signed in) can fill it in. Only a
# config with real values is left alone; hand-edited ones are never clobbered.
aws_config_needs_writing() {
  [ ! -f "$HOME/.aws/config" ] || grep -q '<ACCOUNT_ID>\|<SSO_ROLE_NAME>\|<SSO_START_URL>' "$HOME/.aws/config"
}

# Everything above this point is unattended, so the one step that needs a human
# waits until here: start the script, walk away, and the only thing still
# wanting you is this prompt. Interactive runs only — it never blocks a piped
# run — and pressing Enter straight away just falls through to the placeholder.
if aws_config_needs_writing && [ -t 0 ] && ! op read "$OP_AWS_ITEM/start_url" &>/dev/null; then
  cat <<'EOF'

1Password isn't signed in yet (or CLI integration isn't on), so this run
can't read your AWS SSO details from the vault yet. To fix that now:
  1. Open 1Password, sign in (QR code from your phone is fastest).
  2. Settings > Developer: turn on "Integrate with 1Password CLI" and
     "Use the SSH Agent".
EOF
  read -rp "Press Enter once that's done (or right away to skip and fix ~/.aws/config later): " _
fi

if ! aws_config_needs_writing; then
  : # already has real values — leave it alone
elif [ -z "$REPO_DIR" ]; then
  warn "No local checkout found (ran via curl | bash) — skipping ~/.aws/config (its template lives in the repo). Clone the repo and run ./install.sh directly to get this."
elif command -v op &>/dev/null \
  && start_url=$(op read "$OP_AWS_ITEM/start_url" 2>/dev/null) \
  && account_id=$(op read "$OP_AWS_ITEM/account_id" 2>/dev/null) \
  && role_name=$(op read "$OP_AWS_ITEM/role_name" 2>/dev/null); then
  log "Populating ~/.aws/config from 1Password"
  backup_if_real_file "$HOME/.aws/config"
  sed -e "s|<SSO_START_URL>|$start_url|" -e "s|<ACCOUNT_ID>|$account_id|" -e "s|<SSO_ROLE_NAME>|$role_name|" \
    "$REPO_DIR/aws/config.template" > "$HOME/.aws/config"
elif [ ! -f "$HOME/.aws/config" ]; then
  log "Writing placeholder AWS SSO config (1Password not readable — edit ~/.aws/config by hand, or sign in and re-run this script)"
  cp "$REPO_DIR/aws/config.template" "$HOME/.aws/config"
else
  # shellcheck disable=SC2088  # literal path in a user-facing message
  warn "~/.aws/config still has placeholders and 1Password isn't readable — sign in to 1Password and re-run to fill it in."
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
    OAuth. The bundled ~/.zshrc already sources ~/.config/op/plugins.sh once
    that file exists, so nothing to add by hand.
  - If you haven't already, add your SSH key to a 1Password "SSH Key" vault
    item (Import existing, or generate a new one) — the agent then serves
    it over ~/.1password/agent.sock, no key file needed. Your existing
    ~/.ssh/id_ed25519 was left untouched either way.
  - Sign in: Brave sync, Steam, Signal (link device via QR), Claude Desktop,
    VS Code.
  - If ~/.aws/config still has <ACCOUNT_ID>/<SSO_ROLE_NAME>/<SSO_START_URL>
    placeholders, sign in to 1Password and just re-run this script — it
    detects a placeholder config and rewrites it with the real values.
    Then `aws sso login --profile tp-site`.
  - Log out and back in for the zsh default shell and docker group change
    to take effect.
  - Run `p10k configure` if you want to redo the prompt from scratch
    instead of using the bundled ~/.p10k.zsh.
EOF
