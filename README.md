# linux-bootstrap

Turns a fresh Ubuntu install into my working machine: the software I
use, my shell and terminal config, and enough of my AWS/SSH/GitHub setup that
the only things left are the logins nobody can automate.

Everything here is personal — the package list, the dotfiles, and the
1Password vault item names are mine. Fork it and change them if you're not me.

Ubuntu and its derivatives (Mint, Pop!_OS, Zorin) only. Not plain Debian: the
Docker repo it uses is the Ubuntu one, and snapd isn't there by default.

## Run it

```sh
git clone git@github.com:jtravisp/linux-bootstrap.git
cd linux-bootstrap
./install.sh
```

Keep the checkout — `~/.zshrc`, `~/.p10k.zsh`, and the Ghostty config are
symlinked into it, so edits you make on the machine show up as diffs here.

You can also run it without cloning:

```sh
curl -fsSL https://raw.githubusercontent.com/jtravisp/linux-bootstrap/main/install.sh | bash
```

That installs all the software, but skips the dotfiles and `~/.aws/config` —
there's no checkout to link them from. It warns and carries on rather than
failing.

It finishes with a summary of what's actually on the machine — every package,
symlink, group membership and 1Password check, marked `ok` or `MISS` — so a
long run's output scrolling past doesn't hide a step that didn't land.

Re-running is safe, and is the intended fix for a half-finished first run. It
skips anything already installed, adds you to the `docker` group if that
hasn't happened, and replaces a placeholder `~/.aws/config` with real values
once 1Password is signed in. Anything it would overwrite is moved to
`<name>.bak.<timestamp>` first.

## The one manual step

The script installs 1Password but can't sign in for you, and the AWS SSO
details live in the vault. So once all the unattended work is done, it stops
and waits:

- Open 1Password and sign in — **"Sign in with QR code"** scanned from your
  phone is much faster than typing the master password and secret key.
- Settings > Developer: turn on **"Integrate with 1Password CLI"** and **"Use
  the SSH Agent"**.
- Press Enter. The run finishes with a real `~/.aws/config` and a working SSH
  agent.

Press Enter without doing any of it and you get a placeholder `~/.aws/config`
instead; sign in later and re-run the script to fill it in.

## After it finishes

1. `op plugin init gh` — authenticates `gh` through 1Password instead of the
   OAuth device flow. `~/.zshrc` already picks up `~/.config/op/plugins.sh`.
2. `aws sso login --profile tp-site`
3. Log out and back in, so the zsh login shell and `docker` group take effect.
4. Sign in to the GUI apps: Brave sync, Steam, Signal (link device by QR),
   Claude Desktop, VS Code.

## What it installs

- **apt**: Ghostty, GitHub CLI, Terraform, Signal Desktop, Claude Desktop,
  Docker, 1Password + 1Password CLI, Node.js (NodeSource)
- **snap**: Brave, Steam, VS Code, kubectl
- **vendor installers** (user-local, no sudo): AWS CLI v2, uv, Claude Code CLI
- **shell**: zsh, oh-my-zsh, powerlevel10k, zsh-autosuggestions,
  zsh-syntax-highlighting, MesloLGS Nerd Font
- **CLI tools**: git, jq, ripgrep, tmux, fzf, fd, neovim

Install 1Password from its apt repo, not snap or Flatpak — the SSH agent and
CLI integration don't work in those builds.

Node.js comes from NodeSource as a plain apt package rather than through a
version manager. `NODE_MAJOR` near the top of the Node section in
`install.sh` tracks the current LTS line; bump it when a new LTS lands. If you
later need per-project Node versions, add `fnm` — it reads `.nvmrc` and costs
about a millisecond of shell startup.

## What it configures

- Symlinks `~/.zshrc`, `~/.p10k.zsh`, `~/.config/ghostty/config` into this
  checkout
- Sets zsh as the login shell
- Points `~/.ssh/config` at the 1Password SSH agent (`~/.1password/agent.sock`)
- Writes `~/.aws/config` from the `AWS SSO` vault item, or a placeholder if
  1Password isn't readable
- Prompts for git `user.name` / `user.email` if unset

Prompt appearance lives entirely in `~/.p10k.zsh` — `~/.zshrc` sets no
`POWERLEVEL9K_*` variables, since `.p10k.zsh` unsets them all when it loads.
Run `p10k configure` to change the prompt.

## What it won't do

- **Touch SSH keys.** Import yours into 1Password, or let it generate one —
  the agent serves it over the socket, so no key file is needed. Any existing
  `~/.ssh/id_*` is left alone.
- **Store real AWS account IDs or SSO URLs.** This repo is public; those come
  from 1Password at runtime.
- **Log you in anywhere.** 1Password and `gh` each need one manual step per
  machine.

## 1Password vault items

In the `Private` vault. These are per-account, not per-machine — a new machine
picks them up as soon as it's signed in.

| Item | Type | Used for |
| --- | --- | --- |
| (any) | SSH Key | The key the SSH agent serves |
| `AWS SSO` | Secure Note | Fields `account_id`, `role_name`, `start_url` → `~/.aws/config` |
| GitHub token | Login / API Credential | `op plugin init gh` |

`install.sh` reads the AWS fields with `op read "op://Private/AWS SSO/<field>"`,
so those field names have to match `aws/config.template`.

## Layout

```
install.sh            everything, top to bottom
aws/config.template   ~/.aws/config, with <PLACEHOLDERS> for the vault values
ghostty/config        ~/.config/ghostty/config
zsh/.zshrc            ~/.zshrc
zsh/.p10k.zsh         ~/.p10k.zsh
```

## Tested

Run start to finish on a pristine Ubuntu 26.04 LXD container: every package,
snap and vendor installer lands, the interactive run answers both git identity
prompts and the 1Password checkpoint, and it exits 0. A second run takes about
five seconds and changes nothing — no re-downloaded fonts, no duplicated
`Host *`, no backup files piling up. The `curl | bash` path skips the dotfiles
with a warning instead of failing. Writing `~/.aws/config` from the vault, and
repairing a placeholder one on a later run, were checked against a stub `op`.

## Known gaps

- Only tested in a container, not on real hardware or a VM. The Docker
  *packages* install, but the daemon has never actually been started.
- The 1Password paths are only proven against a stub `op`. The real vault
  read, the SSH agent, and `op plugin init gh` all need a signed-in account
  and haven't been exercised end to end on a fresh machine.
- Installs only. `apt_install` uses `--no-upgrade`, so re-running never
  upgrades anything already present.
