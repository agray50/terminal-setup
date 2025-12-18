#!/bin/bash

# =============================================================================
# Cross-Platform Developer Environment Setup Script
# =============================================================================
# This script sets up zsh, oh-my-zsh, neovim, tmux, and related tools
# Works on macOS and Linux (Ubuntu/Debian, Fedora/RHEL, Arch)
# Safe to run multiple times (idempotent)
# =============================================================================

set -euo pipefail  # Exit on error, undefined vars, pipe failures

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKUP_DIR="${HOME}/.config-backups/$(date +%Y%m%d-%H%M%S)"
MANUAL_STEPS=()

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# -----------------------------------------------------------------------------
# Utility Functions
# -----------------------------------------------------------------------------

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

log_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Detect operating system
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            case "$ID" in
                ubuntu|debian)
                    echo "debian"
                    ;;
                fedora|rhel|centos)
                    echo "fedora"
                    ;;
                arch|manjaro)
                    echo "arch"
                    ;;
                *)
                    echo "linux"
                    ;;
            esac
        else
            echo "linux"
        fi
    else
        echo "unknown"
    fi
}

# Check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Backup file or directory
backup_if_exists() {
    local path="$1"
    if [ -e "$path" ]; then
        mkdir -p "$BACKUP_DIR"
        local backup_path="$BACKUP_DIR/$(basename "$path")"
        log_info "Backing up existing $path to $backup_path"
        cp -r "$path" "$backup_path"
        return 0
    fi
    return 1
}

# Add line to file if it doesn't exist (idempotent)
add_line_to_file() {
    local line="$1"
    local file="$2"
    if ! grep -qF "$line" "$file" 2>/dev/null; then
        echo "$line" >> "$file"
        return 0
    fi
    return 1
}

# Add block to file if marker doesn't exist (idempotent)
add_block_to_file() {
    local marker="$1"
    local content="$2"
    local file="$3"

    if ! grep -qF "$marker" "$file" 2>/dev/null; then
        echo -e "\n$content" >> "$file"
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# Package Installation Functions
# -----------------------------------------------------------------------------

install_package() {
    local package="$1"
    local os_type="$2"

    case "$os_type" in
        macos)
            if ! command_exists brew; then
                log_error "Homebrew is not installed. Please install it first:"
                log_error '/bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"'
                exit 1
            fi
            if ! brew list "$package" &>/dev/null; then
                log_info "Installing $package via Homebrew..."
                brew install "$package"
            else
                log_info "$package is already installed"
            fi
            ;;
        debian)
            if ! dpkg -l | grep -q "^ii  $package "; then
                log_info "Installing $package via apt..."
                sudo apt-get update -qq
                sudo apt-get install -y "$package"
            else
                log_info "$package is already installed"
            fi
            ;;
        fedora)
            if ! rpm -q "$package" &>/dev/null; then
                log_info "Installing $package via dnf..."
                sudo dnf install -y "$package"
            else
                log_info "$package is already installed"
            fi
            ;;
        arch)
            if ! pacman -Q "$package" &>/dev/null; then
                log_info "Installing $package via pacman..."
                sudo pacman -S --noconfirm "$package"
            else
                log_info "$package is already installed"
            fi
            ;;
        *)
            log_warning "Unknown OS type. Please install $package manually."
            MANUAL_STEPS+=("Install $package using your package manager")
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Installation Functions
# -----------------------------------------------------------------------------

install_zsh() {
    log_info "=== Installing zsh ==="

    if command_exists zsh; then
        log_success "zsh is already installed"
        return 0
    fi

    local os_type=$(detect_os)
    install_package "zsh" "$os_type"

    # Set zsh as default shell if not already
    if [ "$SHELL" != "$(which zsh)" ]; then
        log_info "Setting zsh as default shell..."
        chsh -s "$(which zsh)"
        log_warning "You may need to log out and back in for shell change to take effect"
    fi
}

install_ohmyzsh() {
    log_info "=== Installing oh-my-zsh ==="

    if [ -d "${HOME}/.oh-my-zsh" ]; then
        log_success "oh-my-zsh is already installed"
        return 0
    fi

    log_info "Installing oh-my-zsh..."
    # Use unattended install to avoid interactive prompts
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    log_success "oh-my-zsh installed"
}

