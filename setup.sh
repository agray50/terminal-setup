#!/bin/bash
# =============================================================================
# Developer Environment Setup
# =============================================================================
# Supports: macOS, Ubuntu/Debian, Fedora/RHEL, Arch, and generic Linux
# Uses binary releases where possible — minimal package manager dependency
# Idempotent: safe to run multiple times
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN="${HOME}/.local/bin"
BACKUP_DIR="${HOME}/.config-backups/$(date +%Y%m%d-%H%M%S)"
MANUAL_STEPS=()

# -----------------------------------------------------------------------------
# Logging
# -----------------------------------------------------------------------------

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'
BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'

info()    { echo -e "${BLUE}[INFO]${NC} $1"; }
success() { echo -e "${GREEN}[OK]${NC} $1"; }
warn()    { echo -e "${YELLOW}[WARN]${NC} $1"; }
error()   { echo -e "${RED}[ERROR]${NC} $1" >&2; }
manual()  { echo -e "${CYAN}[MANUAL]${NC} $1"; MANUAL_STEPS+=("$1"); }

# -----------------------------------------------------------------------------
# System Detection
# -----------------------------------------------------------------------------

detect_os() {
    if [[ "$OSTYPE" == "darwin"* ]]; then
        echo "macos"
    elif [[ -f /etc/os-release ]]; then
        local ids
        ids="$(. /etc/os-release; echo "${ID:-} ${ID_LIKE:-}")"
        case "$ids" in
            *ubuntu*|*debian*) echo "debian" ;;
            *fedora*|*rhel*|*centos*) echo "fedora" ;;
            *arch*|*manjaro*) echo "arch" ;;
            *) echo "linux" ;;
        esac
    else
        echo "linux"
    fi
}

# Normalised arch: x86_64 or arm64 (used for neovim / k9s / jq / yq release filenames)
detect_arch() {
    case "$(uname -m)" in
        x86_64)        echo "x86_64" ;;
        aarch64|arm64) echo "arm64" ;;
        *)             uname -m ;;
    esac
}

# Rust-style arch: x86_64 or aarch64 (used for ripgrep/fd/bat/eza release filenames)
detect_arch_rust() {
    case "$(uname -m)" in
        x86_64)        echo "x86_64" ;;
        aarch64|arm64) echo "aarch64" ;;
        *)             uname -m ;;
    esac
}

# Full Rust target triple for the current platform
detect_rust_target() {
    local arch os
    arch=$(detect_arch_rust)
    os=$(detect_os)
    if [[ "$os" == "macos" ]]; then
        echo "${arch}-apple-darwin"
    else
        echo "${arch}-unknown-linux-musl"
    fi
}

# -----------------------------------------------------------------------------
# Utilities
# -----------------------------------------------------------------------------

command_exists() { command -v "$1" >/dev/null 2>&1; }

# Append line to file only if not already present
add_line() {
    grep -qF "$1" "$2" 2>/dev/null || echo "$1" >> "$2"
}

# Append block to file only if marker line is not already present
add_block() {
    local marker="$1" content="$2" file="$3"
    grep -qF "$marker" "$file" 2>/dev/null || printf '\n%s\n' "$content" >> "$file"
}

backup_if_exists() {
    [[ -e "$1" ]] || return 0
    mkdir -p "$BACKUP_DIR"
    cp -r "$1" "$BACKUP_DIR/$(basename "$1")"
    info "Backed up $1"
}

# Resolve latest release tag from a GitHub repo (e.g. "v1.2.3" or "14.1.1")
github_latest_tag() {
    curl -fsLI "https://github.com/$1/releases/latest" -o /dev/null -w '%{url_effective}' 2>/dev/null \
        | sed 's|.*/tag/||'
}

# In-place sed that works on both GNU (Linux) and BSD (macOS) sed
sed_inplace() {
    local expr="$1" file="$2"
    if [[ "$(detect_os)" == "macos" ]]; then
        sed -i '' "$expr" "$file"
    else
        sed -i "$expr" "$file"
    fi
}

# -----------------------------------------------------------------------------
# Package Manager (used only for tools without viable binary releases)
# -----------------------------------------------------------------------------

