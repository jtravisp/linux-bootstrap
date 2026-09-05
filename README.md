# linux-bootstrap

Personal bootstrap script for setting up a fresh Ubuntu/Debian install with
the software and terminal config I actually use.

## Usage

```sh
git clone git@github.com:jtravisp/linux-bootstrap.git
cd linux-bootstrap
./install.sh
```

Or directly:

```sh
curl -fsSL https://raw.githubusercontent.com/jtravisp/linux-bootstrap/main/install.sh | bash
```

(Note: piping to `bash` this way skips deploying the dotfiles in this repo,
since there's no local checkout for `install.sh` to copy them from — clone
the repo first if you want the Ghostty config and zsh setup applied too.)

The script is idempotent — safe to re-run, it skips anything already
installed.

## What it installs

- **apt (official repos)**: Ghostty, GitHub CLI, Terraform, Signal Desktop,
  Claude Desktop, Docker, 1Password + 1Password CLI
- **snap**: Brave, Steam, VS Code, kubectl
- **official installer scripts**: AWS CLI v2 (into `~/.local`, no sudo),
  Claude Code CLI, nvm + Node.js LTS
- **shell**: zsh, oh-my-zsh, powerlevel10k, zsh-autosuggestions,
  zsh-syntax-highlighting, MesloLGS Nerd Font
- **CLI tools**: git, jq, ripgrep, tmux, fzf, fd, neovim

1Password is installed via its official apt repo, not snap — the 1Password
SSH agent doesn't work with the Snap Store build.

## What it configures

- Deploys `~/.zshrc`, `~/.p10k.zsh`, and `~/.config/ghostty/config` from
  this repo
- Sets zsh as the default shell
- Prompts for git `user.name`/`user.email` if not already set (interactive
  runs only)
- Points `~/.ssh/config` at the 1Password SSH agent socket
  (`~/.1password/agent.sock`)
- Writes `~/.aws/config` from a 1Password item if one exists (see below),
  otherwise a placeholder template — edit in your real account ID and SSO
  start URL afterward

## What it deliberately does NOT do

- Touch SSH keys (generate, copy, or otherwise) — restore/migrate yours
  into 1Password yourself
- Commit real AWS account IDs / SSO URLs — this is a public repo
- Silently authenticate `gh` or unlock 1Password — those need one manual
  step per machine (see below)

## One-time 1Password setup (per account, not per machine)

To get SSH and `gh` working with no key files or OAuth flow on future
machines, set these up once in your 1Password vault:

- An **SSH Key** item holding your key (import your existing one, or
  generate a new one and retire the old).
- A **Secure Note** (or any item) named `AWS SSO` with three custom fields:
  `account_id`, `role_name`, `start_url` — matching what's in
  `aws/config.template`. `install.sh` reads these via `op read` to write a
  real `~/.aws/config` instead of the placeholder.
- A GitHub **personal access token**, created the first time you run
  `op plugin init gh` (see manual steps below) — reused on every machine
  after that.

## Manual steps after running

- Sign in to 1Password — use **"Sign in with QR code"** if it's offered on
  the welcome screen: scan it with the 1Password mobile app (already signed
  in) instead of typing the master password + secret key by hand. Then in
  Settings > Developer turn on **"Integrate with 1Password CLI"** and
  **"Use the SSH Agent"**. Everything else below depends on this.
- Run `op plugin init gh` once to authenticate `gh` via 1Password instead
  of OAuth device flow.
- Sign in: Brave sync, Steam, Signal (link device), Claude Desktop, VS Code.
- Fill in `~/.aws/config` (by hand, or via the 1Password item above), then
  `aws sso login --profile tp-site`.
- Log out/in for the default shell and `docker` group changes to apply.
