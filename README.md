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
  Claude Desktop, Docker
- **snap**: Brave, Steam, 1Password, VS Code, kubectl
- **official installer scripts**: AWS CLI v2 (into `~/.local`, no sudo),
  Claude Code CLI, nvm + Node.js LTS
- **shell**: zsh, oh-my-zsh, powerlevel10k, zsh-autosuggestions,
  zsh-syntax-highlighting, MesloLGS Nerd Font
- **CLI tools**: git, jq, ripgrep, tmux, fzf, fd, neovim

## What it configures

- Deploys `~/.zshrc`, `~/.p10k.zsh`, and `~/.config/ghostty/config` from
  this repo
- Sets zsh as the default shell
- Prompts for git `user.name`/`user.email` if not already set (interactive
  runs only)
- Writes a placeholder `~/.aws/config` (SSO block) if none exists — edit in
  your real account ID and SSO start URL afterward

## What it deliberately does NOT do

- Touch SSH keys (generate, copy, or otherwise) — restore those yourself,
  e.g. from a password manager or backup
- Commit real AWS account IDs / SSO URLs — this is a public repo
- Install the unofficial `claudeai-desktop` or `claude-code` snaps —
  Claude Desktop comes from Anthropic's official apt repo, and Claude Code
  CLI from Anthropic's official installer

## Manual steps after running

- Sign in: Brave sync, Steam, 1Password, Signal (link device), Claude
  Desktop, VS Code, `gh auth login`
- Fill in real values in `~/.aws/config`, then `aws sso login --profile personal`
- Log out/in for the default shell and `docker` group changes to apply
