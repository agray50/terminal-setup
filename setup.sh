#!/bin/bash
# =============================================================================
# Developer Environment Setup
# =============================================================================
# Supports: macOS, Ubuntu/Debian, Fedora/RHEL, Arch, and generic Linux
# Uses binary releases where possible — minimal package manager dependency
# Idempotent: safe to run multiple times
#
# STABILITY MODEL
# ---------------
# Every version this script installs is pinned in `versions.lock`. A normal run
# reads only that file and makes ZERO version-resolution network calls, so the
# result is deterministic and reproducible — the same commit of this repo always
# produces the same environment.
#
#   ./setup.sh            install/repair to match versions.lock
#   ./setup.sh --update   re-resolve latest upstream versions, rewrite
#                         versions.lock, install NOTHING (review the diff first)
#   ./setup.sh --check    report drift between versions.lock and what's on disk
#   ./setup.sh --dry-run  show what would change, change nothing
# =============================================================================

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LOCAL_BIN="${HOME}/.local/bin"
BACKUP_DIR="${HOME}/.config-backups/$(date +%Y%m%d-%H%M%S)"
BACKUP_WARN_AT=25
LOCKFILE="${SCRIPT_DIR}/versions.lock"
MANUAL_STEPS=()

# Every temp file lives under one directory removed on exit, so a failure part
# way through (this runs under `set -e`) never strands half-written copies of
# ~/.zshrc or multi-megabyte release archives in $TMPDIR.
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

DRY_RUN=false
MODE="install"   # install | update | check | print-block
PRINT_BLOCK=""

while [[ $# -gt 0 ]]; do
    case "$1" in
        --dry-run) DRY_RUN=true ;;
        --update)  MODE="update" ;;
        --check)   MODE="check" ;;
        --print-block)
            MODE="print-block"
            PRINT_BLOCK="${2:-}"
            shift
            ;;
        --help|-h)
            cat <<'USAGE'
Usage: ./setup.sh [OPTION]

  (no option)   Install/repair the environment to match versions.lock.
                Deterministic: no version resolution, no network version checks.

  --update      Re-resolve the latest upstream version of every pinned tool,
                rewrite versions.lock, and install nothing. Review with
                `git diff versions.lock`, then run ./setup.sh to apply.

  --check       Report drift between versions.lock and what is installed.

  --dry-run     Show what would be installed/changed without changing anything.

  --print-block <nvm|pyenv|goenv>
                Print the managed ~/.zshrc block for a version manager, exactly
                as a fresh install writes it (scripts/verify.sh tests these).

  --help, -h    Show this message.

Roll back an update with:  git checkout versions.lock && ./setup.sh
USAGE
            exit 0
            ;;
    esac
    shift
done

# Helpers live in lib/: common.sh is everything an installer needs (logging,
# pins, platform, file editing, downloads); versions.sh is the --update and
# --check machinery, the only code here that talks to the network.
# shellcheck source=lib/common.sh
source "${SCRIPT_DIR}/lib/common.sh"
# shellcheck source=lib/versions.sh
source "${SCRIPT_DIR}/lib/versions.sh"

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
        if grep -qF "$zsh_path" /etc/shells 2>/dev/null; then
            :
        elif $DRY_RUN; then
            info "[dry-run] would add $zsh_path to /etc/shells"
        else
            echo "$zsh_path" | sudo tee -a /etc/shells >/dev/null
        fi
        if $DRY_RUN; then
            info "[dry-run] would run: chsh -s $zsh_path"
        else
            chsh -s "$zsh_path" || warn "chsh failed — on directory-managed systems (e.g. Amazon Workspaces) set your default shell manually (see below)"
        fi
        warn "Log out and back in for the shell change to take effect"
    fi
}

install_ohmyzsh() {
    info "=== oh-my-zsh ==="
    local dir="${HOME}/.oh-my-zsh"
    if [[ ! -d "$dir" ]]; then
        dry_skip "would install oh-my-zsh" && return 0
        RUNZSH=no CHSH=no sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
        success "oh-my-zsh installed"
    fi
    # oh-my-zsh publishes no tags, so the installer always lands on master HEAD.
    # Move it to the pinned commit so it stops being a moving target.
    clone_at_tag "https://github.com/ohmyzsh/ohmyzsh.git" "$dir" "$(pin OHMYZSH_COMMIT)" "oh-my-zsh"
}

install_powerlevel10k() {
    info "=== powerlevel10k ==="
    local dir="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/themes/powerlevel10k"
    clone_at_tag "https://github.com/romkatv/powerlevel10k.git" "$dir" "$(pin P10K_VERSION)" "powerlevel10k"

    if [[ -f "${HOME}/.zshrc" ]] && ! grep -q '^ZSH_THEME="powerlevel10k/powerlevel10k"' "${HOME}/.zshrc"; then
        sed_inplace 's|^ZSH_THEME="[^"]*"|ZSH_THEME="powerlevel10k/powerlevel10k"|' "${HOME}/.zshrc"
    fi

    # p10k's instant prompt must be the FIRST thing in .zshrc to work. Without
    # it the prompt waits for the whole rc file to finish. Previously this block
    # only existed if you'd run `p10k configure` by hand, so a fresh machine
    # silently lost the fast prompt.
    setup_p10k_instant_prompt

    if [[ -f "${SCRIPT_DIR}/p10k.zsh" ]]; then
        run cp "${SCRIPT_DIR}/p10k.zsh" "${HOME}/.p10k.zsh"
        success "p10k.zsh installed"
    else
        manual "Run 'p10k configure' to set up your prompt"
    fi

    add_line '[[ ! -f ~/.p10k.zsh ]] || source ~/.p10k.zsh' "${HOME}/.zshrc"
}

setup_p10k_instant_prompt() {
    local zshrc="${HOME}/.zshrc"
    [[ -f "$zshrc" ]] || touch "$zshrc"
    if grep -qF 'p10k-instant-prompt' "$zshrc" 2>/dev/null; then
        return 0
    fi
    dry_skip "would prepend p10k instant-prompt block to $zshrc" && return 0
    local tmp
    tmp=$(mktemp "$WORK/tmp.XXXXXX")
    cat > "$tmp" <<'IP_EOF'
# Enable Powerlevel10k instant prompt. Should stay close to the top of ~/.zshrc.
# Initialization code that may require console input (password prompts, [y/n]
# confirmations, etc.) must go above this block; everything else may go below.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

IP_EOF
    cat "$zshrc" >> "$tmp"
    mv "$tmp" "$zshrc"
    success "p10k instant-prompt block prepended to .zshrc"
}

install_zsh_plugins() {
    info "=== zsh plugins ==="
    local custom="${ZSH_CUSTOM:-$HOME/.oh-my-zsh/custom}/plugins"

    clone_at_tag "https://github.com/zsh-users/zsh-syntax-highlighting.git" \
        "$custom/zsh-syntax-highlighting" "$(pin ZSH_SYNTAX_HIGHLIGHTING_VERSION)" "zsh-syntax-highlighting"
    clone_at_tag "https://github.com/zsh-users/zsh-autosuggestions.git" \
        "$custom/zsh-autosuggestions" "$(pin ZSH_AUTOSUGGESTIONS_VERSION)" "zsh-autosuggestions"

    if [[ -f "${HOME}/.zshrc" ]]; then
        local plugin
        for plugin in zsh-syntax-highlighting zsh-autosuggestions; do
            grep -q "$plugin" "${HOME}/.zshrc" \
                || sed_inplace "s/^plugins=(\(..*\))/plugins=(\1 $plugin)/" "${HOME}/.zshrc"
        done
    fi
}