pkg_install() {
    local pkg="$1" os="${2:-$(detect_os)}"
    case "$os" in
        macos)   brew install "$pkg" ;;
        debian)  sudo apt-get install -y "$pkg" ;;
        fedora)  sudo dnf install -y "$pkg" ;;
        arch)    sudo pacman -S --noconfirm "$pkg" ;;
        *)       manual "Install '$pkg' using your system package manager" ;;
    esac
}

# -----------------------------------------------------------------------------
# Binary Download Helpers
# -----------------------------------------------------------------------------

# Download a .tar.gz archive, find a named binary inside, install to LOCAL_BIN
install_from_tarball() {
    local url="$1" binary="$2"
    local tmpdir
    tmpdir=$(mktemp -d)

    info "Downloading $binary..."
    curl -fsSL "$url" -o "$tmpdir/archive.tar.gz"
    tar -xzf "$tmpdir/archive.tar.gz" -C "$tmpdir"

    local bin_path
    bin_path=$(find "$tmpdir" -name "$binary" -type f | head -1)

    if [[ -z "$bin_path" ]]; then
        rm -rf "$tmpdir"
        error "Could not find '$binary' in archive: $url"
        return 1
    fi

    mkdir -p "$LOCAL_BIN"
    cp "$bin_path" "$LOCAL_BIN/$binary"
    chmod 755 "$LOCAL_BIN/$binary"
    rm -rf "$tmpdir"
    success "$binary installed"
}

# Download a single binary file directly to LOCAL_BIN
install_from_binary_url() {
    local url="$1" binary="$2"
    info "Downloading $binary..."
    mkdir -p "$LOCAL_BIN"
    curl -fsSL "$url" -o "$LOCAL_BIN/$binary"
    chmod 755 "$LOCAL_BIN/$binary"
    success "$binary installed"
}

# -----------------------------------------------------------------------------
# Shell
# -----------------------------------------------------------------------------

install_zsh() {
    info "=== zsh ==="
    if command_exists zsh; then
        success "zsh already installed"
    else
        pkg_install "zsh"
    fi

    local zsh_path
    zsh_path=$(command -v zsh)
    if [[ "$SHELL" != "$zsh_path" ]]; then
        grep -qF "$zsh_path" /etc/shells || echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
        chsh -s "$zsh_path" || warn "chsh failed — on directory-managed systems (e.g. Amazon Workspaces) set your default shell manually (see below)"
        warn "Log out and back in for the shell change to take effect"
    fi
}

install_ohmyzsh() {
    info "=== oh-my-zsh ==="
    if [[ -d "${HOME}/.oh-my-zsh" ]]; then
        success "oh-my-zsh already installed"
        return 0
    fi
    RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
    success "oh-my-zsh installed"
}

install_powerlevel10k() {
    info "=== powerlevel10k ==="
    local dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    if [[ ! -d "$dir" ]]; then
        git clone --depth=1 https://github.com/romkatv/powerlevel10k.git "$dir"
        success "powerlevel10k installed"
    else
        success "powerlevel10k already installed"
    fi

    if [[ -f "${HOME}/.zshrc" ]] && ! grep -q '^ZSH_THEME="powerlevel10k/powerlevel10k"' "${HOME}/.zshrc"; then
        sed_inplace 's|^ZSH_THEME="[^"]*"|ZSH_THEME="powerlevel10k/powerlevel10k"|' "${HOME}/.zshrc"
    fi

    if [[ -f "${SCRIPT_DIR}/p10k.zsh" ]]; then
        cp "${SCRIPT_DIR}/p10k.zsh" "${HOME}/.p10k.zsh"
        success "p10k.zsh installed"
    else
        manual "Run 'p10k configure' to set up your prompt"
    fi

    add_line '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh' "${HOME}/.zshrc"
}

install_zsh_plugins() {
    info "=== zsh plugins ==="
    local custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"

    if [[ ! -d "$custom/zsh-syntax-highlighting" ]]; then
        git clone https://github.com/zsh-users/zsh-syntax-highlighting.git "$custom/zsh-syntax-highlighting"
        success "zsh-syntax-highlighting installed"
    else
        success "zsh-syntax-highlighting already installed"
    fi

    if [[ ! -d "$custom/zsh-autosuggestions" ]]; then
        git clone https://github.com/zsh-users/zsh-autosuggestions "$custom/zsh-autosuggestions"
        success "zsh-autosuggestions installed"
    else
        success "zsh-autosuggestions already installed"
    fi

    if [[ -f "${HOME}/.zshrc" ]]; then
        grep -q "zsh-syntax-highlighting" "${HOME}/.zshrc" || \
            perl -i -pe 's/^(plugins=\()(.+)(\))/$1$2 zsh-syntax-highlighting$3/' "${HOME}/.zshrc"
        grep -q "zsh-autosuggestions" "${HOME}/.zshrc" || \
            perl -i -pe 's/^(plugins=\()(.+)(\))/$1$2 zsh-autosuggestions$3/' "${HOME}/.zshrc"
    fi
}