install_powerlevel10k() {
    log_info "=== Installing powerlevel10k theme ==="

    local p10k_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"

    if [ -d "$p10k_dir" ]; then
        log_success "powerlevel10k is already installed"
    else
        log_info "Cloning powerlevel10k..."
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$p10k_dir"
        log_success "powerlevel10k installed"
    fi

    # Update .zshrc to use powerlevel10k theme (idempotent)
    if [ -f "${HOME}/.zshrc" ]; then
        # Check if ZSH_THEME is already set to powerlevel10k
        if ! grep -q '^ZSH_THEME="powerlevel10k/powerlevel10k"' "${HOME}/.zshrc"; then
            log_info "Updating ZSH_THEME to powerlevel10k..."
            # Use portable sed syntax
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' 's/^ZSH_THEME="[^"]*"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "${HOME}/.zshrc"
            else
                sed -i 's/^ZSH_THEME="[^"]*"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "${HOME}/.zshrc"
            fi
        fi
    fi
}

install_zsh_plugins() {
    log_info "=== Installing zsh plugins ==="

    # zsh-syntax-highlighting
    local syntax_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
    if [ -d "$syntax_dir" ]; then
        log_success "zsh-syntax-highlighting is already installed"
    else
        log_info "Installing zsh-syntax-highlighting..."
        git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$syntax_dir"
        log_success "zsh-syntax-highlighting installed"
    fi

    # Update plugins array in .zshrc
    if [ -f "${HOME}/.zshrc" ]; then
        if ! grep -q "plugins=.*zsh-syntax-highlighting" "${HOME}/.zshrc"; then
            log_info "Adding zsh-syntax-highlighting to plugins..."
            # This is a simplified approach - manually add to plugins array
            if grep -q "^plugins=(" "${HOME}/.zshrc"; then
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    sed -i '' 's/^plugins=(\(.*\))/plugins=(\1 zsh-syntax-highlighting)/' "${HOME}/.zshrc"
                else
                    sed -i 's/^plugins=(\(.*\))/plugins=(\1 zsh-syntax-highlighting)/' "${HOME}/.zshrc"
                fi
            fi
        fi
    fi

    # zsh-autosuggestions
    local autosuggestions_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
    if [ -d "$autosuggestions_dir" ]; then
        log_success "zsh-autosuggestions is already installed"
    else
        log_info "Installing zsh-autosuggestions..."
        git clone https://github.com/zsh-users/zsh-autosuggestions "$autosuggestions_dir"
        log_success "zsh-autosuggestions installed"
    fi

    # Update plugins array in .zshrc
    if [ -f "${HOME}/.zshrc" ]; then
        if ! grep -q "plugins=.*zsh-autosuggestions" "${HOME}/.zshrc"; then
            log_info "Adding zsh-autosuggestions to plugins..."
            if grep -q "^plugins=(" "${HOME}/.zshrc"; then
                if [[ "$OSTYPE" == "darwin"* ]]; then
                    sed -i '' 's/^plugins=(\(.*\))/plugins=(\1 zsh-autosuggestions)/' "${HOME}/.zshrc"
                else
                    sed -i 's/^plugins=(\(.*\))/plugins=(\1 zsh-autosuggestions)/' "${HOME}/.zshrc"
                fi
            fi
        fi
    fi
}

