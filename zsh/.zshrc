# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

# Path to your oh-my-zsh installation.
export ZSH="$HOME/.oh-my-zsh"

ZSH_THEME="powerlevel10k/powerlevel10k"

# Prompt appearance lives entirely in ~/.p10k.zsh (sourced at the bottom of this
# file), which begins by unsetting every POWERLEVEL9K_* variable. Setting them
# here has no effect — edit ~/.p10k.zsh or re-run `p10k configure` instead.

# Which plugins would you like to load?
# zsh-syntax-highlighting must stay last in this list.
plugins=(git zsh-autosuggestions zsh-syntax-highlighting)

source $ZSH/oh-my-zsh.sh

# User configuration

export PATH="$HOME/.local/bin:$PATH"

# fzf key bindings (Ctrl-R history search, Ctrl-T file search). Debian/Ubuntu's
# fzf package ships these separately rather than wiring them up on install.
[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && \
  source /usr/share/doc/fzf/examples/key-bindings.zsh
[ -f /usr/share/doc/fzf/examples/completion.zsh ] && \
  source /usr/share/doc/fzf/examples/completion.zsh

# 1Password shell plugins (`op plugin init gh` etc.) — this file only exists
# once at least one plugin has been set up.
[ -f ~/.config/op/plugins.sh ] && source ~/.config/op/plugins.sh

# To customize prompt, run `p10k configure` or edit ~/.p10k.zsh.
[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh
