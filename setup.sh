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
CYAN='\033[0;36m'
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

# Log a manual step both inline (with a [MANUAL] tag) and append to MANUAL_STEPS
log_manual_step() {
    local step="$1"
    echo -e "${CYAN}[MANUAL]${NC} $step"
    MANUAL_STEPS+=("$step")
}

# Detect operating system
# Checks both ID and ID_LIKE so derivatives (e.g. Linux Mint) are handled correctly
detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ "$OSTYPE" == "linux-gnu"* ]]; then
        if [ -f /etc/os-release ]; then
            . /etc/os-release
            # Build a combined string of ID and ID_LIKE for matching
            local id_string="${ID:-} ${ID_LIKE:-}"
            case "$id_string" in
                *ubuntu*|*debian*)
                    echo "debian"
                    ;;
                *fedora*|*rhel*|*centos*)
                    echo "fedora"
                    ;;
                *arch*|*manjaro*)
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
# Uses printf to avoid misinterpreting escape sequences in content
add_block_to_file() {
    local marker="$1"
    local content="$2"
    local file="$3"

    if ! grep -qF "$marker" "$file" 2>/dev/null; then
        printf '\n%s\n' "$content" >> "$file"
        return 0
    fi
    return 1
}

# -----------------------------------------------------------------------------
# Package Installation Functions
# -----------------------------------------------------------------------------

install_homebrew() {
    if command_exists brew; then
        log_success "Homebrew is already installed"
        return 0
    fi

    log_info "Installing Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"

    # Add brew to PATH for the rest of this script (Apple Silicon path first, then Intel)
    if [ -f /opt/homebrew/bin/brew ]; then
        eval "$(/opt/homebrew/bin/brew shellenv)"
    elif [ -f /usr/local/bin/brew ]; then
        eval "$(/usr/local/bin/brew shellenv)"
    fi

    log_success "Homebrew installed"
}

install_package() {
    local package="$1"
    local os_type="$2"

    case "$os_type" in
        macos)
            if ! brew list "$package" &>/dev/null; then
                log_info "Installing $package via Homebrew..."
                brew install "$package"
            else
                log_info "$package is already installed"
            fi
            ;;
        debian)
            # apt-get update is run once in main(); no per-package update here
            if ! dpkg -l | grep -q "^ii  $package "; then
                log_info "Installing $package via apt..."
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
            log_manual_step "Install $package using your package manager"
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
    else
        local os_type
        os_type=$(detect_os)
        install_package "zsh" "$os_type"
    fi

    # Set zsh as default shell if not already
    if [ "$SHELL" != "$(command -v zsh)" ]; then
        log_info "Setting zsh as default shell..."
        # Ensure zsh is in /etc/shells before calling chsh
        local zsh_path
        zsh_path="$(command -v zsh)"
        if ! grep -qF "$zsh_path" /etc/shells; then
            log_info "Adding $zsh_path to /etc/shells..."
            echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
        fi
        chsh -s "$zsh_path"
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
        if ! grep -q '^ZSH_THEME="powerlevel10k/powerlevel10k"' "${HOME}/.zshrc"; then
            log_info "Updating ZSH_THEME to powerlevel10k..."
            if [[ "$OSTYPE" == "darwin"* ]]; then
                sed -i '' 's/^ZSH_THEME="[^"]*"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "${HOME}/.zshrc"
            else
                sed -i 's/^ZSH_THEME="[^"]*"/ZSH_THEME="powerlevel10k\/powerlevel10k"/' "${HOME}/.zshrc"
            fi
        fi
    fi

    # Copy p10k.zsh from repo if present; otherwise prompt the user to configure
    if [ -f "${SCRIPT_DIR}/p10k.zsh" ]; then
        log_info "Copying p10k.zsh from repo..."
        cp "${SCRIPT_DIR}/p10k.zsh" "${HOME}/.p10k.zsh"
        log_success "p10k.zsh installed to ~/.p10k.zsh"
    else
        log_manual_step "Run 'p10k configure' to customise your prompt"
    fi

    # Ensure the p10k source line is in .zshrc
    add_line_to_file '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh' "${HOME}/.zshrc" \
        && log_success "p10k source line added to .zshrc"
}

install_zsh_plugins() {
    log_info "=== Installing zsh plugins ==="

    local os_type
    os_type=$(detect_os)

    if [[ "$os_type" == "macos" ]]; then
        # Install via Homebrew and source directly (macOS)
        if ! brew list zsh-syntax-highlighting &>/dev/null; then
            log_info "Installing zsh-syntax-highlighting..."
            brew install zsh-syntax-highlighting
        else
            log_success "zsh-syntax-highlighting is already installed"
        fi

        if ! brew list zsh-autosuggestions &>/dev/null; then
            log_info "Installing zsh-autosuggestions..."
            brew install zsh-autosuggestions
        else
            log_success "zsh-autosuggestions is already installed"
        fi

        local syntax_source='source $(brew --prefix)/share/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh'
        local autosugg_source='source $(brew --prefix)/share/zsh-autosuggestions/zsh-autosuggestions.zsh'

        add_line_to_file "$syntax_source" "${HOME}/.zshrc" && log_success "zsh-syntax-highlighting source added"
        add_line_to_file "$autosugg_source" "${HOME}/.zshrc" && log_success "zsh-autosuggestions source added"
    else
        # Install as oh-my-zsh custom plugins (Linux)
        local syntax_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-syntax-highlighting"
        if [ ! -d "$syntax_dir" ]; then
            log_info "Installing zsh-syntax-highlighting..."
            git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$syntax_dir"
            log_success "zsh-syntax-highlighting installed"
        else
            log_success "zsh-syntax-highlighting is already installed"
        fi

        local autosugg_dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins/zsh-autosuggestions"
        if [ ! -d "$autosugg_dir" ]; then
            log_info "Installing zsh-autosuggestions..."
            git clone https://github.com/zsh-users/zsh-autosuggestions "$autosugg_dir"
            log_success "zsh-autosuggestions installed"
        else
            log_success "zsh-autosuggestions is already installed"
        fi

        if [ -f "${HOME}/.zshrc" ]; then
            if ! grep -q "plugins=.*zsh-syntax-highlighting" "${HOME}/.zshrc"; then
                sed -i 's/^plugins=(\(.*\))/plugins=(\1 zsh-syntax-highlighting)/' "${HOME}/.zshrc"
            fi
            if ! grep -q "plugins=.*zsh-autosuggestions" "${HOME}/.zshrc"; then
                sed -i 's/^plugins=(\(.*\))/plugins=(\1 zsh-autosuggestions)/' "${HOME}/.zshrc"
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

    local os_type
    os_type=$(detect_os)

    case "$os_type" in
        macos)
            install_package "fzf" "$os_type"
            # Run the fzf install script with --no-update-rc so it doesn't touch
            # shell rc files itself; we add the source line manually below.
            if [ -f /opt/homebrew/opt/fzf/install ]; then
                /opt/homebrew/opt/fzf/install --key-bindings --completion --no-update-rc
            elif [ -f /usr/local/opt/fzf/install ]; then
                /usr/local/opt/fzf/install --key-bindings --completion --no-update-rc
            fi
            # Manually add the fzf shell integration source line
            add_line_to_file '[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh' "${HOME}/.zshrc" \
                && log_success "fzf shell integration added to .zshrc"
            ;;
        debian)
            install_package "fzf" "$os_type"
            # Debian/Ubuntu package does not add shell integration automatically
            add_line_to_file '[ -f /usr/share/doc/fzf/examples/key-bindings.zsh ] && source /usr/share/doc/fzf/examples/key-bindings.zsh' "${HOME}/.zshrc" \
                && log_success "fzf key-bindings added to .zshrc"
            add_line_to_file '[ -f /usr/share/doc/fzf/examples/completion.zsh ] && source /usr/share/doc/fzf/examples/completion.zsh' "${HOME}/.zshrc" \
                && log_success "fzf completion added to .zshrc"
            ;;
        fedora)
            install_package "fzf" "$os_type"
            add_line_to_file '[ -f /usr/share/fzf/shell/key-bindings.zsh ] && source /usr/share/fzf/shell/key-bindings.zsh' "${HOME}/.zshrc" \
                && log_success "fzf key-bindings added to .zshrc"
            ;;
        arch)
            install_package "fzf" "$os_type"
            add_line_to_file '[ -f /usr/share/fzf/key-bindings.zsh ] && source /usr/share/fzf/key-bindings.zsh' "${HOME}/.zshrc" \
                && log_success "fzf key-bindings added to .zshrc"
            add_line_to_file '[ -f /usr/share/fzf/completion.zsh ] && source /usr/share/fzf/completion.zsh' "${HOME}/.zshrc" \
                && log_success "fzf completion added to .zshrc"
            ;;
        *)
            # Fallback to git installation
            if [ ! -d "${HOME}/.fzf" ]; then
                log_info "Installing fzf from git..."
                git clone --depth 1 https://github.com/junegunn/fzf.git "${HOME}/.fzf"
                "${HOME}/.fzf/install" --key-bindings --completion --no-update-rc
            fi
            add_line_to_file '[ -f ~/.fzf.zsh ] && source ~/.fzf.zsh' "${HOME}/.zshrc" \
                && log_success "fzf shell integration added to .zshrc"
            ;;
    esac

    log_success "fzf installed"
}