install_fzf() {
    log_info "=== Installing fzf ==="

    if command_exists fzf; then
        log_success "fzf is already installed"
        return 0
    fi

    local os_type=$(detect_os)

    # Try package manager first (cleaner installation)
    case "$os_type" in
        macos)
            install_package "fzf" "$os_type"
            # Run install script to set up shell integration
            if [ -f /usr/local/opt/fzf/install ]; then
                /usr/local/opt/fzf/install --key-bindings --completion --no-update-rc
            elif [ -f /opt/homebrew/opt/fzf/install ]; then
                /opt/homebrew/opt/fzf/install --key-bindings --completion --no-update-rc
            fi
            ;;
        debian)
            install_package "fzf" "$os_type"
            ;;
        fedora)
            install_package "fzf" "$os_type"
            ;;
        arch)
            install_package "fzf" "$os_type"
            ;;
        *)
            # Fallback to git installation
            if [ ! -d "${HOME}/.fzf" ]; then
                log_info "Installing fzf from git..."
                git clone --depth 1 https://github.com/junegunn/fzf.git "${HOME}/.fzf"
                "${HOME}/.fzf/install" --key-bindings --completion --no-update-rc
            fi
            ;;
    esac

    log_success "fzf installed"
}

install_neovim() {
    log_info "=== Installing neovim ==="

    if command_exists nvim; then
        local nvim_version=$(nvim --version | head -n1)
        log_success "neovim is already installed: $nvim_version"
        return 0
    fi

    local os_type=$(detect_os)

    case "$os_type" in
        macos)
            install_package "neovim" "$os_type"
            ;;
        debian)
            # Ubuntu/Debian often have outdated neovim, but try package first
            install_package "neovim" "$os_type"
            log_warning "If neovim version is too old, consider installing from:"
            log_warning "https://github.com/neovim/neovim/releases"
            ;;
        fedora)
            install_package "neovim" "$os_type"
            ;;
        arch)
            install_package "neovim" "$os_type"
            ;;
        *)
            log_warning "Please install neovim manually from:"
            log_warning "https://github.com/neovim/neovim/blob/master/INSTALL.md"
            MANUAL_STEPS+=("Install neovim from https://github.com/neovim/neovim/blob/master/INSTALL.md")
            ;;
    esac
}

install_tmux() {
    log_info "=== Installing tmux ==="

    if command_exists tmux; then
        log_success "tmux is already installed"
        return 0
    fi

    local os_type=$(detect_os)
    install_package "tmux" "$os_type"
}

install_tpm() {
    log_info "=== Installing tmux plugin manager (tpm) ==="

    local tpm_dir="${HOME}/.tmux/plugins/tpm"

    if [ -d "$tpm_dir" ]; then
        log_success "tpm is already installed"
        return 0
    fi

    log_info "Cloning tpm..."
    git clone https://github.com/tmux-plugins/tpm "$tpm_dir"
    log_success "tpm installed"

    MANUAL_STEPS+=("After tmux is running, press 'prefix + I' (capital i) to install tmux plugins")
}

install_cli_tools() {
    log_info "=== Installing additional CLI tools ==="

    local os_type=$(detect_os)

    # ripgrep - better grep, used by neovim telescope
    if ! command_exists rg; then
        log_info "Installing ripgrep..."
        install_package "ripgrep" "$os_type"
    else
        log_success "ripgrep is already installed"
    fi

    # fd - better find, used by neovim telescope
    if ! command_exists fd; then
        log_info "Installing fd..."
        case "$os_type" in
            debian)
                install_package "fd-find" "$os_type"
                # Create symlink if it doesn't exist
                if [ ! -e "${HOME}/.local/bin/fd" ]; then
                    mkdir -p "${HOME}/.local/bin"
                    ln -s "$(which fdfind)" "${HOME}/.local/bin/fd" 2>/dev/null || true
                fi
                ;;
            *)
                install_package "fd" "$os_type"
                ;;
        esac
    else
        log_success "fd is already installed"
    fi

    # bat - better cat with syntax highlighting
    if ! command_exists bat; then
        log_info "Installing bat..."
        install_package "bat" "$os_type"
    else
        log_success "bat is already installed"
    fi

    # git - should be installed but check anyway
    if ! command_exists git; then
        log_info "Installing git..."
        install_package "git" "$os_type"
    else
        log_success "git is already installed"
    fi

    # xclip for Linux clipboard support in tmux
    if [[ "$os_type" != "macos" ]]; then
        if ! command_exists xclip; then
            log_info "Installing xclip for tmux clipboard support..."
            install_package "xclip" "$os_type"
        else
            log_success "xclip is already installed"
        fi
    fi
}