# -----------------------------------------------------------------------------
# CLI Tools — binary releases
# -----------------------------------------------------------------------------

install_bash() {
    # macOS ships with bash 3.2 (GPL licensing); upgrade to bash 5 via brew
    if [[ "$(detect_os)" != "macos" ]]; then return 0; fi
    info "=== bash (upgrade) ==="
    local current_version
    current_version=$(bash --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    local major="${current_version%%.*}"
    if [[ "$major" -ge 5 ]]; then
        success "bash already at version $current_version"
        return 0
    fi
    brew list bash &>/dev/null || brew install bash
    success "bash upgraded"
}

install_fzf() {
    info "=== fzf ==="
    if [[ ! -d "${HOME}/.fzf" ]]; then
        git clone --depth 1 https://github.com/junegunn/fzf.git "${HOME}/.fzf"
        # --bin: download prebuilt binary only; shell integration handled below
        "${HOME}/.fzf/install" --bin
        success "fzf installed"
    else
        success "fzf already installed"
    fi

    # Ensure binary is reachable from LOCAL_BIN
    mkdir -p "$LOCAL_BIN"
    ln -sf "${HOME}/.fzf/bin/fzf" "$LOCAL_BIN/fzf"

    # Remove legacy fzf shell integration lines (replaced by explicit functions in setup_zsh_functions)
    if [[ -f "${HOME}/.zshrc" ]]; then
        perl -i -ne 'print unless /\[ -f ~\/\.fzf\.zsh \]/ || /eval "\$\(fzf --zsh\)"/' "${HOME}/.zshrc"
    fi
}

install_neovim() {
    info "=== neovim ==="
    if command_exists nvim; then
        success "neovim already installed: $(nvim --version | head -1)"
        return 0
    fi

    local os arch url
    os=$(detect_os)
    arch=$(detect_arch)

    if [[ "$os" == "macos" ]]; then
        url="https://github.com/neovim/neovim/releases/latest/download/nvim-macos-${arch}.tar.gz"
    else
        url="https://github.com/neovim/neovim/releases/latest/download/nvim-linux-${arch}.tar.gz"
    fi

    local tmpdir; tmpdir=$(mktemp -d)
    info "Downloading neovim..."
    curl -fsSL "$url" -o "$tmpdir/nvim.tar.gz"
    tar -xzf "$tmpdir/nvim.tar.gz" -C "$tmpdir"

    local nvim_dir
    nvim_dir=$(find "$tmpdir" -maxdepth 1 -type d -name "nvim*" | head -1)
    mkdir -p "${HOME}/.local"
    rm -rf "${HOME}/.local/nvim"
    mv "$nvim_dir" "${HOME}/.local/nvim"
    mkdir -p "$LOCAL_BIN"
    ln -sf "${HOME}/.local/nvim/bin/nvim" "$LOCAL_BIN/nvim"
    rm -rf "$tmpdir"
    success "neovim installed"
}

install_ripgrep() {
    info "=== ripgrep ==="
    command_exists rg && { success "ripgrep already installed"; return 0; }

    local tag version target
    tag=$(github_latest_tag "BurntSushi/ripgrep")
    version="${tag#v}"
    target=$(detect_rust_target)
    install_from_tarball \
        "https://github.com/BurntSushi/ripgrep/releases/download/${tag}/ripgrep-${version}-${target}.tar.gz" \
        "rg"
}

install_fd() {
    info "=== fd ==="
    command_exists fd && { success "fd already installed"; return 0; }

    local tag target
    tag=$(github_latest_tag "sharkdp/fd")
    target=$(detect_rust_target)
    install_from_tarball \
        "https://github.com/sharkdp/fd/releases/download/${tag}/fd-${tag}-${target}.tar.gz" \
        "fd"
}

install_bat() {
    info "=== bat ==="
    command_exists bat && { success "bat already installed"; return 0; }

    local tag target
    tag=$(github_latest_tag "sharkdp/bat")
    target=$(detect_rust_target)
    install_from_tarball \
        "https://github.com/sharkdp/bat/releases/download/${tag}/bat-${tag}-${target}.tar.gz" \
        "bat"
}

install_eza() {
    info "=== eza ==="
    command_exists eza && { success "eza already installed"; return 0; }

    local os arch url
    os=$(detect_os)

    # eza has no macOS binaries on GitHub releases — brew is the only option
    if [[ "$os" == "macos" ]]; then
        pkg_install "eza" "macos"
        return 0
    fi

    # Linux: x86_64 has a musl build; aarch64 only has gnu
    arch=$(detect_arch_rust)
    if [[ "$arch" == "x86_64" ]]; then
        url="https://github.com/eza-community/eza/releases/latest/download/eza_x86_64-unknown-linux-musl.tar.gz"
    else
        url="https://github.com/eza-community/eza/releases/latest/download/eza_${arch}-unknown-linux-gnu.tar.gz"
    fi

    install_from_tarball "$url" "eza"
}

install_jq() {
    info "=== jq ==="
    command_exists jq && { success "jq already installed"; return 0; }

    local os arch jq_os jq_arch
    os=$(detect_os)
    arch=$(detect_arch)
    [[ "$os" == "macos" ]] && jq_os="macos" || jq_os="linux"
    [[ "$arch" == "x86_64" ]] && jq_arch="amd64" || jq_arch="arm64"

    install_from_binary_url \
        "https://github.com/jqlang/jq/releases/latest/download/jq-${jq_os}-${jq_arch}" \
        "jq"
}

install_yq() {
    info "=== yq ==="
    command_exists yq && { success "yq already installed"; return 0; }

    local os arch yq_os yq_arch
    os=$(detect_os)
    arch=$(detect_arch)
    [[ "$os" == "macos" ]] && yq_os="darwin" || yq_os="linux"
    [[ "$arch" == "x86_64" ]] && yq_arch="amd64" || yq_arch="arm64"

    install_from_binary_url \
        "https://github.com/mikefarah/yq/releases/latest/download/yq_${yq_os}_${yq_arch}" \
        "yq"
}

install_k9s() {
    info "=== k9s ==="
    command_exists k9s && { success "k9s already installed"; return 0; }

    local os arch k9s_os k9s_arch
    os=$(detect_os)
    arch=$(detect_arch)
    [[ "$os" == "macos" ]] && k9s_os="Darwin" || k9s_os="Linux"
    [[ "$arch" == "x86_64" ]] && k9s_arch="amd64" || k9s_arch="arm64"

    install_from_tarball \
        "https://github.com/derailed/k9s/releases/latest/download/k9s_${k9s_os}_${k9s_arch}.tar.gz" \
        "k9s"
}

# -----------------------------------------------------------------------------
# Terminal Multiplexer
# -----------------------------------------------------------------------------

install_tmux() {
    info "=== tmux ==="
    if command_exists tmux; then
        success "tmux already installed"
        return 0
    fi
    pkg_install "tmux"
}

install_tpm() {
    info "=== tpm ==="
    local dir="${HOME}/.tmux/plugins/tpm"
    if [[ -d "$dir" ]]; then
        success "tpm already installed"
        return 0
    fi
    git clone https://github.com/tmux-plugins/tpm "$dir"
    success "tpm installed"
}

# -----------------------------------------------------------------------------
# Language Toolchains & Version Managers
# -----------------------------------------------------------------------------

install_rust() {
    info "=== Rust ==="
    if command_exists cargo; then
        success "Rust already installed"
    else
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
        success "Rust installed"
    fi
    # Always ensure cargo env is sourced — rustup uses --no-modify-path so won't add it itself
    add_line '. "$HOME/.cargo/env"' "${HOME}/.zshrc"
}

install_nvm() {
    info "=== nvm ==="
    if [[ -d "${HOME}/.nvm" ]]; then
        success "nvm already installed"
    else
        curl -o- https://raw.githubusercontent.com/nvm-sh/nvm/v0.40.1/install.sh | bash
        success "nvm installed"
    fi

    # nvm's installer may have already written its init block to .zshrc (when $SHELL=zsh);
    # check for the sourced script rather than our marker to avoid duplicates
    grep -qF 'nvm.sh' "${HOME}/.zshrc" 2>/dev/null || add_block "# nvm" "$(cat <<'EOF'
# nvm
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
[ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
EOF
)" "${HOME}/.zshrc"
}

install_pyenv() {
    info "=== pyenv ==="
    if command_exists pyenv; then
        success "pyenv already installed"
    else
        curl https://pyenv.run | bash
        success "pyenv installed"
    fi

    add_block "# pyenv" "$(cat <<'EOF'
# pyenv
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
eval "$(pyenv init -)"
EOF
)" "${HOME}/.zshrc"
}