# -----------------------------------------------------------------------------
# CLI Tools — binary releases, all versions from versions.lock
# -----------------------------------------------------------------------------

install_bash() {
    info "=== bash ==="
    # macOS ships with bash 3.2 (GPL licensing); upgrade to bash 5 via brew
    if [[ "$OS" != "macos" ]]; then success "bash — skipped (Linux)"; return 0; fi
    local current_version major
    current_version=$(bash --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    major="${current_version%%.*}"
    if [[ "$major" -ge 5 ]]; then
        success "bash already at version $current_version"
        return 0
    fi
    brew_ensure bash
    success "bash upgraded"
}

install_fzf() {
    info "=== fzf ==="
    local tag; tag=$(pin FZF_VERSION)

    # fzf is cloned (not just downloaded) because its repo ships the completion
    # and key-binding shell scripts; the binary comes from its own installer.
    clone_at_tag "https://github.com/junegunn/fzf.git" "${HOME}/.fzf" "$tag" "fzf"

    if ! at_pinned_version "fzf" "$tag" "$(installed_version fzf)"; then
        run "${HOME}/.fzf/install" --bin
        success "fzf ${tag} binary installed"
    fi

    if $DRY_RUN; then
        info "[dry-run] would symlink ${HOME}/.fzf/bin/fzf -> $LOCAL_BIN/fzf"
    else
        ln -sf "${HOME}/.fzf/bin/fzf" "$LOCAL_BIN/fzf"
    fi

    # Remove legacy fzf shell integration lines (replaced by explicit functions in setup_zsh_functions)
    if grep -qE '\[ -f ~/\.fzf\.zsh \]|eval "\$\(fzf --zsh\)"' "${HOME}/.zshrc" 2>/dev/null; then
        sed_inplace '/\[ -f ~\/\.fzf\.zsh \]/d; /eval "\$(fzf --zsh)"/d' "${HOME}/.zshrc"
    fi
}

install_neovim() {
    info "=== neovim ==="

    local tag url
    tag=$(pin NVIM_VERSION)

    at_pinned_version "neovim" "$tag" "$(installed_version nvim)" && return 0

    url="https://github.com/neovim/neovim/releases/download/${tag}/nvim-$(by_os macos linux)-${ARCH}.tar.gz"

    dry_skip "would download and install neovim ${tag} from $url" && return 0

    local tmpdir; tmpdir=$(mktemp -d "$WORK/dir.XXXXXX")
    curl -fsSL "$url" -o "$tmpdir/nvim.tar.gz"
    tar -xzf "$tmpdir/nvim.tar.gz" -C "$tmpdir"

    local nvim_dir
    nvim_dir=$(find "$tmpdir" -maxdepth 1 -type d -name "nvim*" | head -1)
    mkdir -p "${HOME}/.local"
    rm -rf "${HOME}/.local/nvim"
    mv "$nvim_dir" "${HOME}/.local/nvim"
    ln -sf "${HOME}/.local/nvim/bin/nvim" "$LOCAL_BIN/nvim"
    rm -rf "$tmpdir"
    success "neovim ${tag} installed"
}

install_ripgrep() {
    install_release rg RIPGREP_VERSION \
        "https://github.com/BurntSushi/ripgrep/releases/download/{tag}/ripgrep-{ver}-{target}.tar.gz"
}

install_fd() {
    install_release fd FD_VERSION \
        "https://github.com/sharkdp/fd/releases/download/{tag}/fd-{tag}-{target}.tar.gz"
}

install_bat() {
    install_release bat BAT_VERSION \
        "https://github.com/sharkdp/bat/releases/download/{tag}/bat-{tag}-{target}.tar.gz"
}

install_eza() {
    if [[ "$OS" == "macos" ]]; then
        info "=== eza ==="
        local tag; tag=$(pin EZA_VERSION)
        # eza publishes no macOS binaries, so brew is the only option. brew
        # tracks its own formula version, which may differ from the pinned tag —
        # report what brew actually has rather than echoing the pin back.
        if command_exists eza && brew list eza &>/dev/null; then
            success "eza $(eza --version 2>/dev/null | grep -oE 'v[0-9.]+' | head -1) — via brew (pin ${tag} is advisory on macOS)"
            return 0
        fi
        brew_ensure eza
        success "eza installed via brew"
        return 0
    fi

    # Linux: x86_64 has a musl build; aarch64 only has gnu
    install_release eza EZA_VERSION \
        "https://github.com/eza-community/eza/releases/download/{tag}/eza_$(by_arch x86_64-unknown-linux-musl aarch64-unknown-linux-gnu).tar.gz"
}

install_jq() {
    install_release jq JQ_VERSION \
        "https://github.com/jqlang/jq/releases/download/{tag}/jq-$(by_os macos linux)-$(by_arch amd64 arm64)"
}

install_yq() {
    install_release yq YQ_VERSION \
        "https://github.com/mikefarah/yq/releases/download/{tag}/yq_$(by_os darwin linux)_$(by_arch amd64 arm64)"
}

install_k9s() {
    install_release k9s K9S_VERSION \
        "https://github.com/derailed/k9s/releases/download/{tag}/k9s_$(by_os Darwin Linux)_$(by_arch amd64 arm64).tar.gz"
}

install_lazygit() {
    # Primary git UI (nvim: <leader>gg). Handles interactive rebase, conflict
    # resolution, stashes, cherry-pick and amend far better than any nvim plugin.
    install_release lazygit LAZYGIT_VERSION \
        "https://github.com/jesseduffield/lazygit/releases/download/{tag}/lazygit_{ver}_$(by_os Darwin Linux)_$(by_arch x86_64 arm64).tar.gz"
}

install_delta() {
    # Syntax-highlighted git diffs in the terminal; configured as git's pager
    # in git/gitconfig and reused by fzf-lua's git previewers.
    install_release delta DELTA_VERSION \
        "https://github.com/dandavison/delta/releases/download/{tag}/delta-{tag}-{target}.tar.gz"
}

install_postgres_client() {
    info "=== postgres client (psql) ==="
    # Required by vim-dadbod for the <leader>D database UI. Client only — this
    # does not install or run a Postgres server.
    if command_exists psql; then
        success "psql already installed ($(psql --version 2>/dev/null))"
        return 0
    fi
    case "$OS" in
        macos)
            # libpq is keg-only: it ships psql but is not symlinked into PATH.
            if $DRY_RUN; then
                info "[dry-run] would run: brew install libpq and symlink psql"
            else
                brew install libpq
                local pq; pq="$(brew --prefix libpq 2>/dev/null)"
                if [[ -x "$pq/bin/psql" ]]; then
                    ln -sf "$pq/bin/psql" "$LOCAL_BIN/psql"
                    ln -sf "$pq/bin/pg_dump" "$LOCAL_BIN/pg_dump" 2>/dev/null || true
                    success "psql installed (libpq, symlinked into ~/.local/bin)"
                else
                    warn "libpq installed but psql not found at $pq/bin/psql"
                fi
            fi
            ;;
        debian) pkg_install "postgresql-client" ;;
        fedora) pkg_install "postgresql" ;;
        arch)   pkg_install "postgresql-libs" ;;
        *)      manual "Install a postgres client (psql) for the nvim database UI" ;;
    esac
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
    clone_at_tag "https://github.com/tmux-plugins/tpm.git" \
        "${HOME}/.tmux/plugins/tpm" "$(pin TPM_VERSION)" "tpm"
}