install_version_managers() {
    log_info "=== Installing version managers (optional) ==="

    # nvm - Node version manager
    if [ ! -d "${HOME}/.nvm" ]; then
        log_info "Installing nvm..."
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
        log_success "nvm installed"
    else
        log_success "nvm is already installed"
    fi

    # pyenv - Python version manager
    if ! command_exists pyenv; then
        log_info "Installing pyenv..."
        curl https://pyenv.run | bash
        log_success "pyenv installed"

        # Add to zshrc if not present
        local pyenv_init='
# pyenv configuration
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"'

        add_block_to_file "# pyenv configuration" "$pyenv_init" "${HOME}/.zshrc"
    else
        log_success "pyenv is already installed"
    fi

    # tfenv - Terraform version manager
    if ! command_exists tfenv; then
        local os_type=$(detect_os)
        if [[ "$os_type" == "macos" ]]; then
            log_info "Installing tfenv..."
            install_package "tfenv" "$os_type"
        else
            log_info "Installing tfenv from git..."
            if [ ! -d "${HOME}/.tfenv" ]; then
                git clone --depth=1 https://github.com/tfutils/tfenv.git "${HOME}/.tfenv"
                mkdir -p "${HOME}/.local/bin"
                ln -s "${HOME}/.tfenv/bin/*" "${HOME}/.local/bin/" 2>/dev/null || true
            fi
        fi
        log_success "tfenv installed"
    else
        log_success "tfenv is already installed"
    fi
}

# -----------------------------------------------------------------------------
# Configuration Functions
# -----------------------------------------------------------------------------

setup_zsh_keybindings() {
    log_info "=== Setting up custom zsh keybindings ==="

    local keybindings='# ------------------------------
# Custom Zsh Keybindings Setup
# ------------------------------
bindkey '\''^B'\'' backward-kill-line
bindkey '\''^F'\'' kill-line
bindkey '\''^O'\'' forward-word
bindkey '\''^P'\'' backward-word
bindkey '\''^Y'\'' clear-screen'

    if add_block_to_file "# Custom Zsh Keybindings Setup" "$keybindings" "${HOME}/.zshrc"; then
        log_success "Custom keybindings added to .zshrc"
    else
        log_info "Custom keybindings already present in .zshrc"
    fi
}

setup_zsh_aliases() {
    log_info "=== Setting up zsh aliases ==="

    local aliases='
# Custom aliases
alias nf='\''nvim $(fzf --preview "bat --color=always --style=numbers --line-range=:500 {}")'\''
alias gg='\''nvim -c "Neogit"'\'''

    if add_block_to_file "# Custom aliases" "$aliases" "${HOME}/.zshrc"; then
        log_success "Custom aliases added to .zshrc"
    else
        log_info "Custom aliases already present in .zshrc"
    fi
}

setup_nvim_config() {
    log_info "=== Setting up neovim configuration ==="

    local nvim_config_dir="${HOME}/.config/nvim"
    local nvim_source_dir="${SCRIPT_DIR}/nvim"

    if [ ! -d "$nvim_source_dir" ]; then
        log_error "Neovim config directory not found: $nvim_source_dir"
        return 1
    fi

    # Backup existing config
    backup_if_exists "$nvim_config_dir"

    # Create symlink to nvim config (better than copy for development)
    if [ -L "$nvim_config_dir" ]; then
        local current_target=$(readlink "$nvim_config_dir")
        if [ "$current_target" = "$nvim_source_dir" ]; then
            log_success "Neovim config is already symlinked correctly"
            return 0
        else
            log_info "Removing old symlink..."
            rm "$nvim_config_dir"
        fi
    elif [ -d "$nvim_config_dir" ]; then
        log_info "Removing existing directory..."
        rm -rf "$nvim_config_dir"
    fi

    log_info "Creating symlink: $nvim_config_dir -> $nvim_source_dir"
    ln -s "$nvim_source_dir" "$nvim_config_dir"
    log_success "Neovim config symlinked"

    MANUAL_STEPS+=("Open nvim and let Lazy.nvim install plugins (first run may take a few minutes)")
}