install_goenv() {
    info "=== goenv ==="
    if [[ -d "${HOME}/.goenv" ]]; then
        success "goenv already installed"
    else
        git clone --depth=1 https://github.com/go-nv/goenv.git "${HOME}/.goenv"
        success "goenv installed"
    fi

    add_block "# goenv" "$(cat <<'EOF'
# goenv
export GOENV_ROOT="$HOME/.goenv"
export PATH="$GOENV_ROOT/bin:$PATH"
eval "$(goenv init -)"
EOF
)" "${HOME}/.zshrc"
}

install_sdkman() {
    info "=== SDKMAN ==="
    if [[ -d "${HOME}/.sdkman" ]]; then
        success "SDKMAN already installed"
    else
        curl -s "https://get.sdkman.io" | bash
        success "SDKMAN installed"
    fi

    # SDKMAN's installer may have already written its init block to .zshrc;
    # check for the sourced script rather than our marker to avoid duplicates
    grep -qF 'sdkman-init.sh' "${HOME}/.zshrc" 2>/dev/null || add_block "# SDKMAN" "$(cat <<'EOF'
# SDKMAN
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
EOF
)" "${HOME}/.zshrc"
}

install_tfenv() {
    info "=== tfenv ==="
    if command_exists tfenv; then
        success "tfenv already installed"
        return 0
    fi

    if [[ ! -d "${HOME}/.tfenv" ]]; then
        git clone --depth=1 https://github.com/tfutils/tfenv.git "${HOME}/.tfenv"
    fi

    mkdir -p "$LOCAL_BIN"
    for bin in "${HOME}/.tfenv/bin/"*; do
        local dest="$LOCAL_BIN/$(basename "$bin")"
        [[ ! -e "$dest" ]] && ln -s "$bin" "$dest"
    done
    success "tfenv installed"
}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

