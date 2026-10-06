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
LOCKFILE="${SCRIPT_DIR}/versions.lock"
MANUAL_STEPS=()

DRY_RUN=false
MODE="install"   # install | update | check

for arg in "$@"; do
    case "$arg" in
        --dry-run) DRY_RUN=true ;;
        --update)  MODE="update" ;;
        --check)   MODE="check" ;;
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

  --help, -h    Show this message.

Roll back an update with:  git checkout versions.lock && ./setup.sh
USAGE
            exit 0
            ;;
    esac
done

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
# Version lock
# -----------------------------------------------------------------------------
# versions.lock is a flat KEY=value file. Parsed rather than sourced so a stray
# line in the lock file can never execute arbitrary code.

# NOTE: deliberately no associative arrays here. macOS still ships bash 3.2 as
# /bin/bash, and this script has to bootstrap on a fresh machine *before*
# install_bash has upgraded it — so nothing in this file may use bash 4+ syntax.
# Pins are therefore read straight from the lockfile on demand; it has ~25
# entries, so the cost is irrelevant.

load_lockfile() {
    if [[ ! -f "$LOCKFILE" ]]; then
        error "versions.lock not found at $LOCKFILE"
        echo "  This file pins every tool version. Restore it with: git checkout versions.lock"
        exit 1
    fi
    local count
    count=$(grep -cE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' "$LOCKFILE" || true)
    if [[ "${count:-0}" -eq 0 ]]; then
        error "versions.lock contains no KEY=value entries — it may be corrupt"
        exit 1
    fi
    info "Loaded ${count} pinned versions from versions.lock"
}

# Read a pin, failing loudly rather than silently installing something unpinned.
# Matches the first `KEY=value` line, ignoring comments and surrounding space.
pin() {
    local key="$1" value
    value=$(sed -n "s/^[[:space:]]*${key}[[:space:]]*=[[:space:]]*\\([^#]*\\).*/\\1/p" "$LOCKFILE" \
        | head -1 \
        | sed 's/[[:space:]]*$//')
    if [[ -z "$value" ]]; then
        error "versions.lock is missing required key: $key"
        exit 1
    fi
    printf '%s\n' "$value"
}

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

# Execute (or, in --dry-run mode, just log) a mutating command
run() {
    if $DRY_RUN; then
        info "[dry-run] would run: $*"
    else
        "$@"
    fi
}

# Append line to file only if not already present
add_line() {
    if grep -qF "$1" "$2" 2>/dev/null; then
        return 0
    elif $DRY_RUN; then
        info "[dry-run] would append to $2: $1"
    else
        echo "$1" >> "$2"
    fi
}

# Write a managed block into a file, replacing it if it already exists.
#
# Each block is wrapped in explicit delimiters:
#
#     # >>> terminal-setup: <name> >>>
#     ...content...
#     # <<< terminal-setup: <name> <<<
#
# and the whole region is REGENERATED on every run. This replaces the previous
# marker-only append, which could not distinguish "my block is already
# installed" from "a stale or partially-damaged block with the same header is
# installed" — the cause of two separate bugs: legacy eager `goenv init -`
# blocks suppressing the lazy replacement (so goenv was never on PATH), and a
# migration step later stripping export lines out of a freshly written block.
#
# Content comes from STDIN:
#
#     add_block "aliases" ~/.zshrc <<'EOF'
#     ...
#     EOF
#
# Deliberately not `"$(cat <<'EOF' ...)"`: bash 3.2 — still /bin/bash on macOS,
# which this script must bootstrap under — misparses a heredoc nested inside
# command substitution.
add_block() {
    local name="$1" file="$2" content
    content=$(cat)

    local begin="# >>> terminal-setup: ${name} >>>"
    local end="# <<< terminal-setup: ${name} <<<"

    [[ -f "$file" ]] || touch "$file"

    # Already present and byte-identical? Nothing to do.
    if grep -qF "$begin" "$file" 2>/dev/null; then
        local current
        current=$(awk -v b="$begin" -v e="$end" '
            $0 == b { inblk = 1; next }
            $0 == e { inblk = 0; next }
            inblk   { print }
        ' "$file")
        if [[ "$current" == "$content" ]]; then
            return 0
        fi
        if $DRY_RUN; then
            info "[dry-run] would UPDATE managed block '${name}' in $file"
            return 0
        fi
        # Replace the region in place, preserving its position in the file.
        # The content is staged in a temp file because awk reads it with
        # getline, which cannot take it on stdin alongside the target file.
        local tmp blockfile
        tmp=$(mktemp)
        blockfile=$(mktemp)
        printf '%s\n' "$content" > "$blockfile"
        awk -v b="$begin" -v e="$end" -v f="$blockfile" '
            $0 == b { print; while ((getline line < f) > 0) print line; close(f); skip = 1; next }
            $0 == e { print; skip = 0; next }
            !skip   { print }
        ' "$file" > "$tmp"
        mv "$tmp" "$file"
        rm -f "$blockfile"
        info "Updated managed block '${name}'"
        return 0
    fi

    if $DRY_RUN; then
        info "[dry-run] would append managed block '${name}' to $file"
        return 0
    fi
    {
        printf '\n%s\n' "$begin"
        printf '%s\n' "$content"
        printf '%s\n' "$end"
    } >> "$file"
}

backup_if_exists() {
    [[ -e "$1" ]] || return 0
    if $DRY_RUN; then
        info "[dry-run] would back up $1 to $BACKUP_DIR"
        return 0
    fi
    mkdir -p "$BACKUP_DIR"
    cp -r "$1" "$BACKUP_DIR/$(basename "$1")"
    info "Backed up $1"
}

# Resolve latest release tag from a GitHub repo (e.g. "v1.2.3" or "14.1.1").
# ONLY called by --update. The install path never resolves versions.
github_latest_tag() {
    curl -fsLI "https://github.com/$1/releases/latest" -o /dev/null -w '%{url_effective}' 2>/dev/null \
        | sed 's|.*/tag/||'
}

# Latest tag (not release) — for repos that tag but never publish releases.
github_latest_tag_only() {
    curl -fsL "https://api.github.com/repos/$1/tags?per_page=1" 2>/dev/null \
        | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

# Latest commit SHA on the default branch — for repos with no tags at all.
github_latest_commit() {
    curl -fsL "https://api.github.com/repos/$1/commits?per_page=1" 2>/dev/null \
        | sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

# Latest mason-registry snapshot tag.
mason_latest_registry() {
    curl -fsL "https://api.github.com/repos/mason-org/mason-registry/releases?per_page=1" 2>/dev/null \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

# Compare a pinned tag against an installed version string.
# Returns 0 (skip — already correct) or 1 (install/update needed).
# Usage: at_pinned_version "name" "$pinned_tag" "$(binary --version | head -1)"
at_pinned_version() {
    local name="$1" pinned_tag="$2" installed="$3"
    local pinned_ver="${pinned_tag#v}"   # strip leading 'v'
    pinned_ver="${pinned_ver#jq-}"       # jq tags look like 'jq-1.8.2'
    if [[ -z "$installed" ]]; then
        info "Installing ${name} ${pinned_tag}..."
        return 1
    fi
    if echo "$installed" | grep -qF "$pinned_ver"; then
        success "${name} ${pinned_tag} — pinned, up to date"
        return 0
    fi
    local cur; cur=$(echo "$installed" | grep -oE '[0-9][0-9.]*[0-9]' | head -1)
    info "Changing ${name}: ${cur:-unknown} → ${pinned_ver} (pinned)"
    return 1
}

# In-place sed that works on both GNU (Linux) and BSD (macOS) sed
sed_inplace() {
    local expr="$1" file="$2"
    if $DRY_RUN; then
        info "[dry-run] would edit $file: $expr"
        return 0
    fi
    if [[ "$(detect_os)" == "macos" ]]; then
        sed -i '' "$expr" "$file"
    else
        sed -i "$expr" "$file"
    fi
}

# Clone (or move an existing clone) to an exact tag/commit, detached.
# Replaces the old `git pull` pattern, which tracked moving branches and was
# the main reason a working setup would break without anything changing locally.
clone_at_tag() {
    local url="$1" dir="$2" ref="$3"
    local name="${4:-$(basename "$dir")}"

    if [[ -d "$dir/.git" ]]; then
        local current
        current=$(git -C "$dir" rev-parse HEAD 2>/dev/null || echo "")
        # Already exactly at the requested ref?
        if [[ "$current" == "$ref"* ]]; then
            success "${name} @ ${ref:0:12} — pinned, up to date"
            return 0
        fi
        local resolved
        resolved=$(git -C "$dir" rev-parse "refs/tags/${ref}^{commit}" 2>/dev/null || echo "")
        if [[ -n "$resolved" && "$current" == "$resolved" ]]; then
            success "${name} @ ${ref} — pinned, up to date"
            return 0
        fi
    fi

    if $DRY_RUN; then
        info "[dry-run] would check out ${name} at ${ref} in $dir"
        return 0
    fi

    if [[ ! -d "$dir/.git" ]]; then
        rm -rf "$dir"
        git clone --quiet --filter=blob:none "$url" "$dir"
    fi

    git -C "$dir" fetch --quiet --tags --force origin || true
    # A 40-char hex string is a commit SHA; anything else is a tag.
    if [[ "$ref" =~ ^[0-9a-f]{40}$ ]]; then
        git -C "$dir" fetch --quiet origin "$ref" 2>/dev/null || true
    fi
    if git -C "$dir" checkout --quiet --detach "$ref" 2>/dev/null; then
        success "${name} @ ${ref} — checked out"
    else
        warn "${name}: could not check out ref '${ref}' — leaving as-is"
    fi
}

# -----------------------------------------------------------------------------
# Package Manager (used only for tools without viable binary releases)
# -----------------------------------------------------------------------------

pkg_install() {
    local pkg="$1" os="${2:-$(detect_os)}"
    if $DRY_RUN; then
        info "[dry-run] would install package '$pkg' via ${os}'s package manager"
        return 0
    fi
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
    if $DRY_RUN; then
        info "[dry-run] would download and install '$binary' from $url"
        return 0
    fi

    local tmpdir
    tmpdir=$(mktemp -d)

    curl -fsSL "$url" -o "$tmpdir/archive.tar.gz"
    tar -xzf "$tmpdir/archive.tar.gz" -C "$tmpdir"

    local bin_path
    bin_path=$(find "$tmpdir" -name "$binary" -type f -perm -u+x | head -1)
    [[ -z "$bin_path" ]] && bin_path=$(find "$tmpdir" -name "$binary" -type f | head -1)

    if [[ -z "$bin_path" ]]; then
        rm -rf "$tmpdir"
        error "Could not find '$binary' in archive: $url"
        return 1
    fi

    mkdir -p "$LOCAL_BIN"
    cp "$bin_path" "$LOCAL_BIN/$binary"
    chmod 755 "$LOCAL_BIN/$binary"
    rm -rf "$tmpdir"
}

# Download a single binary file directly to LOCAL_BIN
install_from_binary_url() {
    local url="$1" binary="$2"
    if $DRY_RUN; then
        info "[dry-run] would download '$binary' from $url"
        return 0
    fi
    mkdir -p "$LOCAL_BIN"
    curl -fsSL "$url" -o "$LOCAL_BIN/$binary"
    chmod 755 "$LOCAL_BIN/$binary"
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
        if $DRY_RUN; then
            info "[dry-run] would install oh-my-zsh"
            return 0
        fi
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
    if $DRY_RUN; then
        info "[dry-run] would prepend p10k instant-prompt block to $zshrc"
        return 0
    fi
    local tmp
    tmp=$(mktemp)
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
            if grep -q "$plugin" "${HOME}/.zshrc"; then
                continue
            elif $DRY_RUN; then
                info "[dry-run] would add $plugin to .zshrc plugins list"
            else
                perl -i -pe "s/^(plugins=\()(.+)(\))/\$1\$2 $plugin\$3/" "${HOME}/.zshrc"
            fi
        done
    fi
}

# -----------------------------------------------------------------------------
# CLI Tools — binary releases, all versions from versions.lock
# -----------------------------------------------------------------------------

install_bash() {
    info "=== bash ==="
    # macOS ships with bash 3.2 (GPL licensing); upgrade to bash 5 via brew
    if [[ "$(detect_os)" != "macos" ]]; then success "bash — skipped (Linux)"; return 0; fi
    local current_version major
    current_version=$(bash --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)
    major="${current_version%%.*}"
    if [[ "$major" -ge 5 ]]; then
        success "bash already at version $current_version"
        return 0
    fi
    if ! brew list bash &>/dev/null; then
        run brew install bash
    fi
    success "bash upgraded"
}

install_fzf() {
    info "=== fzf ==="
    local tag; tag=$(pin FZF_VERSION)

    # fzf is cloned (not just downloaded) because its repo ships the completion
    # and key-binding shell scripts; the binary comes from its own installer.
    clone_at_tag "https://github.com/junegunn/fzf.git" "${HOME}/.fzf" "$tag" "fzf"

    if ! at_pinned_version "fzf" "$tag" "$("$LOCAL_BIN/fzf" --version 2>/dev/null | head -1)"; then
        run "${HOME}/.fzf/install" --bin
        success "fzf ${tag} binary installed"
    fi

    if $DRY_RUN; then
        info "[dry-run] would symlink ${HOME}/.fzf/bin/fzf -> $LOCAL_BIN/fzf"
    else
        mkdir -p "$LOCAL_BIN"
        ln -sf "${HOME}/.fzf/bin/fzf" "$LOCAL_BIN/fzf"
    fi

    # Remove legacy fzf shell integration lines (replaced by explicit functions in setup_zsh_functions)
    if [[ -f "${HOME}/.zshrc" ]]; then
        if $DRY_RUN; then
            info "[dry-run] would strip legacy fzf shell-integration lines from .zshrc"
        else
            perl -i -ne 'print unless /\[ -f ~\/\.fzf\.zsh \]/ || /eval "\$\(fzf --zsh\)"/' "${HOME}/.zshrc"
        fi
    fi
}

install_neovim() {
    info "=== neovim ==="

    local os arch tag url
    os=$(detect_os)
    arch=$(detect_arch)
    tag=$(pin NVIM_VERSION)

    at_pinned_version "neovim" "$tag" "$(nvim --version 2>/dev/null | head -1)" && return 0

    if [[ "$os" == "macos" ]]; then
        url="https://github.com/neovim/neovim/releases/download/${tag}/nvim-macos-${arch}.tar.gz"
    else
        url="https://github.com/neovim/neovim/releases/download/${tag}/nvim-linux-${arch}.tar.gz"
    fi

    if $DRY_RUN; then
        info "[dry-run] would download and install neovim ${tag} from $url"
        return 0
    fi

    local tmpdir; tmpdir=$(mktemp -d)
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
    success "neovim ${tag} installed"
}

install_ripgrep() {
    info "=== ripgrep ==="
    local tag version target
    tag=$(pin RIPGREP_VERSION)
    at_pinned_version "rg" "$tag" "$("$LOCAL_BIN/rg" --version 2>/dev/null | head -1)" && return 0
    version="${tag#v}"
    target=$(detect_rust_target)
    install_from_tarball \
        "https://github.com/BurntSushi/ripgrep/releases/download/${tag}/ripgrep-${version}-${target}.tar.gz" \
        "rg"
    success "rg ${tag} installed"
}

install_fd() {
    info "=== fd ==="
    local tag target
    tag=$(pin FD_VERSION)
    at_pinned_version "fd" "$tag" "$("$LOCAL_BIN/fd" --version 2>/dev/null | head -1)" && return 0
    target=$(detect_rust_target)
    install_from_tarball \
        "https://github.com/sharkdp/fd/releases/download/${tag}/fd-${tag}-${target}.tar.gz" \
        "fd"
    success "fd ${tag} installed"
}

install_bat() {
    info "=== bat ==="
    local tag target
    tag=$(pin BAT_VERSION)
    at_pinned_version "bat" "$tag" "$("$LOCAL_BIN/bat" --version 2>/dev/null | head -1)" && return 0
    target=$(detect_rust_target)
    install_from_tarball \
        "https://github.com/sharkdp/bat/releases/download/${tag}/bat-${tag}-${target}.tar.gz" \
        "bat"
    success "bat ${tag} installed"
}

install_eza() {
    info "=== eza ==="
    local os arch tag url
    os=$(detect_os)
    tag=$(pin EZA_VERSION)

    if [[ "$os" == "macos" ]]; then
        # eza publishes no macOS binaries, so brew is the only option. brew
        # tracks its own formula version, which may differ from the pinned tag —
        # report what brew actually has rather than echoing the pin back.
        if command_exists eza && brew list eza &>/dev/null; then
            success "eza $(eza --version 2>/dev/null | grep -oE 'v[0-9.]+' | head -1) — via brew (pin ${tag} is advisory on macOS)"
            return 0
        fi
        if $DRY_RUN; then
            info "[dry-run] would run: brew install eza"
        else
            brew install eza
        fi
        success "eza installed via brew"
        return 0
    fi

    at_pinned_version "eza" "$tag" "$("$LOCAL_BIN/eza" --version 2>/dev/null | head -2 | tail -1)" && return 0

    # Linux: x86_64 has a musl build; aarch64 only has gnu
    arch=$(detect_arch_rust)
    if [[ "$arch" == "x86_64" ]]; then
        url="https://github.com/eza-community/eza/releases/download/${tag}/eza_x86_64-unknown-linux-musl.tar.gz"
    else
        url="https://github.com/eza-community/eza/releases/download/${tag}/eza_${arch}-unknown-linux-gnu.tar.gz"
    fi
    install_from_tarball "$url" "eza"
    success "eza ${tag} installed"
}

install_jq() {
    info "=== jq ==="
    local os arch tag jq_os jq_arch
    os=$(detect_os)
    arch=$(detect_arch)
    tag=$(pin JQ_VERSION)
    at_pinned_version "jq" "$tag" "$("$LOCAL_BIN/jq" --version 2>/dev/null)" && return 0
    [[ "$os" == "macos" ]] && jq_os="macos" || jq_os="linux"
    [[ "$arch" == "x86_64" ]] && jq_arch="amd64" || jq_arch="arm64"
    install_from_binary_url \
        "https://github.com/jqlang/jq/releases/download/${tag}/jq-${jq_os}-${jq_arch}" \
        "jq"
    success "jq ${tag} installed"
}

install_yq() {
    info "=== yq ==="
    local os arch tag yq_os yq_arch
    os=$(detect_os)
    arch=$(detect_arch)
    tag=$(pin YQ_VERSION)
    at_pinned_version "yq" "$tag" "$("$LOCAL_BIN/yq" --version 2>/dev/null | head -1)" && return 0
    [[ "$os" == "macos" ]] && yq_os="darwin" || yq_os="linux"
    [[ "$arch" == "x86_64" ]] && yq_arch="amd64" || yq_arch="arm64"
    install_from_binary_url \
        "https://github.com/mikefarah/yq/releases/download/${tag}/yq_${yq_os}_${yq_arch}" \
        "yq"
    success "yq ${tag} installed"
}

install_k9s() {
    info "=== k9s ==="
    local os arch tag k9s_os k9s_arch
    os=$(detect_os)
    arch=$(detect_arch)
    tag=$(pin K9S_VERSION)
    at_pinned_version "k9s" "$tag" "$("$LOCAL_BIN/k9s" version 2>/dev/null | grep -i 'Version:' | head -1)" && return 0
    [[ "$os" == "macos" ]] && k9s_os="Darwin" || k9s_os="Linux"
    [[ "$arch" == "x86_64" ]] && k9s_arch="amd64" || k9s_arch="arm64"
    install_from_tarball \
        "https://github.com/derailed/k9s/releases/download/${tag}/k9s_${k9s_os}_${k9s_arch}.tar.gz" \
        "k9s"
    success "k9s ${tag} installed"
}

install_lazygit() {
    info "=== lazygit ==="
    # Primary git UI (nvim: <leader>gg). Handles interactive rebase, conflict
    # resolution, stashes, cherry-pick and amend far better than any nvim plugin.
    local os arch tag lg_os lg_arch
    os=$(detect_os)
    arch=$(detect_arch)
    tag=$(pin LAZYGIT_VERSION)
    at_pinned_version "lazygit" "$tag" "$("$LOCAL_BIN/lazygit" --version 2>/dev/null | head -1)" && return 0
    [[ "$os" == "macos" ]] && lg_os="Darwin" || lg_os="Linux"
    [[ "$arch" == "x86_64" ]] && lg_arch="x86_64" || lg_arch="arm64"
    install_from_tarball \
        "https://github.com/jesseduffield/lazygit/releases/download/${tag}/lazygit_${tag#v}_${lg_os}_${lg_arch}.tar.gz" \
        "lazygit"
    success "lazygit ${tag} installed"
}

install_delta() {
    info "=== delta ==="
    # Syntax-highlighted git diffs in the terminal; configured as git's pager
    # in git/gitconfig and reused by fzf-lua's git previewers.
    local tag target
    tag=$(pin DELTA_VERSION)
    at_pinned_version "delta" "$tag" "$("$LOCAL_BIN/delta" --version 2>/dev/null | head -1)" && return 0
    target=$(detect_rust_target)
    install_from_tarball \
        "https://github.com/dandavison/delta/releases/download/${tag}/delta-${tag}-${target}.tar.gz" \
        "delta"
    success "delta ${tag} installed"
}

install_postgres_client() {
    info "=== postgres client (psql) ==="
    # Required by vim-dadbod for the <leader>D database UI. Client only — this
    # does not install or run a Postgres server.
    if command_exists psql; then
        success "psql already installed ($(psql --version 2>/dev/null))"
        return 0
    fi
    case "$(detect_os)" in
        macos)
            # libpq is keg-only: it ships psql but is not symlinked into PATH.
            if $DRY_RUN; then
                info "[dry-run] would run: brew install libpq and symlink psql"
            else
                brew install libpq
                mkdir -p "$LOCAL_BIN"
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
        mkdir -p "$LOCAL_BIN"
        ln -sf "${HOME}/.cargo/bin/tree-sitter" "$LOCAL_BIN/tree-sitter"
    fi
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

    # nvm's installer may have already written its init block to .zshrc (when $SHELL=zsh);
    # check for the sourced script rather than our marker to avoid duplicates.
    # Sourcing nvm.sh is real shell-startup cost, so defer it behind a lazy-loading
    # stub that only runs on first actual use of nvm/node/npm/npx.
    add_block "nvm" "${HOME}/.zshrc" <<'BLOCK_EOF'
# nvm (lazy-loaded on first use)
export NVM_DIR="$HOME/.nvm"
_nvm_lazy_load() {
    unset -f nvm node npm npx _nvm_lazy_load
    [ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"
    [ -s "$NVM_DIR/bash_completion" ] && \. "$NVM_DIR/bash_completion"
}
nvm()  { _nvm_lazy_load; nvm "$@"; }
node() { _nvm_lazy_load; node "$@"; }
npm()  { _nvm_lazy_load; npm "$@"; }
npx()  { _nvm_lazy_load; npx "$@"; }
BLOCK_EOF
}

install_pyenv() {
    info "=== pyenv ==="
    # Cloned at a pinned tag rather than installed via `curl pyenv.run | bash`,
    # which always fetches master and is one of the ways this setup used to drift.
    clone_at_tag "https://github.com/pyenv/pyenv.git" "${HOME}/.pyenv" "$(pin PYENV_VERSION)" "pyenv"

    # `pyenv init -` forks pyenv and evals its output on every shell startup;
    # defer that behind a lazy-loading stub that runs on first actual use.
    add_block "pyenv" "${HOME}/.zshrc" <<'BLOCK_EOF'
# pyenv (lazy-loaded on first use)
export PYENV_ROOT="$HOME/.pyenv"
[[ -d $PYENV_ROOT/bin ]] && export PATH="$PYENV_ROOT/bin:$PATH"
_pyenv_lazy_load() {
    unset -f pyenv python python3 pip pip3 _pyenv_lazy_load
    eval "$(command pyenv init -)"
}
pyenv()   { _pyenv_lazy_load; pyenv "$@"; }
python()  { _pyenv_lazy_load; python "$@"; }
python3() { _pyenv_lazy_load; python3 "$@"; }
pip()     { _pyenv_lazy_load; pip "$@"; }
pip3()    { _pyenv_lazy_load; pip3 "$@"; }
BLOCK_EOF

    # pyenv builds Python from source — surface the required packages per distro
    case "$(detect_os)" in
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

    # `goenv init -` forks goenv and evals its output on every shell startup;
    # defer that behind a lazy-loading stub that runs on first actual use.
    add_block "goenv" "${HOME}/.zshrc" <<'BLOCK_EOF'
# goenv (lazy-loaded on first use)
export GOENV_ROOT="$HOME/.goenv"
export PATH="$GOENV_ROOT/bin:$PATH"
export GOENV_PATH_ORDER=front
_goenv_lazy_load() {
    unset -f goenv go _goenv_lazy_load
    eval "$(command goenv init -)"
}
goenv() { _goenv_lazy_load; goenv "$@"; }
go()    { _goenv_lazy_load; go "$@"; }
BLOCK_EOF

    # goenv downloads pre-built Go binaries but needs gcc/make for cgo-based tooling
    case "$(detect_os)" in
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
        sdkman_script=$(mktemp)
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

    local os
    os=$(detect_os)

    if $DRY_RUN && [[ "$os" != "macos" ]]; then
        info "[dry-run] would install Docker via ${os}'s package manager (multiple sudo steps: repo setup, package install, enable service, add \$USER to docker group)"
        return 0
    fi

    case "$os" in
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

    if $DRY_RUN; then
        info "[dry-run] would symlink tfenv binaries into $LOCAL_BIN"
        return 0
    fi

    mkdir -p "$LOCAL_BIN"
    local bin dest
    for bin in "${HOME}/.tfenv/bin/"*; do
        dest="$LOCAL_BIN/$(basename "$bin")"
        [[ -e "$dest" ]] || ln -s "$bin" "$dest"
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

    local found=0 h
    for h in "${legacy_headers[@]}"; do
        if grep -qxF "$h" "$zshrc" 2>/dev/null; then
            found=1
            break
        fi
    done
    local sdk_count
    sdk_count=$(grep -c 'sdkman-init.sh' "$zshrc" 2>/dev/null || echo 0)

    if [[ $found -eq 0 && "$sdk_count" -le 1 ]]; then
        success "no legacy blocks to migrate"
        return 0
    fi

    if $DRY_RUN; then
        info "[dry-run] would remove legacy un-delimited blocks from $zshrc"
        return 0
    fi

    backup_if_exists "$zshrc"

    # Delete each legacy header and the contiguous non-blank lines after it.
    # Never touches a managed region: those start with "# >>> terminal-setup:".
    local hdr_file
    hdr_file=$(mktemp)
    printf '%s\n' "${legacy_headers[@]}" > "$hdr_file"
    local tmp
    tmp=$(mktemp)
    awk -v hdrfile="$hdr_file" '
        BEGIN {
            while ((getline h < hdrfile) > 0) { hdr[h] = 1 }
            close(hdrfile)
        }
        # Inside a managed region: always keep, never treat as legacy.
        /^# >>> terminal-setup:/ { managed = 1; print; next }
        /^# <<< terminal-setup:/ { managed = 0; print; next }
        managed { print; next }

        skipping {
            if ($0 == "") { skipping = 0 }   # blank line ends the legacy block
            next
        }
        ($0 in hdr) { skipping = 1; removed++; next }
        { print }
        END { if (removed) printf("REMOVED %d\n", removed) > "/dev/stderr" }
    ' "$zshrc" > "$tmp"
    mv "$tmp" "$zshrc"
    rm -f "$hdr_file"

    # Collapse runs of blank lines left behind.
    perl -i -0777 -pe 's/\n{3,}/\n\n/g' "$zshrc"

    # Duplicate SDKMAN init: its own installer writes one and older versions of
    # this script appended another. Keep the first.
    perl -i -0777 -pe '
        my $blk = qq{export SDKMAN_DIR="\$HOME/.sdkman"\n[[ -s "\$HOME/.sdkman/bin/sdkman-init.sh" ]] && source "\$HOME/.sdkman/bin/sdkman-init.sh"\n};
        my $q = quotemeta $blk;
        my $n = 0;
        s/$q/(++$n == 1) ? $blk : ""/ge;
    ' "$zshrc"

    success "legacy un-delimited blocks removed (backed up to $BACKUP_DIR)"

    # Report, don't delete, the multi-paragraph ones.
    local leftover=""
    grep -qxF "# Custom aliases" "$zshrc" 2>/dev/null && leftover="${leftover} '# Custom aliases'"
    grep -qxF "# Custom shell functions" "$zshrc" 2>/dev/null && leftover="${leftover} '# Custom shell functions'"
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
    if $DRY_RUN; then
        info "[dry-run] would ensure $LOCAL_BIN exists and re-append its PATH line to $zshrc"
        return 0
    fi
    mkdir -p "$LOCAL_BIN"
    touch "$zshrc"
    # grep exits 1 when it filters out every line or the file is empty, so the
    # exit status is deliberately ignored — but the move must still happen.
    grep -vF "$line" "$zshrc" > "${zshrc}.tmp" || true
    mv "${zshrc}.tmp" "$zshrc"
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

# Is the installed git at least $1 (e.g. "2.35")? bash 3.2 safe: no arrays.
git_version_at_least() {
    local want="$1" have
    have=$(git --version 2>/dev/null | sed -n 's/^git version \([0-9.]*\).*/\1/p')
    [[ -z "$have" ]] && return 1

    local want_major want_minor have_major have_minor
    want_major="${want%%.*}"; want_minor="${want#*.}"; want_minor="${want_minor%%.*}"
    have_major="${have%%.*}"; have_minor="${have#*.}"; have_minor="${have_minor%%.*}"
    [[ -z "$want_minor" || "$want_minor" == "$want" ]] && want_minor=0
    [[ -z "$have_minor" || "$have_minor" == "$have" ]] && have_minor=0

    if [[ "$have_major" -gt "$want_major" ]]; then return 0; fi
    if [[ "$have_major" -lt "$want_major" ]]; then return 1; fi
    [[ "$have_minor" -ge "$want_minor" ]]
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

    if $DRY_RUN; then
        info "[dry-run] would write $out (conflictstyle=${conflictstyle})"
        return 0
    fi

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
    elif $DRY_RUN; then
        backup_if_exists "$target"
        info "[dry-run] would symlink $target -> $source"
    else
        backup_if_exists "$target"
        rm -rf "$target"
        mkdir -p "$(dirname "$target")"
        ln -s "$source" "$target"
        success "Neovim config symlinked: $target -> $source"
    fi

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
    if $DRY_RUN; then
        info "[dry-run] would write Mason registry pin ${registry} to $out"
        return 0
    fi
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
    if [[ "$(detect_os)" == "macos" ]]; then success "clipboard — pbcopy (macOS native)"; return 0; fi

    # Install both clipboard backends: xclip (X11) and wl-clipboard (Wayland)
    command_exists xclip    || pkg_install "xclip"
    command_exists wl-copy  || pkg_install "wl-clipboard"

    if $DRY_RUN; then
        info "[dry-run] would write clipboard helper to $LOCAL_BIN/tmux-clipboard"
        return 0
    fi

    # Write a runtime-detection wrapper so tmux works on both X11 and Wayland
    mkdir -p "$LOCAL_BIN"
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
    local target="${HOME}/.tmux.conf"
    local source="${SCRIPT_DIR}/tmux/tmux.conf"

    if [[ ! -f "$source" ]]; then
        error "tmux config not found: $source"
        return 1
    fi

    # Symlinked, not copied: edits to the repo take effect on the next
    # `prefix + r` with no re-run of this script. The old copy+sed approach
    # meant repo changes were invisible until setup.sh ran again. The
    # pbcopy/tmux-clipboard choice now lives inside tmux.conf as an if-shell.
    if [[ -L "$target" && "$(readlink "$target")" == "$source" ]]; then
        success "tmux config symlink already correct"
    elif $DRY_RUN; then
        backup_if_exists "$target"
        info "[dry-run] would symlink $target -> $source"
    else
        backup_if_exists "$target"
        rm -f "$target"
        ln -s "$source" "$target"
        success "tmux config symlinked: $target -> $source"
    fi

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

    if $DRY_RUN; then
        info "[dry-run] would pin tmux plugins in tmux.conf (navigator=${nav:0:12} catppuccin=${cat_tmux} cpu=${cpu:0:12})"
        return 0
    fi

    sed_inplace "s|^set -g @plugin 'christoomey/vim-tmux-navigator.*|set -g @plugin 'christoomey/vim-tmux-navigator#${nav}'|" "$conf"
    sed_inplace "s|^set -g @plugin 'catppuccin/tmux.*|set -g @plugin 'catppuccin/tmux#${cat_tmux}'|" "$conf"
    sed_inplace "s|^set -g @plugin 'tmux-plugins/tmux-cpu.*|set -g @plugin 'tmux-plugins/tmux-cpu#${cpu}'|" "$conf"
    success "tmux plugins pinned from versions.lock"
}

# -----------------------------------------------------------------------------
# --update : re-resolve every pinned version, rewrite versions.lock, install nothing
# -----------------------------------------------------------------------------

# Map of lock key -> how to resolve its latest value.
# "release:<repo>" latest GitHub release tag
# "tag:<repo>"     latest git tag (repos that tag but publish no releases)
# "commit:<repo>"  latest commit SHA (repos with no tags at all)
# "mason"          latest mason-registry snapshot
# "manual"         never auto-resolved (explained inline)
resolver_for() {
    case "$1" in
        NVIM_VERSION)                    echo "release:neovim/neovim" ;;
        FZF_VERSION)                     echo "release:junegunn/fzf" ;;
        RIPGREP_VERSION)                 echo "release:BurntSushi/ripgrep" ;;
        FD_VERSION)                      echo "release:sharkdp/fd" ;;
        BAT_VERSION)                     echo "release:sharkdp/bat" ;;
        EZA_VERSION)                     echo "release:eza-community/eza" ;;
        JQ_VERSION)                      echo "release:jqlang/jq" ;;
        YQ_VERSION)                      echo "release:mikefarah/yq" ;;
        K9S_VERSION)                     echo "release:derailed/k9s" ;;
        LAZYGIT_VERSION)                 echo "release:jesseduffield/lazygit" ;;
        DELTA_VERSION)                   echo "release:dandavison/delta" ;;
        TREE_SITTER_CLI_VERSION)         echo "tag:tree-sitter/tree-sitter" ;;
        OHMYZSH_COMMIT)                  echo "commit:ohmyzsh/ohmyzsh" ;;
        P10K_VERSION)                    echo "release:romkatv/powerlevel10k" ;;
        ZSH_SYNTAX_HIGHLIGHTING_VERSION) echo "tag:zsh-users/zsh-syntax-highlighting" ;;
        ZSH_AUTOSUGGESTIONS_VERSION)     echo "tag:zsh-users/zsh-autosuggestions" ;;
        TPM_VERSION)                     echo "tag:tmux-plugins/tpm" ;;
        TMUX_NAVIGATOR_COMMIT)           echo "commit:christoomey/vim-tmux-navigator" ;;
        CATPPUCCIN_TMUX_VERSION)         echo "release:catppuccin/tmux" ;;
        TMUX_CPU_COMMIT)                 echo "commit:tmux-plugins/tmux-cpu" ;;
        NVM_VERSION)                     echo "release:nvm-sh/nvm" ;;
        PYENV_VERSION)                   echo "release:pyenv/pyenv" ;;
        GOENV_VERSION)                   echo "release:go-nv/goenv" ;;
        TFENV_VERSION)                   echo "release:tfutils/tfenv" ;;
        MASON_REGISTRY)                  echo "mason" ;;
        *)                               echo "manual" ;;
    esac
}

