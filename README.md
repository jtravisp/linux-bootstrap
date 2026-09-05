# linux-bootstrap

Personal bootstrap script for setting up a fresh Ubuntu/Debian install with
the software and terminal config I actually use.

**Status:** the 1Password integration (SSH agent, CLI, AWS config
population) has been verified end-to-end against a real account and a real
vault item — not just written and hoped for. See "Status" below for what
that verification covered.

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
installed. **You will re-run it once**, deliberately — see the walkthrough
below.

## Full walkthrough on a brand new machine

Order matters here because of one unavoidable chicken-and-egg step: the
script installs 1Password, but can't sign into it for you, so the very
first run can't yet read anything from your vault.

1. `./install.sh` — installs everything (software, shell, dotfiles, SSH
   config pointed at the 1Password agent socket). Since 1Password isn't
   signed in yet, `~/.aws/config` gets written as a placeholder at this
   point — that's expected, not a bug.
2. Open 1Password, sign in. Use **"Sign in with QR code"** if it's offered
   — scan it with the mobile app (already signed into your account) instead
   of typing the master password + secret key by hand.
3. In the 1Password app: Settings > Developer, turn on **"Integrate with
   1Password CLI"** and **"Use the SSH Agent"**.
4. Run `op plugin init gh` once, to authenticate `gh` via 1Password instead
   of the OAuth device flow. The GitHub personal access token this needs
   already exists in the vault from the first machine this was ever set up
   on — you'll just be picking it, not creating a new one.
5. `./install.sh` again. This time `op` is signed in, so it reads the real
   `AWS SSO` vault item and writes a real `~/.aws/config` (see "1Password
   vault items" below — this item already exists in the account, nothing
   to create).
6. `aws sso login --profile tp-site`.
7. Sign in to the rest: Brave sync, Steam, Signal (link device via QR),
   Claude Desktop, VS Code.
8. Log out and back in, for the zsh default shell and `docker` group
   changes to take effect.
9. Optional: `p10k configure` if you want to redo the prompt from scratch
   instead of using the bundled `~/.p10k.zsh`.

## What it installs

- **apt (official repos)**: Ghostty, GitHub CLI, Terraform, Signal Desktop,
  Claude Desktop, Docker, 1Password + 1Password CLI
- **snap**: Brave, Steam, VS Code, kubectl
- **official installer scripts**: AWS CLI v2, uv (both install to
  `~/.local`, no sudo), Claude Code CLI, nvm + Node.js LTS
- **shell**: zsh, oh-my-zsh, powerlevel10k, zsh-autosuggestions,
  zsh-syntax-highlighting, MesloLGS Nerd Font
- **CLI tools**: git, jq, ripgrep, tmux, fzf, fd, neovim

1Password is installed via its official apt repo, not snap — **the SSH
agent and CLI integration do not work with the Snap Store or Flatpak
builds**, confirmed against 1Password's own docs and by testing both.

## What it configures

- Deploys `~/.zshrc`, `~/.p10k.zsh`, and `~/.config/ghostty/config` from
  this repo
- Sets zsh as the default shell
- Prompts for git `user.name`/`user.email` if not already set (interactive
  runs only)
- Points `~/.ssh/config` at the 1Password SSH agent socket
  (`~/.1password/agent.sock`)
- Writes `~/.aws/config` from the `AWS SSO` 1Password item if `op` is
  signed in, otherwise a placeholder template

## What it deliberately does NOT do

- Touch SSH keys (generate, copy, or otherwise) — restore/migrate yours
  into 1Password yourself (Import in the app, or let it generate a new one)
- Commit real AWS account IDs / SSO URLs — this is a public repo
- Silently authenticate `gh` or unlock 1Password — those need one manual
  step per machine (see the walkthrough above)

## 1Password vault items (already set up in the account — reference only)

These live in the `Private` vault of the 1Password account this was built
for. They're per-account, not per-machine — a new machine picks them up as
soon as it's signed in, nothing here needs to be recreated:

- An **SSH Key** item holding the real SSH key the agent serves.
- A **Secure Note** named `AWS SSO` with three custom fields — `account_id`,
  `role_name`, `start_url` — matching `aws/config.template`. `install.sh`
  reads these via `op read op://Private/AWS SSO/<field>`.
- A GitHub **personal access token**, created the first time
  `op plugin init gh` ran — reused by every machine since.

If you ever set this up for a different 1Password account from scratch,
these three are what you need to create once, with those exact field names.

## Status

Verified for real on 2026-09-05, not just written and assumed correct:

- `ssh-add -l` against `~/.1password/agent.sock` lists real keys from the
  vault — the agent works.
- `op vault list` / `op read` succeed against the real account.
- The exact `op read` + `sed` logic `install.sh` uses to build
  `~/.aws/config` was run against the real `AWS SSO` vault item and diffed
  byte-for-byte identical to this machine's actual `~/.aws/config`.

Not yet verified: a truly from-scratch run on a brand new machine/VM (this
was validated piece-by-piece on an already-provisioned machine, not as one
unattended `./install.sh` run start to finish).
