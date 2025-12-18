#!/bin/bash

##Pass arg for mac or linux
##Standard house keeping europipe + sudo require etc

#Install ohmyzsh
sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"

#Install powerlevel10k
git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
sed -i 's/^[[:space:]]*#\?ZSH_THEME="[^"]*"$/ZSH_THEME="powerlevel10k/powerlevel10k"/' ~/.zshrc

#Install zsh-syntax-highlighting
git clone https://github.com/zsh-users/zsh-syntax-highlighting.git ${ZSH_CUSTOM:-~/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting
echo "source ./zsh-syntax-highlighting/zsh-syntax-highlighting.zsh" | tee -a ${HOME}/.zshrc

#Install zsh-autosuggestions
git clone https://github.com/zsh-users/zsh-autosuggestions ~/.zsh/zsh-autosuggestions
echo "source ~/.zsh/zsh-autosuggestions/zsh-autosuggestions.zsh" | tee -a ${HOME}/.zshrc

#Install fzf
git clone --depth 1 https://github.com/junegunn/fzf.git ~/.fzf
~/.fzf/install

#Setup Keybindings
echo '# ------------------------------
# Custom Zsh Keybindings Setup
# ------------------------------
bindkey '\''^B'\'' backward-kill-line
bindkey '\''^F'\'' kill-line
bindkey '\''^O'\'' forward-word
bindkey '\''^P'\'' backward-word
bindkey '\''^Y'\'' clear-screen
' | tee -a ~/.zshrc

#alias nf='\$(nvim \$(fzf --preview "cat {}"))'
#alias gg='nvim -c "Neogit"'

#Setup nvim
## Install with mac and linux trigger to do
cp -rf nvim ${HOME}/.config/nvim

#Setup tmux
## Install with mac and linux trigger to do
cp tmux/tmux.conf ${HOME}/.tmux.conf