# -----------------------------------------------------------------------------
# Language Toolchains & Version Managers
# -----------------------------------------------------------------------------

install_rust() {
    info "=== Rust ==="
    # rustup itself is the pinning mechanism for Rust (rust-toolchain.toml per
    # project), so the toolchain is not pinned here — only tree-sitter-cli below.
    if [[ -f "${HOME}/.cargo/bin/cargo" ]]; then
        success "Rust already installed"
    elif $DRY_RUN; then
        info "[dry-run] would install Rust via rustup"
    else
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
        success "Rust installed"
    fi
    # Always ensure cargo env is sourced — rustup uses --no-modify-path so won't add it itself
    add_line '. "$HOME/.cargo/env"' "${HOME}/.zshrc"
}

install_tree_sitter_cli() {
    info "=== tree-sitter-cli ==="
    local cargo="${HOME}/.cargo/bin/cargo" tag
    tag=$(pin TREE_SITTER_CLI_VERSION)
    # Upstream tags releases as "v0.27.0" but `cargo install --version` wants a
    # bare semver, so accept either form in versions.lock.
    tag="${tag#v}"

    if [[ ! -f "$cargo" ]]; then
        warn "cargo not found — skipping tree-sitter-cli (Rust must be installed first)"
        return 0
    fi

    # nvim-treesitter's `main` branch compiles parsers with this CLI, so its
    # version affects whether parsers build. Pin it and use --locked so the
    # crate's own dependency lockfile is respected.
    local installed
    installed=$("$cargo" install --list 2>/dev/null | sed -n 's/^tree-sitter-cli v\([0-9.]*\).*/\1/p' | head -1)
    if [[ "$installed" == "$tag" ]]; then
        success "tree-sitter-cli ${tag} — pinned, up to date"
    else
        info "Installing tree-sitter-cli ${tag} (was: ${installed:-none}) — this compiles from source and takes a few minutes"
        run "$cargo" install tree-sitter-cli --version "$tag" --locked --force
        success "tree-sitter-cli ${tag} installed"
    fi

    # Symlink into LOCAL_BIN so it's available before cargo env is sourced in new shells
    if $DRY_RUN; then
        info "[dry-run] would symlink ${HOME}/.cargo/bin/tree-sitter -> $LOCAL_BIN/tree-sitter"
    else
        ln -sf "${HOME}/.cargo/bin/tree-sitter" "$LOCAL_BIN/tree-sitter"
    fi
}

# The managed ~/.zshrc blocks for the version managers. A function rather than
# inline heredocs so `./setup.sh --print-block <tool>` hands scripts/verify.sh
# exactly what a fresh machine gets; it used to scrape this file's heredocs by
# their literal text, indentation included, and broke on any refactor.
zshrc_block() {
    case "$1" in
        nvm)
            cat <<'BLOCK_EOF'
# nvm (default Node on PATH eagerly; nvm itself lazy)
export NVM_DIR="$HOME/.nvm"
# Sourcing nvm.sh costs ~200ms on every shell start, and for anything that is
# not an interactive shell all it achieves is putting the selected Node on PATH.
# Resolve that directory here instead — alias file reads and a glob, no forks —
# so processes that never source an rc file (nvim's language servers, debug
# adapters, build scripts) see the same node this shell does. Previously they
# did not: node was reachable only by calling a shell function.
if [[ -d $NVM_DIR/versions/node ]]; then
    # Follow alias indirection: default -> lts/jod -> 22.22.0. Bounded, because
    # a corrupt alias file could otherwise point at itself.
    _nvm_ref=default
    for _nvm_i in 1 2 3 4 5; do
        [[ -r $NVM_DIR/alias/$_nvm_ref ]] || break
        read -r _nvm_ref < "$NVM_DIR/alias/$_nvm_ref"
    done
    # Numeric glob sort (the `n` qualifier) orders v24.6.0 before v24.14.1.
    _nvm_bin=($NVM_DIR/versions/node/v${_nvm_ref#v}*/bin(/Nn))
    (( $#_nvm_bin )) || _nvm_bin=($NVM_DIR/versions/node/v*/bin(/Nn))
    (( $#_nvm_bin )) && export PATH="${_nvm_bin[-1]}:$PATH"
    unset _nvm_ref _nvm_bin _nvm_i
fi
# `nvm` itself still needs the full script, so load it on first use. The stub
# unsets itself *before* sourcing anything: if the source fails, the call falls
# through to PATH rather than re-entering this function forever. An earlier
# version delegated the unset to a shared `_nvm_lazy_load` helper, which made
# every stub a fork bomb in any shell where that helper did not survive.
nvm() {
    unset -f nvm 2>/dev/null
    [[ -s $NVM_DIR/nvm.sh ]] && source "$NVM_DIR/nvm.sh"
    [[ -s $NVM_DIR/bash_completion ]] && source "$NVM_DIR/bash_completion"
    nvm "$@"
}
BLOCK_EOF
            ;;
        pyenv) shim_manager_block pyenv PYENV_ROOT ;;
        goenv) shim_manager_block goenv GOENV_ROOT "export GOENV_PATH_ORDER=front" ;;
        *)
            error "no managed block for '$1' (expected nvm, pyenv or goenv)"
            return 1
            ;;
    esac
}

# pyenv and goenv work identically, so they share one block: <tool> <ROOT var>
# [extra line]. Placeholders, not an unquoted heredoc, so the shell code below
# reads exactly as it lands in ~/.zshrc.
shim_manager_block() {
    local tool="$1" root="$2" extra="${3:-}"
    sed -e "s/@TOOL@/${tool}/g" -e "s/@ROOT@/${root}/g" <<'BLOCK_EOF' | awk -v x="$extra" '$0 == "@EXTRA@" { if (x != "") print x; next } { print }'
# @TOOL@ (shims on PATH eagerly; shell integration lazy)
export @ROOT@="$HOME/.@TOOL@"
@EXTRA@
# `@TOOL@ init -` forks @TOOL@ and evals its output on every shell start. For
# anything that is not an interactive shell, all that output does is prepend
# these two directories — so prepend them directly. This also fixes a real
# correctness bug: with the shims reachable only through a shell function,
# processes spawned without an rc file (nvim's language servers, debug
# adapters, build tooling) silently got the system interpreter instead of the
# @TOOL@-selected one.
[[ -d $@ROOT@/bin ]] && export PATH="$@ROOT@/bin:$PATH"
[[ -d $@ROOT@/shims ]] && export PATH="$@ROOT@/shims:$PATH"
# Only `@TOOL@ shell` needs the shell function, so defer the full init to first
# use of `@TOOL@` itself. The stub unsets itself *before* running init: if init
# fails or @TOOL@ is missing, the call falls through to PATH rather than
# re-entering this function forever. An earlier version put the unset in a
# shared `_@TOOL@_lazy_load` helper, which turned python, go and friends into
# fork bombs in any shell where that helper did not survive.
@TOOL@() {
    unset -f @TOOL@ 2>/dev/null
    eval "$(command @TOOL@ init -)"
    @TOOL@ "$@"
}
BLOCK_EOF
}

install_nvm() {
    info "=== nvm ==="
    local tag; tag=$(pin NVM_VERSION)
    if [[ -d "${HOME}/.nvm" ]]; then
        success "nvm already installed (pinned ${tag})"
    elif $DRY_RUN; then
        info "[dry-run] would install nvm ${tag}"
    else
        curl -o- "https://raw.githubusercontent.com/nvm-sh/nvm/${tag}/install.sh" | bash
        success "nvm ${tag} installed"
    fi

    # nvm's own installer appends an eager init block to .zshrc when $SHELL=zsh;
    # migrate_legacy_zshrc removes it, since it both costs ~200ms per shell and
    # fights the managed block below. The block itself splits the difference:
    # PATH is set eagerly (cheap, and visible to non-shell consumers), while the
    # nvm function is deferred to first use.
    add_block "nvm" "${HOME}/.zshrc" < <(zshrc_block nvm)
}

install_pyenv() {
    info "=== pyenv ==="
    # Cloned at a pinned tag rather than installed via `curl pyenv.run | bash`,
    # which always fetches master and is one of the ways this setup used to drift.
    clone_at_tag "https://github.com/pyenv/pyenv.git" "${HOME}/.pyenv" "$(pin PYENV_VERSION)" "pyenv"

    # PATH eagerly, `pyenv init -` lazily — see the block's own comments for why
    # the shims have to be on PATH rather than behind a shell function.
    add_block "pyenv" "${HOME}/.zshrc" < <(zshrc_block pyenv)

    # pyenv builds Python from source — surface the required packages per distro
    case "$OS" in
        debian)
            manual "pyenv Python build deps (Debian/Ubuntu): sudo apt-get install -y build-essential libssl-dev zlib1g-dev libbz2-dev libreadline-dev libsqlite3-dev libncursesw5-dev xz-utils tk-dev libxml2-dev libxmlsec1-dev libffi-dev liblzma-dev" ;;
        fedora)
            manual "pyenv Python build deps (Fedora/RHEL/yum): sudo dnf install -y gcc make patch zlib-devel bzip2 bzip2-devel readline-devel sqlite sqlite-devel openssl-devel tk-devel libffi-devel xz-devel libuuid-devel gdbm-libs libnsl2" ;;
        arch)
            manual "pyenv Python build deps (Arch): sudo pacman -S --needed base-devel openssl zlib xz tk" ;;
    esac
}