setup_tmux_config() {
    log_info "=== Setting up tmux configuration ==="

    local tmux_conf="${HOME}/.tmux.conf"
    local tmux_source="${SCRIPT_DIR}/tmux/tmux.conf"

    if [ ! -f "$tmux_source" ]; then
        log_error "Tmux config file not found: $tmux_source"
        return 1
    fi

    # Backup existing config
    backup_if_exists "$tmux_conf"

    # Copy tmux config (not symlink, as users might want to customize OS-specific parts)
    log_info "Copying tmux config..."
    cp "$tmux_source" "$tmux_conf"

    # Adjust clipboard config based on OS
    local os_type=$(detect_os)
    if [[ "$os_type" == "macos" ]]; then
        log_info "tmux.conf is already configured for macOS (pbcopy)"
    else
        log_info "Updating tmux.conf for Linux (xclip)..."
        # Comment out macOS line and uncomment Linux line
        if [[ "$os_type" == "darwin"* ]]; then
            sed -i '' 's/^bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "pbcopy"/# bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "pbcopy"/' "$tmux_conf"
            sed -i '' 's/^# bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "xclip -in -selection clipboard"/bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "xclip -in -selection clipboard"/' "$tmux_conf"
        else
            sed -i 's/^bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "pbcopy"/# bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "pbcopy"/' "$tmux_conf"
            sed -i 's/^# bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "xclip -in -selection clipboard"/bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "xclip -in -selection clipboard"/' "$tmux_conf"
        fi
    fi

    log_success "Tmux config installed"
}

# -----------------------------------------------------------------------------
# Main Installation Flow
# -----------------------------------------------------------------------------

main() {
    echo "============================================="
    echo "  Developer Environment Setup"
    echo "============================================="
    echo ""

    local os_type=$(detect_os)
    log_info "Detected OS: $os_type"
    echo ""

    # Install core tools
    install_zsh
    install_ohmyzsh
    install_powerlevel10k
    install_zsh_plugins
    install_fzf
    install_neovim
    install_tmux
    install_tpm
    install_cli_tools

    # Install version managers (optional but recommended)
    install_version_managers

    echo ""

    # Setup configurations
    setup_zsh_keybindings
    setup_zsh_aliases
    setup_nvim_config
    setup_tmux_config

    echo ""
    echo "============================================="
    log_success "Setup Complete!"
    echo "============================================="
    echo ""

    # Show backup location if any backups were made
    if [ -d "$BACKUP_DIR" ]; then
        log_info "Backups saved to: $BACKUP_DIR"
        echo ""
    fi

    # Show manual steps
    if [ ${#MANUAL_STEPS[@]} -gt 0 ]; then
        echo "============================================="
        echo "  MANUAL STEPS REQUIRED"
        echo "============================================="
        echo ""
        for step in "${MANUAL_STEPS[@]}"; do
            echo "  • $step"
        done
        echo ""
    fi

    echo "============================================="
    echo "  ADDITIONAL RECOMMENDED STEPS"
    echo "============================================="
    echo ""
    echo "  1. Install a Nerd Font for proper icon display:"
    echo "     https://github.com/ryanoasis/nerd-fonts"
    echo "     Recommended: FiraCode Nerd Font, JetBrainsMono Nerd Font"
    echo ""
    echo "  2. Configure your terminal to use the Nerd Font"
    echo ""
    echo "  3. Install Catppuccin theme for your terminal:"
    echo "     • iTerm2: https://github.com/catppuccin/iterm"
    echo "     • GNOME Terminal: https://github.com/catppuccin/gnome-terminal"
    echo "     • Alacritty: https://github.com/catppuccin/alacritty"
    echo ""
    echo "  4. Run 'p10k configure' to customize your prompt"
    echo ""
    echo "  5. Restart your terminal or run: source ~/.zshrc"
    echo ""
    echo "  6. Open neovim to install plugins (first run takes time)"
    echo ""
    echo "  7. Open tmux and press 'Ctrl-s + I' to install tmux plugins"
    echo ""
    echo "============================================="
    echo ""

    log_info "Enjoy your new development environment!"
}

# Run main function
main "$@"