install_neovim() {
    log_info "=== Installing neovim ==="

    if command_exists nvim; then
        local nvim_version
        nvim_version=$(nvim --version | head -n1)
        log_success "neovim is already installed: $nvim_version"
        return 0
    fi

    local os_type
    os_type=$(detect_os)

    case "$os_type" in
        macos)
            install_package "neovim" "$os_type"
            ;;
        debian)
            # apt on Ubuntu 22.04 ships neovim 0.7 which is too old; use snap instead
            log_info "Installing neovim via snap (ensures a recent version)..."
            if ! command_exists snapd && ! command_exists snap; then
                log_info "Installing snapd first..."
                sudo apt-get install -y snapd
            fi
            sudo snap install nvim --classic
            log_success "neovim installed via snap"
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
            log_manual_step "Install neovim from https://github.com/neovim/neovim/blob/master/INSTALL.md"
            ;;
    esac
}

install_tmux() {
    log_info "=== Installing tmux ==="

    if command_exists tmux; then
        log_success "tmux is already installed"
        return 0
    fi

    local os_type
    os_type=$(detect_os)
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
    # Headless plugin installation happens in setup_tmux_config after the config is in place
}

install_rust() {
    log_info "=== Installing Rust (rustup) ==="

    if command_exists cargo; then
        log_success "Rust/cargo is already installed"
        return 0
    fi

    log_info "Installing Rust via rustup..."
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
    log_success "Rust installed"

    # Add cargo env source to .zshrc
    add_line_to_file '. "$HOME/.cargo/env"' "${HOME}/.zshrc" \
        && log_success "cargo env source added to .zshrc"
}

install_cli_tools() {
    log_info "=== Installing additional CLI tools ==="

    local os_type
    os_type=$(detect_os)

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
                # Create symlink so 'fd' works as expected
                if [ ! -e "${HOME}/.local/bin/fd" ]; then
                    mkdir -p "${HOME}/.local/bin"
                    ln -s "$(command -v fdfind)" "${HOME}/.local/bin/fd" 2>/dev/null || true
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
    # On Debian/Ubuntu the binary is installed as 'batcat'
    if ! command_exists bat && ! command_exists batcat; then
        log_info "Installing bat..."
        case "$os_type" in
            debian)
                install_package "bat" "$os_type"
                # Create symlink so 'bat' works
                if ! command_exists bat && command_exists batcat; then
                    mkdir -p "${HOME}/.local/bin"
                    ln -sf "$(command -v batcat)" "${HOME}/.local/bin/bat" 2>/dev/null || true
                    log_success "bat symlinked to ~/.local/bin/bat"
                fi
                ;;
            *)
                install_package "bat" "$os_type"
                ;;
        esac
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

    # Ensure ~/.local/bin is in PATH on Linux (needed for fd/bat symlinks)
    if [[ "$os_type" != "macos" ]]; then
        add_line_to_file 'export PATH="$HOME/.local/bin:$PATH"' "${HOME}/.zshrc" \
            && log_success '~/.local/bin added to PATH in .zshrc'
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

    # The nvm install script targets .bashrc (we run in bash); explicitly add
    # the nvm init block to .zshrc as well so zsh sessions pick it up.
    local nvm_block
    nvm_block=$(cat <<'EOF'
# nvm configuration
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
EOF
)
    add_block_to_file "# nvm configuration" "$nvm_block" "${HOME}/.zshrc" \
        && log_success "nvm init block added to .zshrc"

    # pyenv - Python version manager
    if ! command_exists pyenv; then
        log_info "Installing pyenv..."
        curl https://pyenv.run | bash
        log_success "pyenv installed"
    else
        log_success "pyenv is already installed"
    fi

    local pyenv_block
    pyenv_block=$(cat <<'EOF'
# pyenv configuration
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
EOF
)
    add_block_to_file "# pyenv configuration" "$pyenv_block" "${HOME}/.zshrc" \
        && log_success "pyenv init block added to .zshrc"

    # tfenv - Terraform version manager
    if ! command_exists tfenv; then
        local os_type
        os_type=$(detect_os)
        if [[ "$os_type" == "macos" ]]; then
            log_info "Installing tfenv via Homebrew..."
            install_package "tfenv" "$os_type"
        else
            log_info "Installing tfenv from git..."
            if [ ! -d "${HOME}/.tfenv" ]; then
                git clone --depth=1 https://github.com/tfutils/tfenv.git "${HOME}/.tfenv"
            fi
            mkdir -p "${HOME}/.local/bin"
            # Use a loop so the glob expands correctly
            for bin in "${HOME}/.tfenv/bin/"*; do
                local dest="${HOME}/.local/bin/$(basename "$bin")"
                if [ ! -e "$dest" ]; then
                    ln -s "$bin" "$dest"
                fi
            done
        fi
        log_success "tfenv installed"
    else
        log_success "tfenv is already installed"
    fi
}

