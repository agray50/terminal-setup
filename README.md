# terminal-setup

This repo will contain steps and configuration for setting up dev tools. 

## Vial Split Keyboard

Vial is a software that provides a simple interface for key mapping on compatible keyboards and can be downloaded [here](https://get.vial.today/)

Go to the [split-keyboard](split-keyboard/README.md) directory for the config file and associated images. 

## zsh Setup

* [ohmyzsh](https://github.com/ohmyzsh/ohmyzsh)
	* `chsh -s $(which zsh)`

* [powerlevel10k](https://github.com/romkatv/powerlevel10k)

* [zsh-syntax-highlighting](https://github.com/zsh-users/zsh-syntax-highlighting/blob/master/INSTALL.md)

* [zsh-auto-suggestions](https://github.com/zsh-users/zsh-autosuggestions/blob/master/INSTALL.md)

* [fzf](https://github.com/junegunn/ezf)

* Set key bindings

```
echo '# ------------------------------
# Custom Zsh Keybindings Setup
# ------------------------------
bindkey '\''^B'\'' backward-kill-line
bindkey '\''^F'\'' kill-line
bindkey '\''^O'\'' forward-word
bindkey '\''^P'\'' backward-word
bindkey '\''^Y'\'' clear-screen
alias nf='\$(nvim \$(fzf --preview "cat {}"))'
' | tee -a ~/.zshrc
```

## Theme

* [Capuccin](https://github.com/catppuccin) for the terminal. iTerm/GNOME

* [Nerd Fonts](https://github.com/ryanoasis/nerd-fonts)

## neovim Setup

* [nvim](https://github.com/neovim/neovim/blob/master/INSTALL.md#install-from-package)

* Setup nvim config
    * `cp -rf nvim ~/.config/nvim`

## tmux Setup

* [tmux](https://github.com/tmux/tmux/wiki/Installing)

* [tpm](https://github.com/tmux-plugins/tpm)

* [catppuccin](https://github.com/catppuccin/tmux)

* Install xclip
```
brew install xclip
apk install xclip
```

* Setup dot file `cp tmux/tmux.conf ${HOME}/.tmux.conf`

## Command Line Tools
* [nvm](https://github.com/nvm-sh/nvm)

* [pyenv](https://github.com/pyenv/pyenv)

* [tfenv](https://github.com/tfutils/tfenv)