setup_local_bin() {
    mkdir -p "$LOCAL_BIN"
    add_line 'export PATH="$HOME/.local/bin:$PATH"' "${HOME}/.zshrc"
}

setup_zsh_env() {
    add_line 'export EDITOR="nvim"' "${HOME}/.zshrc"
    success "EDITOR set to nvim"
}

setup_zsh_keybindings() {
    add_block "# Custom keybindings" "$(cat <<'EOF'
# Custom keybindings
bindkey -e
bindkey '^B' backward-kill-line
bindkey '^F' kill-line
bindkey '^P' forward-word
bindkey '^O' backward-word
bindkey '^Y' clear-screen
EOF
)" "${HOME}/.zshrc"
    success "Keybindings configured"
}

setup_zsh_aliases() {
    add_block "# Custom aliases" "$(cat <<'EOF'
# Custom aliases

# eza — better ls
alias ls='eza --icons'
alias ll='eza -lh --git --icons'
alias la='eza -lah --git --icons'
alias lt='eza --tree --icons'
alias l2='eza --tree --level=2 --icons'

# bat — syntax-highlighted cat (no pager for short output)
alias cat='bat --paging=never'

# JSON / YAML pretty-print
alias json='jq .'
alias yaml='yq .'

# tmux
alias ta='tmux attach -t'
alias tl='tmux ls'
alias tn='tmux new -s'
alias tk='tmux kill-session -t'

# terraform
alias tf='terraform'
alias tfi='terraform init'
alias tfp='terraform plan'
alias tfa='terraform apply'
alias tfd='terraform destroy'

# neovim + fzf
alias nf='nvim $(fzf --preview "bat --color=always --style=numbers --line-range=:500 {}")'
alias gg='nvim -c "Git"'
EOF
)" "${HOME}/.zshrc"
    success "Aliases configured"
}