install_goenv() {
    info "=== goenv ==="
    clone_at_tag "https://github.com/go-nv/goenv.git" "${HOME}/.goenv" "$(pin GOENV_VERSION)" "goenv"

    # PATH eagerly, `goenv init -` lazily — same block as pyenv's.
    add_block "goenv" "${HOME}/.zshrc" < <(zshrc_block goenv)

    # goenv downloads pre-built Go binaries but needs gcc/make for cgo-based tooling
    case "$OS" in
        debian)
            manual "goenv build deps (Debian/Ubuntu): sudo apt-get install -y build-essential" ;;
        fedora)
            manual "goenv build deps (Fedora/RHEL/yum): sudo dnf install -y gcc make" ;;
        arch)
            manual "goenv build deps (Arch): sudo pacman -S --needed base-devel" ;;
    esac
}

install_sdkman() {
    info "=== SDKMAN ==="
    if [[ -d "${HOME}/.sdkman" ]]; then
        success "SDKMAN already installed"
    elif $DRY_RUN; then
        info "[dry-run] would install SDKMAN"
    else
        command_exists zip  || pkg_install "zip"
        command_exists unzip || pkg_install "unzip"
        local sdkman_script
        sdkman_script=$(mktemp "$WORK/tmp.XXXXXX")
        curl -s "https://get.sdkman.io" -o "$sdkman_script"
        bash "$sdkman_script"
        rm -f "$sdkman_script"
        success "SDKMAN installed"
    fi

    # SDKMAN self-updates on every shell start by default, which silently moves
    # your JVM tooling. Turn that off so `sdk selfupdate` becomes deliberate —
    # the same stability contract as versions.lock. Java versions themselves are
    # pinned per-project by .sdkmanrc.
    local sdk_cfg="${HOME}/.sdkman/etc/config"
    if [[ -f "$sdk_cfg" ]]; then
        if grep -q '^sdkman_auto_selfupdate=false' "$sdk_cfg"; then
            success "SDKMAN auto-selfupdate already disabled"
        else
            sed_inplace 's/^sdkman_auto_selfupdate=.*/sdkman_auto_selfupdate=false/' "$sdk_cfg"
            success "SDKMAN auto-selfupdate disabled (run 'sdk selfupdate' manually)"
        fi
    fi

    # SDKMAN's installer may have already written its init block to .zshrc;
    # check for the sourced script rather than our marker to avoid duplicates.
    # Deliberately NOT lazy-loaded like nvm/pyenv/goenv above: SDKMAN manages
    # JAVA_HOME/PATH for java/javac/mvn/gradle, and project wrapper scripts
    # (./mvnw, ./gradlew) invoke those directly rather than through a shell
    # function, so they wouldn't trigger a lazy stub. Given heavy day-to-day
    # Java use, deferring this risks JAVA_HOME being unset in a fresh shell.
    add_block "sdkman" "${HOME}/.zshrc" <<'BLOCK_EOF'
# SDKMAN
export SDKMAN_DIR="$HOME/.sdkman"
[[ -s "$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "$HOME/.sdkman/bin/sdkman-init.sh"
BLOCK_EOF
}

install_docker() {
    info "=== Docker ==="
    if command_exists docker; then
        success "Docker already installed"
        return 0
    fi

    if $DRY_RUN && [[ "$OS" != "macos" ]]; then
        info "[dry-run] would install Docker via ${OS}'s package manager (multiple sudo steps: repo setup, package install, enable service, add \$USER to docker group)"
        return 0
    fi

    case "$OS" in
        macos)
            manual "Install Docker Desktop: brew install --cask docker"
            ;;
        debian)
            local distro_id
            distro_id=$(. /etc/os-release && echo "${ID}")
            sudo apt-get install -y ca-certificates curl
            sudo install -m 0755 -d /etc/apt/keyrings
            sudo curl -fsSL "https://download.docker.com/linux/${distro_id}/gpg" \
                -o /etc/apt/keyrings/docker.asc
            sudo chmod a+r /etc/apt/keyrings/docker.asc
            echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.asc] \
https://download.docker.com/linux/${distro_id} \
$(. /etc/os-release && echo "${VERSION_CODENAME}") stable" \
                | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
            sudo apt-get update -qq
            sudo apt-get install -y docker-ce docker-ce-cli containerd.io \
                docker-buildx-plugin docker-compose-plugin
            sudo usermod -aG docker "$USER"
            success "Docker installed — re-login for group membership to take effect"
            ;;
        fedora)
            sudo dnf -y install dnf-plugins-core
            sudo dnf config-manager --add-repo \
                https://download.docker.com/linux/fedora/docker-ce.repo
            sudo dnf install -y docker-ce docker-ce-cli containerd.io \
                docker-buildx-plugin docker-compose-plugin
            sudo systemctl enable --now docker
            sudo usermod -aG docker "$USER"
            success "Docker installed — re-login for group membership to take effect"
            ;;
        arch)
            sudo pacman -S --noconfirm docker docker-compose
            sudo systemctl enable --now docker
            sudo usermod -aG docker "$USER"
            success "Docker installed — re-login for group membership to take effect"
            ;;
        *)
            manual "Install Docker manually: https://docs.docker.com/engine/install/"
            ;;
    esac
}