# Newest tag matching a version-series prefix (e.g. "2." for goenv 2.x).
# Checks tags rather than releases, since a maintained older series often has
# tags without GitHub release entries.
resolve_latest_in_series() {
    local spec="$1" prefix="$2" repo tag
    repo="${spec#*:}"
    # Exact prefix match via `case`, NOT grep: the constraint contains a literal
    # "." which grep would treat as "any character", so "2." also matched the
    # ancient date-based tag "v20161215".
    curl -fsL "https://api.github.com/repos/${repo}/tags?per_page=100" 2>/dev/null \
        | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' \
        | while IFS= read -r tag; do
            case "${tag#v}" in
                "${prefix}"*) printf '%s\n' "$tag" ;;
            esac
        done \
        | sed 's/^v//' \
        | sort -t. -k1,1n -k2,2n -k3,3n \
        | tail -1
}

resolve_latest() {
    local spec="$1" kind repo
    kind="${spec%%:*}"
    repo="${spec#*:}"
    case "$kind" in
        release) github_latest_tag "$repo" ;;
        tag)     github_latest_tag_only "$repo" ;;
        commit)  github_latest_commit "$repo" ;;
        mason)   mason_latest_registry ;;
        *)       echo "" ;;
    esac
}

do_update() {
    echo "============================================="
    echo "  Re-resolving pinned versions"
    echo "============================================="
    echo ""
    info "Querying upstream for the latest version of each pinned tool..."
    echo ""

    local changed=0 unchanged=0 failed=0
    local key spec latest current
    local -a report=()

    # Preserve file order and all comments: rewrite values in place.
    local tmp; tmp=$(mktemp)

    while IFS= read -r line || [[ -n "$line" ]]; do
        # Pass through comments and blanks untouched
        if [[ -z "${line// }" || "${line#"${line%%[![:space:]]*}"}" == \#* || "$line" != *=* ]]; then
            printf '%s\n' "$line" >> "$tmp"
            continue
        fi
        key="${line%%=*}"
        current="${line#*=}"
        spec=$(resolver_for "$key")

        if [[ "$spec" == "manual" ]]; then
            printf '%s\n' "$line" >> "$tmp"
            continue
        fi

        latest=$(resolve_latest "$spec")

        # A <KEY>_CONSTRAINT pin restricts this tool to a version series, for
        # tools whose next major needs a different install method. Without it,
        # --update happily crossed goenv 2.x -> 3.x, which replaced the shell
        # implementation with a compiled binary and broke the integration.
        local constraint
        constraint=$(sed -n "s/^[[:space:]]*${key}_CONSTRAINT[[:space:]]*=[[:space:]]*\\([^#]*\\).*/\\1/p" "$LOCKFILE" \
            | head -1 | sed 's/[[:space:]]*$//')
        if [[ -n "$constraint" && -n "$latest" ]]; then
            if [[ "${latest#v}" != "${constraint}"* ]]; then
                local series
                series=$(resolve_latest_in_series "$spec" "$constraint")
                if [[ -n "$series" ]]; then
                    info "$key: newest is ${latest}, but constrained to ${constraint}x — using ${series}"
                    latest="$series"
                else
                    warn "$key: constrained to ${constraint}x; could not resolve a matching tag — keeping ${current}"
                    printf '%s\n' "$line" >> "$tmp"
                    unchanged=$((unchanged + 1))
                    continue
                fi
            fi
        fi

        if [[ -z "$latest" ]]; then
            warn "$key: could not resolve latest (network or rate limit) — keeping ${current}"
            printf '%s\n' "$line" >> "$tmp"
            failed=$((failed + 1))
            continue
        fi

        if [[ "$latest" == "$current" ]]; then
            printf '%s\n' "$line" >> "$tmp"
            unchanged=$((unchanged + 1))
        else
            printf '%s=%s\n' "$key" "$latest" >> "$tmp"
            report+=("  ${key}: ${current} → ${latest}")
            changed=$((changed + 1))
        fi
    done < "$LOCKFILE"

    if $DRY_RUN; then
        info "[dry-run] would rewrite $LOCKFILE"
        rm -f "$tmp"
    else
        mv "$tmp" "$LOCKFILE"
    fi

    echo ""
    if [[ $changed -gt 0 ]]; then
        echo "  UPDATED (${changed}):"
        printf '%s\n' "${report[@]}"
    fi
    echo ""
    success "${changed} changed · ${unchanged} already latest · ${failed} unresolved"
    echo ""
    cat <<'NEXT'
  Nothing has been installed. Next steps:

    git diff versions.lock     # review exactly what moved
    ./setup.sh                 # apply the new pins

  To discard these updates:

    git checkout versions.lock

  Note: Neovim plugins are pinned separately in nvim/lazy-lock.json. To update
  those, run `:Lazy update` inside nvim and commit the resulting lockfile diff.

NEXT
}

# -----------------------------------------------------------------------------
# --check : report drift between versions.lock and what is actually installed
# -----------------------------------------------------------------------------

do_check() {
    echo "============================================="
    echo "  Installed vs. pinned"
    echo "============================================="
    echo ""

    local drift=0
    check_one() {
        local name="$1" pinned="$2" installed="$3"
        local want="${pinned#v}"; want="${want#jq-}"
        if [[ -z "$installed" ]]; then
            printf "  %-16s %-22s %s\n" "$name" "$pinned" "NOT INSTALLED"
            drift=$((drift + 1))
        elif echo "$installed" | grep -qF "$want"; then
            printf "  %-16s %-22s ok\n" "$name" "$pinned"
        else
            printf "  %-16s %-22s DRIFT (installed: %s)\n" "$name" "$pinned" \
                "$(echo "$installed" | grep -oE '[0-9][0-9.]*[0-9]' | head -1)"
            drift=$((drift + 1))
        fi
    }

    check_one "neovim"   "$(pin NVIM_VERSION)"    "$(nvim --version 2>/dev/null | head -1)"
    check_one "fzf"      "$(pin FZF_VERSION)"     "$(fzf --version 2>/dev/null | head -1)"
    check_one "ripgrep"  "$(pin RIPGREP_VERSION)" "$(rg --version 2>/dev/null | head -1)"
    check_one "fd"       "$(pin FD_VERSION)"      "$(fd --version 2>/dev/null | head -1)"
    check_one "bat"      "$(pin BAT_VERSION)"     "$(bat --version 2>/dev/null | head -1)"
    check_one "jq"       "$(pin JQ_VERSION)"      "$(jq --version 2>/dev/null)"
    check_one "yq"       "$(pin YQ_VERSION)"      "$(yq --version 2>/dev/null | head -1)"
    check_one "k9s"      "$(pin K9S_VERSION)"     "$(k9s version 2>/dev/null | grep -i 'Version:' | head -1)"
    check_one "lazygit"  "$(pin LAZYGIT_VERSION)" "$(lazygit --version 2>/dev/null | head -1)"
    check_one "delta"    "$(pin DELTA_VERSION)"   "$(delta --version 2>/dev/null | head -1)"
    check_one "tree-sitter" "$(pin TREE_SITTER_CLI_VERSION)" "$(tree-sitter --version 2>/dev/null)"

    echo ""
    printf "  %-16s %s\n" "mason registry" "$(pin MASON_REGISTRY)"
    printf "  %-16s %s\n" "psql" "$(psql --version 2>/dev/null || echo 'NOT INSTALLED (needed for nvim database UI)')"
    echo ""
    if [[ $drift -eq 0 ]]; then
        success "No drift — everything matches versions.lock"
    else
        warn "${drift} tool(s) differ from versions.lock — run ./setup.sh to reconcile"
    fi
    echo ""
}

# -----------------------------------------------------------------------------
# Prerequisite Check
# -----------------------------------------------------------------------------

check_prerequisites() {
    local missing=()

    command_exists git  || missing+=("git")
    command_exists curl || missing+=("curl")
    command_exists perl || missing+=("perl")
    # `make` is no longer required: the only consumer was telescope-fzf-native,
    # which has been replaced by fzf-lua (pure Lua, shells out to the fzf binary).
    # It stays listed for pyenv/goenv native builds but is no longer fatal.
    command_exists make || warn "make not found — needed only to build Python via pyenv or cgo tooling"

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "Missing required tools: ${missing[*]}"
        echo ""
        echo "  Install them before running this script:"
        echo ""
        echo "  macOS:          xcode-select --install   (includes git, make, curl)"
        echo "  Debian/Ubuntu:  sudo apt-get install -y git curl perl build-essential"
        echo "  Fedora/RHEL:    sudo dnf install -y git curl perl make gcc"
        echo ""
        exit 1
    fi
}

# -----------------------------------------------------------------------------
# Main
# -----------------------------------------------------------------------------

main() {
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

    local os; os=$(detect_os)
    info "OS: $os | Arch: $(detect_arch)"
    info "Versions: pinned by versions.lock (no network version resolution)"
    echo ""

    case "$os" in
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
            if ! (command_exists brew && brew list grep &>/dev/null); then
                run brew install grep
            fi
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
