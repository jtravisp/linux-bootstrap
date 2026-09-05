# linux-bootstrap

Personal bootstrap script for setting up a fresh Ubuntu/Debian install with
the software and terminal config I actually use.

**Status:** the 1Password integration (SSH agent, CLI, AWS config
population) has been verified end-to-end against a real account and a real
vault item, and a real `curl | bash` crash bug was reproduced and fixed —
not just written and hoped for. See "Status" below for exactly what's
covered and what still isn't.

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

(Note: piping to `bash` this way installs all the software fine, but skips
the dotfiles — `.zshrc`, `.p10k.zsh`, Ghostty config — and `~/.aws/config`,
since there's no local checkout for `install.sh` to copy them from. It
warns rather than crashes when it hits those steps. Clone the repo first
if you want those too.)

The script is idempotent — safe to re-run, it skips anything already
installed.

## Full walkthrough on a brand new machine

There's one unavoidable chicken-and-egg step: the script installs
1Password, but can't sign into it for you. `install.sh` handles this with
a single interactive pause mid-run — sign in during the pause and the same
run finishes with a real `~/.aws/config`; skip the pause (or run
non-interactively) and it falls back to a placeholder you fix up with a
second run.

1. `./install.sh`. Partway through, once 1Password itself is installed, it
   pauses if `op` can't yet read your vault:
   - Open 1Password, sign in — use **"Sign in with QR code"** if offered,
     scanning with your phone instead of typing the master password +
     secret key by hand.
   - In the app: Settings > Developer, turn on **"Integrate with 1Password
     CLI"** and **"Use the SSH Agent"**.
   - Back in the terminal, press Enter to continue. The script then reads
     the real `AWS SSO` vault item and writes a real `~/.aws/config` (see
     "1Password vault items" below — this item already exists in the
     account, nothing to create).
   - Prefer to deal with 1Password later? Just press Enter immediately —
     you'll get the placeholder `~/.aws/config` instead, fixable by
     re-running `./install.sh` any time after you've signed in.
2. Run `op plugin init gh` once, to authenticate `gh` via 1Password instead
   of the OAuth device flow. The vault already has GitHub-related
   credentials in it (e.g. a "GH CLI WSL" item) — this may let you pick an
   existing token instead of creating a new one, but that's not confirmed;
   `op plugin init gh` itself has not actually been run as part of this
   setup yet (see "Status").
3. `aws sso login --profile tp-site` (once `~/.aws/config` has real values).
4. Sign in to the rest: Brave sync, Steam, Signal (link device via QR),
   Claude Desktop, VS Code.
5. Log out and back in, for the zsh default shell and `docker` group
   changes to take effect.
6. Optional: `p10k configure` if you want to redo the prompt from scratch
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

All third-party apt signing keys live in `/etc/apt/keyrings/` (not
`/usr/share/keyrings/`, which some vendors' own docs still use) — per
Debian's own guidance, keys go in `/usr/share/keyrings/` only if a package
will keep them updated automatically; none of these are, so
`/etc/apt/keyrings/` (locally-managed) is the correct spot for all of them.

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
- A GitHub **personal access token** for `op plugin init gh` — the vault
  has GitHub-related items already (e.g. "GH CLI WSL"), but whether
  `op plugin init gh` picks one of those up cleanly or needs a fresh token
  created is unconfirmed; that command hasn't actually been run yet.

If you ever set this up for a different 1Password account from scratch,
these three are what you need to create once, with those exact field names.

## Status

Verified for real on 2026-09-05, not just written and assumed correct:

- `ssh-add -l` against `~/.1password/agent.sock` lists real keys from the
  vault — the agent works.
- `op vault list` / `op read` succeed against the real account.
- The exact `op read` + `sed` logic `install.sh` uses to build
  `~/.aws/config` was run against the real `AWS SSO` vault item and diffed
  byte-for-byte identical to this machine's actual `~/.aws/config` — twice,
  before and after a later refactor of that same code path.
- The `curl | bash` path used to crash immediately (`BASH_SOURCE[0]:
  unbound variable`, tripped by `set -u`) before installing anything —
  reproduced against the real file on GitHub, then fixed and re-confirmed
  it now exits cleanly and just skips the checkout-dependent steps.
- The Signal `.sources` keyring-path rewrite (`/usr/share/keyrings/` →
  `/etc/apt/keyrings/`) was tested against the real file Signal serves.

Not yet verified:

- `op plugin init gh` has not actually been run. Whether it cleanly offers
  one of the vault's existing GitHub credentials or requires creating a new
  token is unconfirmed — that command is interactive and wasn't run as
  part of this setup.
- The mid-script 1Password pause (sign in during the pause, press Enter,
  continue in the same run) — the pieces it's built from are each verified
  (the `op read` check, the AWS section it feeds into), but the actual live
  experience of pausing and resuming hasn't been run end to end.
- A truly from-scratch run on a brand new machine/VM — this was validated
  piece-by-piece on an already-provisioned machine, not as one unattended
  `./install.sh` run start to finish.