install_tfenv() {
    info "=== tfenv ==="
    clone_at_tag "https://github.com/tfutils/tfenv.git" "${HOME}/.tfenv" "$(pin TFENV_VERSION)" "tfenv"

    dry_skip "would symlink tfenv binaries into $LOCAL_BIN" && return 0

    local bin dest
    for bin in "${HOME}/.tfenv/bin/"*; do
        dest="$LOCAL_BIN/$(basename "$bin")"
        ln -sf "$bin" "$dest"
    done
    success "tfenv binaries linked"
}

# -----------------------------------------------------------------------------
# Configuration
# -----------------------------------------------------------------------------

# Remove shell-init blocks written by older versions of this script.
#
# add_block now writes delimited, fully regenerated regions. Older versions
# appended un-delimited blocks under plain headers and only checked whether the
# header was present, which caused two problems on a long-lived .zshrc:
#
#   1. A legacy eager `eval "$(goenv init -)"` block kept the "# goenv" marker
#      occupied, so the lazy stub that puts goenv on PATH was never installed.
#      Symptom: `command not found: goenv` on every terminal start.
#   2. Any block whose header already existed was skipped forever, so later
#      improvements to the aliases/functions never reached this machine.
#
#   3. nvm's *own* installer appends an un-delimited, header-less trio that
#      sources nvm.sh on every shell start. It survived every previous pass
#      because it has no header to match, so the managed nvm block was loading
#      on top of an already-eager nvm -- paying the ~200ms this setup exists to
#      avoid. It is matched by its exact three lines instead.
#
# Blocks are removed from their header to the following blank line. Every block
# written by this script is a single paragraph, so that boundary is exact. The
# two multi-paragraph blocks (aliases, functions) are reported rather than
# deleted: the managed region is appended afterwards and later definitions win
# in zsh, so a stale copy is cosmetic, and guessing its extent risks eating
# hand-written config.
migrate_legacy_zshrc() {
    info "=== migrating legacy .zshrc blocks ==="
    local zshrc="${HOME}/.zshrc"
    [[ -f "$zshrc" ]] || return 0

    # Single-paragraph blocks that are safe to remove wholesale.
    local -a legacy_headers=(
        "# nvm"
        "# nvm (lazy-loaded on first use)"
        "# pyenv"
        "# pyenv (lazy-loaded on first use)"
        "# goenv"
        "# goenv (lazy-loaded on first use)"
        "# SDKMAN"
        "# tmux auto-attach"
        "# Custom keybindings"
    )

    # Detection runs against the un-managed remainder only. Three of the
    # headers above -- "# SDKMAN", "# tmux auto-attach", "# Custom keybindings"
    # -- are byte-identical to the first content line of blocks add_block
    # writes, so grepping the whole file matched this script's own output and
    # pinned `found` at 1 forever. The awk below was always managed-aware; the
    # detection was not. The cost was a backup directory, a full awk rewrite
    # and two perl passes over ~/.zshrc on every single run, plus a [MANUAL]
    # step telling the user to hand-delete the installer's own blocks. 53
    # backup directories had accumulated here before this was spotted.
    local unmanaged
    unmanaged=$(mktemp "$WORK/tmp.XXXXXX")
    unmanaged_region "$zshrc" > "$unmanaged"

    local found=0 h
    for h in "${legacy_headers[@]}"; do
        if grep -qxF "$h" "$unmanaged"; then
            found=1
            break
        fi
    done

    # `grep -c` prints "0" AND exits 1 when nothing matches, so the previous
    # `|| echo 0` appended a *second* line: the value became "0\n0" and the
    # numeric test below threw a syntax error rather than comparing. `|| true`
    # keeps grep's own "0" and swallows only the exit status.
    local sdk_count nvm_eager
    sdk_count=$(grep -cF 'sdkman-init.sh' "$unmanaged" || true)
    nvm_eager=$(grep -c '^\[ -s "\$NVM_DIR/nvm.sh" \]' "$unmanaged" || true)
    rm -f "$unmanaged"

    if [[ "$sdk_count" -le 1 && "$nvm_eager" -eq 0 && $found -eq 0 ]]; then
        success "no legacy blocks to migrate"
        return 0
    fi

    dry_skip "would remove legacy un-delimited blocks from $zshrc" && return 0

    backup_if_exists "$zshrc"

    # Delete each legacy header and the contiguous non-blank lines after it.
    # Never touches a managed region: those start with "# >>> terminal-setup:".
    local hdr_file
    hdr_file=$(mktemp "$WORK/tmp.XXXXXX")
    printf '%s\n' "${legacy_headers[@]}" > "$hdr_file"
    local tmp
    tmp=$(mktemp "$WORK/tmp.XXXXXX")
    # One pass: drop legacy blocks, drop un-managed copies of SDKMAN's init (its
    # installer writes one, older versions of this script appended another, and
    # the managed sdkman block written later in this run is the one that counts),
    # and collapse the runs of blank lines left behind. This used to be three
    # passes, two of them perl -- and the perl dedupe kept the *first* copy
    # file-wide, so when the installer's copy came first it deleted the managed
    # block's lines instead.
    awk -v hdrfile="$hdr_file" '
        BEGIN {
            while ((getline h < hdrfile) > 0) { hdr[h] = 1 }
            close(hdrfile)
            sdk1 = "export SDKMAN_DIR=\"$HOME/.sdkman\""
            sdk2 = "[[ -s \"$HOME/.sdkman/bin/sdkman-init.sh\" ]] && source \"$HOME/.sdkman/bin/sdkman-init.sh\""
        }
        function emit(line) {
            if (line == "" && blank) return
            blank = (line == "")
            print line
        }
        # A held SDKMAN export line is resolved by the line after it.
        held {
            held = 0
            if ($0 == sdk2) next
            emit(sdk1)
        }
        # Inside a managed region: always keep, never treat as legacy.
        /^# >>> terminal-setup:/ { managed = 1; emit($0); next }
        /^# <<< terminal-setup:/ { managed = 0; emit($0); next }
        managed { emit($0); next }

        skipping {
            if ($0 == "") { skipping = 0 }   # blank line ends the legacy block
            next
        }
        ($0 in hdr) { skipping = 1; next }
        $0 == sdk1 { held = 1; next }

        # The nvm installer writes these three lines with no header. Matched
        # exactly so nothing else can be caught by them; the managed nvm block
        # re-exports NVM_DIR to the same value, so dropping it loses nothing.
        $0 == "export NVM_DIR=\"$HOME/.nvm\"" { next }
        /^\[ -s "\$NVM_DIR\/nvm\.sh" \]/ { next }
        /^\[ -s "\$NVM_DIR\/bash_completion" \]/ { next }
        { emit($0) }
        END { if (held) emit(sdk1) }
    ' "$zshrc" > "$tmp"
    mv "$tmp" "$zshrc"

    success "legacy un-delimited blocks removed (backed up to $BACKUP_DIR)"

    # Report, don't delete, the multi-paragraph ones -- again against the
    # un-managed remainder, since "# Custom aliases" and "# Custom shell
    # functions" are also the first lines of the blocks written above.
    local leftover="" rest
    rest=$(mktemp "$WORK/tmp.XXXXXX")
    unmanaged_region "$zshrc" > "$rest"
    grep -qxF "# Custom aliases" "$rest" && leftover="${leftover} '# Custom aliases'"
    grep -qxF "# Custom shell functions" "$rest" && leftover="${leftover} '# Custom shell functions'"
    rm -f "$rest"
    if [[ -n "$leftover" ]]; then
        manual "Old${leftover} block(s) remain in ~/.zshrc. The managed versions are appended after them and take precedence, so this is cosmetic — delete the old ones by hand when convenient."
    fi
}