# -----------------------------------------------------------------------------
# Configuration Functions
# -----------------------------------------------------------------------------

setup_zsh_env() {
    log_info "=== Setting up zsh environment variables ==="

    add_line_to_file 'export EDITOR="nvim"' "${HOME}/.zshrc" \
        && log_success "EDITOR=nvim added to .zshrc"
}

setup_zsh_keybindings() {
    log_info "=== Setting up custom zsh keybindings ==="

    local keybindings
    keybindings=$(cat <<'EOF'
# ------------------------------
# Custom Zsh Keybindings Setup
# ------------------------------
bindkey '^B' backward-kill-line
bindkey '^F' kill-line
bindkey '^O' forward-word
bindkey '^P' backward-word
bindkey '^Y' clear-screen
EOF
)

    if add_block_to_file "# Custom Zsh Keybindings Setup" "$keybindings" "${HOME}/.zshrc"; then
        log_success "Custom keybindings added to .zshrc"
    else
        log_info "Custom keybindings already present in .zshrc"
    fi
}

setup_zsh_aliases() {
    log_info "=== Setting up zsh aliases ==="

    local aliases
    aliases=$(cat <<'EOF'
# Custom aliases
alias nf='nvim $(fzf --preview "bat --color=always --style=numbers --line-range=:500 {}")'
alias gg='nvim -c "Git"'
EOF
)

    if add_block_to_file "# Custom aliases" "$aliases" "${HOME}/.zshrc"; then
        log_success "Custom aliases added to .zshrc"
    else
        log_info "Custom aliases already present in .zshrc"
    fi
}

setup_tmux_autoattach() {
    log_info "=== Setting up tmux auto-attach ==="

    local block
    block=$(cat <<'EOF'
# Auto-attach or create tmux session
if command -v tmux &>/dev/null && [ -z "$TMUX" ]; then
  tmux attach -t main 2>/dev/null || tmux new -s main
fi
EOF
)

    if add_block_to_file "# Auto-attach or create tmux session" "$block" "${HOME}/.zshrc"; then
        log_success "tmux auto-attach added to .zshrc"
    else
        log_info "tmux auto-attach already present in .zshrc"
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

    # Create symlink to nvim config
    if [ -L "$nvim_config_dir" ]; then
        local current_target
        current_target=$(readlink "$nvim_config_dir")
        if [ "$current_target" = "$nvim_source_dir" ]; then
            log_success "Neovim config is already symlinked correctly"
        else
            log_info "Removing old symlink..."
            rm "$nvim_config_dir"
            ln -s "$nvim_source_dir" "$nvim_config_dir"
            log_success "Neovim config symlinked"
        fi
    elif [ -d "$nvim_config_dir" ]; then
        log_info "Removing existing directory..."
        rm -rf "$nvim_config_dir"
        ln -s "$nvim_source_dir" "$nvim_config_dir"
        log_success "Neovim config symlinked"
    else
        log_info "Creating symlink: $nvim_config_dir -> $nvim_source_dir"
        ln -s "$nvim_source_dir" "$nvim_config_dir"
        log_success "Neovim config symlinked"
    fi

    # Headlessly install / sync Lazy.nvim plugins
    if command_exists nvim; then
        log_info "Running Lazy.nvim headless sync..."
        nvim --headless "+Lazy! sync" +qa || log_warning "Lazy.nvim sync encountered an issue; open nvim to resolve"
        log_success "Lazy.nvim sync complete"
    else
        log_warning "nvim not found in PATH; skipping Lazy.nvim sync"
    fi
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

    # Copy tmux config
    log_info "Copying tmux config..."
    cp "$tmux_source" "$tmux_conf"

    # Adjust clipboard config based on OS
    local os_type
    os_type=$(detect_os)
    if [[ "$os_type" == "macos" ]]; then
        log_info "tmux.conf is already configured for macOS (pbcopy)"
    else
        log_info "Updating tmux.conf for Linux (xclip)..."
        # Always use GNU sed on Linux; no inner macOS check needed here
        sed -i 's/^bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "pbcopy"/# bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "pbcopy"/' "$tmux_conf"
        sed -i 's/^# bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "xclip -in -selection clipboard"/bind-key -T copy-mode-vi MouseDragEnd1Pane send-keys -X copy-pipe-and-cancel "xclip -in -selection clipboard"/' "$tmux_conf"
    fi

    log_success "Tmux config installed"

    # Headlessly install tmux plugins via tpm
    local tpm_install="${HOME}/.tmux/plugins/tpm/bin/install_plugins"
    if [ -x "$tpm_install" ]; then
        log_info "Installing tmux plugins headlessly..."
        "$tpm_install" || log_warning "tpm install_plugins encountered an issue"
        log_success "Tmux plugins installed"
    else
        log_warning "tpm install script not found; plugins may not be installed yet"
    fi
}