setup_zsh_functions() {
    add_block "# Custom shell functions" "$(cat <<'EOF'
# Custom shell functions

# fh — fuzzy history search; selected command is loaded into the prompt for editing
fh() {
    print -z $(fc -ln 1 | fzf --tac --no-sort)
}

# fcd — fuzzy cd into any subdirectory
fcd() {
    local dir
    dir=$(fd --type d --hidden --exclude .git 2>/dev/null \
        | fzf --preview 'eza --tree --level=2 --icons {}')
    [[ -n "$dir" ]] && cd "$dir"
}

# fgb — fuzzy git branch checkout
fgb() {
    local branch
    branch=$(git branch --all 2>/dev/null | grep -v HEAD \
        | fzf | sed 's|.*remotes/origin/||' | tr -d ' ')
    [[ -n "$branch" ]] && git checkout "$branch"
}

# fkill — fuzzy process kill
fkill() {
    local pid
    pid=$(ps -ef | sed 1d \
        | fzf -m --header='Select process(es) to kill' \
        | awk '{print $2}')
    [[ -n "$pid" ]] && echo "$pid" | xargs kill -9
}

# frg — ripgrep through file contents, preview with bat, open result in nvim
frg() {
    local result file line
    result=$(rg --color=always --line-number --no-heading "${@:-.}" \
        | fzf --ansi --delimiter=: \
              --preview 'bat --color=always {1} --highlight-line {2}' \
              --preview-window 'right:60%:+{2}-5')
    [[ -z "$result" ]] && return
    file=$(echo "$result" | cut -d: -f1)
    line=$(echo "$result" | cut -d: -f2)
    nvim +"$line" "$file"
}
EOF
)" "${HOME}/.zshrc"
    success "Shell functions configured"
}

setup_tmux_autoattach() {
    add_block "# tmux auto-attach" "$(cat <<'EOF'
# tmux auto-attach
if command -v tmux &>/dev/null && [ -z "$TMUX" ]; then
  tmux attach -t main 2>/dev/null || tmux new -s main
fi
EOF
)" "${HOME}/.zshrc"
    success "tmux auto-attach configured"
}

setup_nvim_config() {
    info "=== Neovim config ==="
    local target="${HOME}/.config/nvim"
    local source="${SCRIPT_DIR}/nvim"

    if [[ ! -d "$source" ]]; then
        error "nvim config directory not found: $source"
        return 1
    fi

    if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
        success "Neovim config symlink already correct"
    else
        # Only backup when we are about to replace something
        backup_if_exists "$target"
        rm -rf "$target"
        ln -s "$source" "$target"
        success "Neovim config symlinked: $target -> $source"
    fi

    if command_exists nvim; then
        info "Running lazy.nvim headless sync..."
        nvim --headless "+Lazy! sync" +qa 2>/dev/null \
            || warn "Lazy sync had issues; open nvim to resolve"
        success "Lazy.nvim sync complete"
    else
        warn "nvim not in PATH yet; skipping Lazy sync (re-run setup after shell reload)"
    fi
}

setup_tmux_config() {
    info "=== tmux config ==="
    local target="${HOME}/.tmux.conf"
    local source="${SCRIPT_DIR}/tmux/tmux.conf"

    if [[ ! -f "$source" ]]; then
        error "tmux config not found: $source"
        return 1
    fi

    backup_if_exists "$target"
    cp "$source" "$target"

    if [[ "$(detect_os)" != "macos" ]]; then
        sed -i 's|copy-pipe-and-cancel "pbcopy"|copy-pipe-and-cancel "xclip -in -selection clipboard"|' "$target"
        command_exists xclip || pkg_install "xclip"
    fi

    success "tmux config installed"

    local tpm_install="${HOME}/.tmux/plugins/tpm/bin/install_plugins"
    if [[ -x "$tpm_install" ]]; then
        "$tpm_install" || warn "tpm plugin install had issues"
        success "tmux plugins installed"
    else
        warn "tpm not ready; open tmux and press prefix+I to install plugins"
    fi
}

# -----------------------------------------------------------------------------
# Prerequisite Check
# -----------------------------------------------------------------------------