setup_local_bin() {
    info "=== local bin ==="
    # Always remove then re-append so ~/.local/bin ends up at the bottom of
    # .zshrc — sourced last means it prepends last, giving it priority over
    # Homebrew and any other PATH block written earlier.
    local line='export PATH="$HOME/.local/bin:$PATH"' zshrc="${HOME}/.zshrc"
    dry_skip "would ensure $LOCAL_BIN exists and re-append its PATH line to $zshrc" && return 0
    touch "$zshrc"
    # grep exits 1 when it filters out every line or the file is empty — fine,
    # the move must still happen. Anything else is a real error, and moving its
    # partial output over .zshrc would truncate it; `|| true` used to allow that.
    local tmp; tmp=$(mktemp "$WORK/tmp.XXXXXX")
    grep -vF "$line" "$zshrc" > "$tmp" || [[ $? -eq 1 ]]
    mv "$tmp" "$zshrc"
    echo "$line" >> "$zshrc"
    success "$LOCAL_BIN on PATH (last, so it takes precedence)"
}

setup_zsh_env() {
    info "=== zsh environment ==="
    add_line 'export EDITOR="nvim"' "${HOME}/.zshrc"
    add_line 'export VISUAL="nvim"' "${HOME}/.zshrc"
    # bat powers fzf/delta previews and `cat`; match the nvim colourscheme.
    add_line 'export BAT_THEME="Catppuccin Mocha"' "${HOME}/.zshrc"
    success "zsh environment configured"
}

setup_zsh_keybindings() {
    info "=== zsh keybindings ==="
    add_block "keybindings" "${HOME}/.zshrc" <<'BLOCK_EOF'
# Custom keybindings
bindkey -e
bindkey '^B' backward-kill-line
bindkey '^F' kill-line
bindkey '^P' forward-word
bindkey '^O' backward-word
bindkey '^Y' clear-screen
BLOCK_EOF
    success "Keybindings configured"
}

setup_zsh_aliases() {
    info "=== zsh aliases ==="
    add_block "aliases" "${HOME}/.zshrc" <<'BLOCK_EOF'
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

# git — lazygit is the primary UI (same tool nvim's <leader>gg opens)
alias lg='lazygit'
alias gs='git status'
alias gd='git diff'
alias gds='git diff --staged'
alias gl="git log --graph --abbrev-commit --decorate --date=relative --format=format:'%C(bold blue)%h%C(reset) %C(bold green)(%ar)%C(reset) %C(white)%s%C(reset) %C(dim white)- %an%C(reset)%C(auto)%d%C(reset)' --all"
alias gco='git checkout'
alias gcb='git checkout -b'
alias gri='git rebase -i'
alias grc='git rebase --continue'
alias gra='git rebase --abort'

# neovim
alias v='nvim'
alias vi='nvim'
BLOCK_EOF
    success "Aliases configured"
}