# -----------------------------------------------------------------------------
# Main Installation Flow
# -----------------------------------------------------------------------------

main() {
    echo "============================================="
    echo "  Developer Environment Setup"
    echo "============================================="
    echo ""

    local os_type
    os_type=$(detect_os)
    log_info "Detected OS: $os_type"
    echo ""

    # --- macOS: ensure Homebrew is present before anything else ---
    if [[ "$os_type" == "macos" ]]; then
        install_homebrew
    fi

    # --- Linux: run a single package-manager update before all installs ---
    if [[ "$os_type" == "debian" ]]; then
        log_info "Running apt-get update..."
        sudo apt-get update -qq
    elif [[ "$os_type" == "fedora" ]]; then
        log_info "Running dnf check-update..."
        sudo dnf check-update -q || true
    elif [[ "$os_type" == "arch" ]]; then
        log_info "Running pacman -Sy..."
        sudo pacman -Sy --noconfirm
    fi

    echo ""

    # --- Install core tools ---
    install_zsh
    install_ohmyzsh
    install_powerlevel10k
    install_zsh_plugins
    install_fzf
    install_neovim
    install_tmux
    install_tpm
    install_rust
    install_cli_tools

    # --- Install version managers (optional but recommended) ---
    install_version_managers

    echo ""

    # --- Setup configurations ---
    setup_zsh_env
    setup_zsh_keybindings
    setup_zsh_aliases
    setup_tmux_autoattach
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

    # Show accumulated manual steps (logged inline already; this is the summary)
    if [ ${#MANUAL_STEPS[@]} -gt 0 ]; then
        echo "============================================="
        echo "  MANUAL STEPS REQUIRED (SUMMARY)"
        echo "============================================="
        echo ""
        for step in "${MANUAL_STEPS[@]}"; do
            echo "  • $step"
        done
        echo ""
    fi

    echo "============================================="
    echo "  POST-INSTALL CHECKLIST"
    echo "============================================="
    echo ""
    echo "  1. Install a Nerd Font for proper icon display:"
    echo "     https://github.com/ryanoasis/nerd-fonts"
    echo "     Recommended: FiraCode Nerd Font, JetBrainsMono Nerd Font"
    echo ""
    echo "  2. Configure your terminal to use the Nerd Font"
    echo ""
    echo "  3. Install Catppuccin theme for your terminal:"
    echo "     • iTerm2:        https://github.com/catppuccin/iterm"
    echo "     • GNOME Terminal: https://github.com/catppuccin/gnome-terminal"
    echo "     • Alacritty:     https://github.com/catppuccin/alacritty"
    echo ""
    echo "  4. Reload your shell configuration:"
    echo "     source ~/.zshrc"
    echo ""
    echo "============================================="
    echo ""

    log_info "Enjoy your new development environment!"
}

# Run main function
main "$@"
