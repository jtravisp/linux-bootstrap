# linux-bootstrap

Personal bootstrap script for setting up a fresh Ubuntu/Debian install with
the software and terminal config I actually use.

**Status:** the 1Password integration (SSH agent, CLI, AWS config
population) has been verified against a real account and a real vault item.
See "Status" below for exactly what's covered and what still isn't.

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
since there's no local checkout for `install.sh` to link them from. It
warns rather than crashes when it hits those steps. Clone the repo first
if you want those too.)

The script is idempotent — safe to re-run, it skips anything already
installed. Re-running is also the intended fix for a half-finished first
run: it will add you to the `docker` group if that didn't happen, and
rewrite a placeholder `~/.aws/config` with real values once 1Password is
signed in. Any pre-existing real file it would replace is moved to
`<name>.bak.<timestamp>` rather than overwritten.

## Full walkthrough on a brand new machine

There's one unavoidable chicken-and-egg step: the script installs
1Password, but can't sign into it for you. `install.sh` handles this with a
single interactive pause, deliberately placed after every unattended step so
nothing else is waiting on you — sign in during the pause and the same run
finishes with a real `~/.aws/config`; skip the pause (or run
non-interactively) and it falls back to a placeholder you fix up with a
second run.

1. `./install.sh`. Every unattended install runs first, so you can start it
   and walk away. At the very end, if `op` still can't read your vault, it
   pauses:
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
     you'll get the placeholder `~/.aws/config` instead. Re-run
     `./install.sh` any time after signing in and it replaces the
     placeholder with the real thing.
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

- Symlinks `~/.zshrc`, `~/.p10k.zsh`, and `~/.config/ghostty/config` to the
  copies in this checkout — symlinks rather than copies so that a tweak made
  on the machine shows up as a diff here instead of silently drifting away
  from the repo. Run `./install.sh` from wherever you want the checkout to
  live permanently.
- Sources fzf's key bindings and, once `op plugin init` has been run,
  `~/.config/op/plugins.sh` from `~/.zshrc`
- Sets zsh as the default shell
- Prompts for git `user.name`/`user.email` if not already set (interactive
  runs only)
- Appends a `Host *` block to `~/.ssh/config` pointing at the 1Password SSH
  agent socket (`~/.1password/agent.sock`) — appended, not prepended,
  because ssh uses the *first* value it finds for a keyword, so a `Host *`
  block at the top of the file would override every per-host setting below it
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
- Ubuntu 26.04 "resolute" is new enough that third-party repos were worth
  checking rather than assuming: `ghostty` is in `resolute/universe`, and
  both HashiCorp's and Docker's apt repos publish a real `resolute` suite
  (a bogus codename 404s on both, so those aren't catch-all responses).
  `install.sh` now probes for the codename anyway and falls back to the
  newest suite a repo does publish, since that lag is the likeliest way a
  bootstrap run breaks on a just-released distro. The fallback path itself
  was exercised by feeding `repo_suite` a bogus codename: it warns and drops
  to the newest suite the repo actually has.
- `awscli.amazonaws.com/v2/install.sh` is real and defaults to
  `~/.local/share` + `~/.local/bin`, as claimed above.
- The `POWERLEVEL9K_*` block that used to sit in `zsh/.zshrc` was dead: line
  27 of `zsh/.p10k.zsh` does `unset -m '(POWERLEVEL9K_*|DEFAULT_USER)~...'`,
  and a live shell confirmed the values in effect all came from `.p10k.zsh`,
  never from `.zshrc`. That block is gone.
- fzf's zsh integration really does live at
  `/usr/share/doc/fzf/examples/{key-bindings,completion}.zsh` — checked
  against the contents of the `fzf` .deb this release ships.
- `install.sh` is `shellcheck -S style` clean.
- The Signal `.sources` keyring-path rewrite (`/usr/share/keyrings/` →
  `/etc/apt/keyrings/`) was tested against the real file Signal serves.

Not yet verified:

- `op plugin init gh` has not actually been run. Whether it cleanly offers
  one of the vault's existing GitHub credentials or requires creating a new
  token is unconfirmed — that command is interactive and wasn't run as
  part of this setup.
- The 1Password pause (sign in during the pause, press Enter, continue in
  the same run) — the pieces it's built from are each verified (the
  `op read` check, the AWS section it feeds into), but the actual live
  experience of pausing and resuming hasn't been run end to end.
- A truly from-scratch run on a brand new machine/VM — this was validated
  piece-by-piece on an already-provisioned machine, not as one unattended
  `./install.sh` run start to finish.