setup_zsh_functions() {
    info "=== zsh functions ==="
    add_block "functions" "${HOME}/.zshrc" <<'BLOCK_EOF'
# Custom shell functions

# zsh refuses to define a function whose name is already an alias, and older
# versions of this setup shipped some of these as aliases (notably `nf`). A
# leftover alias aborts parsing of the rest of this block with
# "defining function based on alias", taking every later function with it.
# Clearing them first makes this block self-contained whatever precedes it.
unalias fh nf fcd fgb fkill frg fshow 2>/dev/null || true

# fh — fuzzy history search; selected command is loaded into the prompt for editing
fh() {
    print -z $(fc -ln 1 | fzf --tac --no-sort)
}

# nf — fuzzy find file and open in nvim; optional first arg scopes the search root
nf() {
    local root="${1:-.}"
    local file
    file=$(fd --type f --hidden --exclude .git . "$root" 2>/dev/null \
        | fzf --preview "bat --color=always --style=numbers --line-range=:500 {}")
    [[ -n "$file" ]] && nvim "$file"
}

# fcd — fuzzy cd; optional first arg scopes the search root (default: current dir)
fcd() {
    local root="${1:-.}"
    local dir
    dir=$(fd --type d --hidden --exclude .git . "$root" 2>/dev/null \
        | fzf --preview 'eza --tree --level=2 --icons {}')
    [[ -n "$dir" ]] && cd "$dir"
}

# fgb — fuzzy git branch checkout, newest-first with a commit preview
fgb() {
    local branch
    branch=$(git branch --all --sort=-committerdate 2>/dev/null | grep -v HEAD \
        | fzf --preview 'git log --oneline --graph --date=relative --color=always -20 $(sed "s|.*remotes/origin/||;s|^[* ]*||" <<< {})' \
        | sed 's|.*remotes/origin/||' | tr -d ' ')
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

# fshow — browse commits with a delta diff preview; enter copies the SHA
fshow() {
    git log --graph --color=always --date=relative \
        --format="%C(auto)%h %C(green)(%ar)%C(reset) %s %C(dim white)- %an%C(reset)" "$@" \
    | fzf --ansi --no-sort --reverse --tiebreak=index \
          --preview 'grep -o "[a-f0-9]\{7,\}" <<< {} | head -1 | xargs -I% git show --color=always % | delta' \
          --bind 'enter:execute(grep -o "[a-f0-9]\{7,\}" <<< {} | head -1 | xargs -I% git show % | less -R)'
}
BLOCK_EOF
    success "Shell functions configured"
}

setup_tmux_autoattach() {
    info "=== tmux auto-attach ==="
    add_block "tmux-autoattach" "${HOME}/.zshrc" <<'BLOCK_EOF'
# tmux auto-attach
if command -v tmux &>/dev/null && [ -z "$TMUX" ]; then
  tmux attach -t main 2>/dev/null || tmux new -s main
fi
BLOCK_EOF
    success "tmux auto-attach configured"
}

setup_gitconfig() {
    info "=== git config ==="
    local gitconfig="${HOME}/.gitconfig"
    local shared="${SCRIPT_DIR}/git/gitconfig"

    if [[ ! -f "$shared" ]]; then
        error "shared gitconfig not found: $shared"
        return 1
    fi

    # Included rather than copied, so edits to the repo take effect immediately
    # and your identity/credentials stay in ~/.gitconfig, out of version control.
    if git config --global --get-all include.path 2>/dev/null | grep -qxF "$shared"; then
        success "gitconfig include already present"
    elif $DRY_RUN; then
        info "[dry-run] would add include.path=$shared to $gitconfig"
    else
        backup_if_exists "$gitconfig"
        git config --global --add include.path "$shared"
        success "gitconfig included from $shared"
    fi

    if ! git config --global --get user.email >/dev/null 2>&1; then
        manual "Set your git identity: git config --global user.name 'Your Name' && git config --global user.email you@example.com"
    fi
}

setup_gitconfig_version() {
    info "=== git config (version-gated) ==="
    # This repo is shared between machines with different git versions — macOS
    # ships 2.50, Ubuntu 20.04 ships 2.24. Some settings are validated by value
    # rather than silently ignored, so a value the local git does not know makes
    # EVERY git command fail. The reported symptom was:
    #   error: unknown style 'zdiff3' given for 'merge.conflictstyle'
    # on a plain `git checkout`. So the version-dependent settings live here,
    # generated per machine, instead of in the shared committed gitconfig.
    local out="${SCRIPT_DIR}/git/gitconfig.local"
    local gv
    gv=$(git --version 2>/dev/null | sed -n 's/^git version \([0-9.]*\).*/\1/p')
    info "Detected git ${gv:-unknown}"

    local conflictstyle="diff3" notes=""
    if git_version_at_least 2.35; then
        conflictstyle="zdiff3"
    else
        notes="${notes}  ; merge.conflictstyle=zdiff3 needs git >= 2.35; using diff3\n"
    fi

    dry_skip "would write $out (conflictstyle=${conflictstyle})" && return 0

    {
        echo "; GENERATED by setup.sh for git ${gv:-unknown} — do not edit, not committed."
        echo "; Regenerate by re-running ./setup.sh. Included from git/gitconfig."
        echo ";"
        echo "; Only settings this git version actually supports are written here, so"
        echo "; the same repo works on macOS (git 2.50) and Ubuntu 20.04 (git 2.24)."
        echo ""
        echo "[merge]"
        echo "    ; Shows the common ancestor alongside both sides, so you can see what"
        echo "    ; each side changed rather than guessing between two variants."
        printf '%b' "$notes"
        echo "    conflictstyle = ${conflictstyle}"
        echo ""

        if git_version_at_least 2.38; then
            echo "[rebase]"
            echo "    updateRefs = true    ; stacked branches follow along on rebase"
            echo ""
        fi
        if git_version_at_least 2.37; then
            echo "[push]"
            echo "    autoSetupRemote = true   ; \`git push\` on a new branch just works"
            echo ""
            echo "[help]"
            echo "    autocorrect = prompt     ; \"git stauts\" offers to run status"
            echo ""
        fi
        if git_version_at_least 2.41; then
            echo "[fetch]"
            echo "    all = true"
            echo ""
        fi
        if git_version_at_least 2.28; then
            echo "[init]"
            echo "    defaultBranch = main"
            echo ""
        fi
    } > "$out"

    success "git/gitconfig.local generated for git ${gv} (conflictstyle=${conflictstyle})"

    # Fail loudly here rather than letting the user discover it on their next
    # checkout: prove the resulting config is actually readable by this git.
    if git config --global --get-all include.path >/dev/null 2>&1; then
        if ! git -C "$SCRIPT_DIR" status >/dev/null 2>&1; then
            error "git still errors after writing gitconfig.local — run: git -C $SCRIPT_DIR status"
        else
            success "git config verified: plain git commands succeed"
        fi
    fi
}

# Symlink a repo config into place, backing up whatever was there.
# Symlinked, not copied: edits to the repo take effect immediately, with no
# re-run of this script.
link_config() {
    local name="$1" source="$2" target="$3"
    if [[ ! -e "$source" ]]; then
        error "${name} config not found: $source"
        return 1
    fi
    if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
        success "${name} config symlink already correct"
        return 0
    fi
    backup_if_exists "$target"
    dry_skip "would symlink $target -> $source" && return 0
    rm -rf "$target"
    mkdir -p "$(dirname "$target")"
    ln -s "$source" "$target"
    success "${name} config symlinked: $target -> $source"
}

setup_nvim_config() {
    info "=== Neovim config ==="
    link_config "Neovim" "${SCRIPT_DIR}/nvim" "${HOME}/.config/nvim" || return 1

    # Write the pinned Mason registry snapshot where the nvim config reads it.
    # This is what freezes every LSP server, formatter, linter and DAP adapter.
    setup_mason_pin

    if $DRY_RUN; then
        info "[dry-run] would run: nvim --headless '+Lazy! restore'"
    elif command_exists nvim; then
        info "Restoring plugins from lock file..."
        nvim --headless "+Lazy! restore" +qa 2>/dev/null \
            || warn "Lazy restore had issues; open nvim to resolve"
        success "Lazy.nvim restore complete"
    else
        warn "nvim not in PATH yet; skipping Lazy restore (re-run setup after shell reload)"
    fi
}

setup_mason_pin() {
    # nvim/lua/mason-pin.lua is generated from versions.lock so the Lua config
    # never needs editing by hand and there is exactly one source of truth.
    local out="${SCRIPT_DIR}/nvim/lua/mason-pin.lua"
    local registry; registry=$(pin MASON_REGISTRY)

    if [[ -f "$out" ]] && grep -qF "$registry" "$out"; then
        success "Mason registry pin already at ${registry}"
        return 0
    fi
    dry_skip "would write Mason registry pin ${registry} to $out" && return 0
    cat > "$out" <<EOF
-- GENERATED by setup.sh from versions.lock — do not edit by hand.
-- Change MASON_REGISTRY in versions.lock (or run ./setup.sh --update) instead.
--
-- Pinning the registry snapshot freezes every LSP server, formatter, linter and
-- DAP adapter version. Without it, Mason silently upgrades all of them.
return {
    registry = "github:mason-org/mason-registry@${registry}",
}
EOF
    success "Mason registry pinned to ${registry}"
}

setup_clipboard_helper() {
    info "=== clipboard helper ==="
    # macOS uses pbcopy natively — no helper needed
    if [[ "$OS" == "macos" ]]; then success "clipboard — pbcopy (macOS native)"; return 0; fi

    # Install both clipboard backends: xclip (X11) and wl-clipboard (Wayland)
    command_exists xclip    || pkg_install "xclip"
    command_exists wl-copy  || pkg_install "wl-clipboard"

    dry_skip "would write clipboard helper to $LOCAL_BIN/tmux-clipboard" && return 0

    # Write a runtime-detection wrapper so tmux works on both X11 and Wayland
    cat > "$LOCAL_BIN/tmux-clipboard" <<'EOF'
#!/bin/sh
# Route clipboard writes to the correct backend at runtime.
# Buffer stdin first so we can choose the backend before consuming it.
buf=$(cat)
if [ -n "$WAYLAND_DISPLAY" ] && command -v wl-copy >/dev/null 2>&1; then
    printf '%s' "$buf" | wl-copy
elif [ -n "$DISPLAY" ] && command -v xclip >/dev/null 2>&1; then
    printf '%s' "$buf" | xclip -in -selection clipboard
else
    # Headless / SSH: emit OSC 52 so the host terminal receives the clipboard data
    encoded=$(printf '%s' "$buf" | base64 | tr -d '\n')
    printf '\033]52;c;%s\a' "$encoded"
fi
EOF
    chmod 755 "$LOCAL_BIN/tmux-clipboard"
    success "clipboard helper installed (Wayland + X11 + OSC 52)"
}

setup_tmux_config() {
    info "=== tmux config ==="
    # The old copy+sed approach meant repo changes were invisible until
    # setup.sh ran again; symlinked, they apply on the next `prefix + r`. The
    # pbcopy/tmux-clipboard choice lives inside tmux.conf as an if-shell.
    link_config "tmux" "${SCRIPT_DIR}/tmux/tmux.conf" "${HOME}/.tmux.conf" || return 1

    setup_tmux_plugin_pins

    local tpm_install="${HOME}/.tmux/plugins/tpm/bin/install_plugins"
    if $DRY_RUN; then
        info "[dry-run] would run tpm's install_plugins if available"
    elif [[ -x "$tpm_install" ]]; then
        "$tpm_install" >/dev/null 2>&1 || warn "tpm plugin install had issues"
        success "tmux plugins installed"
    else
        warn "tpm not ready; open tmux and press prefix+I to install plugins"
    fi
}

setup_tmux_plugin_pins() {
    # tmux.conf declares plugins with tpm's `repo#ref` syntax. Rewrite those
    # refs from versions.lock so tmux plugins are pinned by the same mechanism
    # as everything else, instead of tracking their default branches.
    local conf="${SCRIPT_DIR}/tmux/tmux.conf"
    local nav cat_tmux cpu
    nav=$(pin TMUX_NAVIGATOR_COMMIT)
    cat_tmux=$(pin CATPPUCCIN_TMUX_VERSION)
    cpu=$(pin TMUX_CPU_COMMIT)

    dry_skip "would pin tmux plugins in tmux.conf (navigator=${nav:0:12} catppuccin=${cat_tmux} cpu=${cpu:0:12})" && return 0

    sed_inplace "s|^set -g @plugin 'christoomey/vim-tmux-navigator.*|set -g @plugin 'christoomey/vim-tmux-navigator#${nav}'|" "$conf"
    sed_inplace "s|^set -g @plugin 'catppuccin/tmux.*|set -g @plugin 'catppuccin/tmux#${cat_tmux}'|" "$conf"
    sed_inplace "s|^set -g @plugin 'tmux-plugins/tmux-cpu.*|set -g @plugin 'tmux-plugins/tmux-cpu#${cpu}'|" "$conf"
    success "tmux plugins pinned from versions.lock"
}

# -----------------------------------------------------------------------------
# Prerequisite Check
# -----------------------------------------------------------------------------

check_prerequisites() {
    local missing=()

    command_exists git  || missing+=("git")
    command_exists curl || missing+=("curl")
    # `make` is no longer required: the only consumer was telescope-fzf-native,
    # which has been replaced by fzf-lua (pure Lua, shells out to the fzf binary).
    # It stays listed for pyenv/goenv native builds but is no longer fatal.
    command_exists make || warn "make not found — needed only to build Python via pyenv or cgo tooling"

    # Guard required: bash 3.2 (macOS /bin/bash) treats "${a[@]}" on an empty
    # array as unbound under `set -u`.
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing[*]}"
        echo ""
        echo "  Install them before running this script:"
        echo ""
        echo "  macOS:          xcode-select --install   (includes git, make, curl)"
        echo "  Debian/Ubuntu:  sudo apt-get install -y git curl build-essential"
        echo "  Fedora/RHEL:    sudo dnf install -y git curl make gcc"
        echo ""
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
    if [[ "$MODE" == "print-block" ]]; then
        zshrc_block "$PRINT_BLOCK"
        exit
    fi

    load_lockfile

    case "$MODE" in
        update) do_update; exit 0 ;;
        check)  do_check;  exit 0 ;;
    esac

    echo "============================================="
    echo "  Developer Environment Setup"
    echo "============================================="
    echo ""

    check_prerequisites

    info "OS: $OS | Arch: $ARCH"
    info "Versions: pinned by versions.lock (no network version resolution)"
    echo ""

    case "$OS" in
        macos)
            if command_exists brew; then
                :
            elif $DRY_RUN; then
                info "[dry-run] would install Homebrew"
            else
                /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
            fi
            # Ensure brew is on PATH for the rest of this run (only if it's actually installed)
            if [[ -f /opt/homebrew/bin/brew ]]; then
                eval "$(/opt/homebrew/bin/brew shellenv)"
            elif [[ -f /usr/local/bin/brew ]]; then
                eval "$(/usr/local/bin/brew shellenv)"
            fi
            # Add Homebrew bin to PATH permanently in .zshrc
            add_block "homebrew" "${HOME}/.zshrc" <<'BLOCK_EOF'