check_prerequisites() {
    local missing=()

    command_exists git  || missing+=("git")
    command_exists curl || missing+=("curl")
    command_exists perl || missing+=("perl")

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing[*]}"
        echo ""
        echo "  Install them before running this script:"
        echo ""
        echo "  macOS:          xcode-select --install"
        echo "  Debian/Ubuntu:  sudo apt-get install -y git curl perl"
        echo "  Fedora/RHEL:    sudo dnf install -y git curl perl"
        echo ""
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    echo "============================================="
    echo "  Developer Environment Setup"
    echo "============================================="
    echo ""

    check_prerequisites

    local os; os=$(detect_os)
    info "OS: $os | Arch: $(detect_arch)"
    echo ""

    setup_local_bin

    case "$os" in
        macos)
            command_exists brew || {
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            }
            # Always ensure brew is on PATH for this session
            [[ -f /opt/homebrew/bin/brew ]] \
                && eval "$(/opt/homebrew/bin/brew shellenv)" \
                || eval "$(/usr/local/bin/brew shellenv)"
            # Add Homebrew bin to PATH permanently in .zshrc
            add_block "# Homebrew" "$(cat <<'EOF'
# Homebrew — Apple Silicon uses /opt/homebrew, Intel uses /usr/local
[[ -d /opt/homebrew/bin ]] && export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
[[ -d /usr/local/bin ]] && export PATH="/usr/local/bin:/usr/local/sbin:$PATH"
EOF
)" "${HOME}/.zshrc"
            # tfenv requires GNU grep; macOS ships with BSD grep
            brew list grep &>/dev/null || brew install grep
            # Add GNU grep to PATH so it takes precedence over BSD grep
            add_line 'export PATH="$(brew --prefix)/opt/grep/libexec/gnubin:$PATH"' "${HOME}/.zshrc"
            ;;
        debian)  sudo apt-get update -qq || warn "apt-get update had errors — check /etc/apt/sources.list.d/ for misconfigured repos" ;;
        fedora)  sudo dnf check-update -q || true ;;
    esac

    echo ""
    info "--- Installing tools ---"
    install_zsh
    install_ohmyzsh
    install_powerlevel10k
    install_zsh_plugins
    install_fzf
    install_neovim
    install_tmux
    install_tpm
    install_bash
    install_rust
    install_ripgrep
    install_fd
    install_bat
    install_eza
    install_jq
    install_yq
    install_k9s
    install_nvm
    install_pyenv
    install_goenv
    install_sdkman
    install_tfenv

    echo ""
    info "--- Configuring dotfiles ---"
    setup_zsh_env
    setup_zsh_keybindings
    setup_zsh_aliases
    setup_zsh_functions
    setup_tmux_autoattach
    setup_nvim_config
    setup_tmux_config

    echo ""
    echo "============================================="
    success "Setup complete!"
    echo "============================================="
    echo ""

    [[ -d "$BACKUP_DIR" ]] && info "Backups saved to: $BACKUP_DIR"

    if [[ ${#MANUAL_STEPS[@]} -gt 0 ]]; then
        echo ""
        echo "  MANUAL STEPS REQUIRED:"
        for step in "${MANUAL_STEPS[@]}"; do
            echo "  • $step"
        done
        echo ""
    fi

    cat <<'CHECKLIST'

  POST-INSTALL CHECKLIST
  ─────────────────────────────────────────────

  Complete these steps in order:

  1. Reload your shell:
       source ~/.zshrc

  2. Install a Nerd Font (required for icons and prompt):
       https://github.com/ryanoasis/nerd-fonts
       Recommended: JetBrainsMono Nerd Font
     Then set it as the font in your terminal emulator.

  3. Install Catppuccin theme for your terminal:
       iTerm2:  https://github.com/catppuccin/iterm
       GNOME:   https://github.com/catppuccin/gnome-terminal
       Alacritty: https://github.com/catppuccin/alacritty

  4. Configure your prompt (only if no p10k.zsh in repo):
       p10k configure

  5. Install Node.js:
       nvm install --lts && nvm use --lts

  6. Install Python:
       pyenv install 3.13.0 && pyenv global 3.13.0

  7. Install Go:
       goenv install 1.23.0 && goenv global 1.23.0

  8. Install Java:
       sdk install java

  9. Install Terraform:
       tfenv install latest && tfenv use latest

  10. Install tmux plugins:
       Open tmux, then press: Ctrl-s + I

CHECKLIST
}

main "$@"