# Homebrew — Apple Silicon uses /opt/homebrew, Intel uses /usr/local
[[ -d /opt/homebrew/bin ]] && export PATH="/opt/homebrew/bin:/opt/homebrew/sbin:$PATH"
[[ -d /usr/local/bin ]] && export PATH="/usr/local/bin:/usr/local/sbin:$PATH"
BLOCK_EOF
            # tfenv requires GNU grep; macOS ships with BSD grep
            command_exists brew && brew_ensure grep
            # Add GNU grep to PATH so it takes precedence over BSD grep
            add_line 'export PATH="$(brew --prefix)/opt/grep/libexec/gnubin:$PATH"' "${HOME}/.zshrc"
            ;;
        debian)
            if $DRY_RUN; then
                info "[dry-run] would run: sudo apt-get update && apt-get install -y build-essential"
            else
                sudo apt-get update -qq || warn "apt-get update had errors — check /etc/apt/sources.list.d/ for misconfigured repos"
                sudo apt-get install -y --no-install-recommends build-essential
            fi
            ;;
        fedora)
            if $DRY_RUN; then
                info "[dry-run] would run: sudo dnf install -y make gcc"
            else
                sudo dnf check-update -q || true
                sudo dnf install -y make gcc
            fi
            ;;
    esac

    echo ""
    # Must run before any managed block is written, so the legacy removal can
    # never touch freshly generated content.
    migrate_legacy_zshrc
    warn_stale_backups

    # Every installer writes into LOCAL_BIN, so create it once here.
    $DRY_RUN || mkdir -p "$LOCAL_BIN"

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
    install_tree_sitter_cli
    install_ripgrep
    install_fd
    install_bat
    install_eza
    install_jq
    install_yq
    install_k9s
    install_lazygit
    install_delta
    install_postgres_client
    install_nvm
    install_pyenv
    install_goenv
    install_sdkman
    install_tfenv
    install_docker

    echo ""
    info "--- Configuring dotfiles ---"
    setup_zsh_env
    setup_local_bin
    setup_zsh_keybindings
    setup_zsh_aliases
    setup_zsh_functions
    setup_tmux_autoattach
    setup_clipboard_helper
    setup_gitconfig
    setup_gitconfig_version
    setup_nvim_config
    setup_tmux_config

    echo ""
    echo "============================================="
    success "Setup complete!"
    echo "============================================="
    echo ""

    [[ -d "$BACKUP_DIR" ]] && info "Backups saved to: $BACKUP_DIR"

    # Guard required: bash 3.2 (macOS /bin/bash) treats "${a[@]}" on an empty
    # array as unbound under `set -u`.
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

  5. Install language runtimes (these are per-project, not pinned globally):
       nvm install --lts && nvm use --lts
       pyenv install <version> && pyenv global <version>
       goenv install <version> && goenv global <version>
       sdk install java
       tfenv install latest && tfenv use latest

  6. Install tmux plugins:
       Open tmux, then press: Ctrl-s + I

  7. Optional — database UI connections. Create a file that is never committed:
       ~/.config/nvim-dbs.lua   (see README "Database" section for the format)

  VERSION MANAGEMENT
  ─────────────────────────────────────────────

    ./setup.sh --check     see installed vs. pinned
    ./setup.sh --update    re-resolve latest, rewrite versions.lock (installs nothing)
    git diff versions.lock review what would change
    ./setup.sh             apply

  Neovim plugins are pinned separately in nvim/lazy-lock.json — update with
  `:Lazy update` inside nvim, then commit the lockfile diff.

CHECKLIST
}

main "$@"
