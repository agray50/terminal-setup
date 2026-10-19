# shellcheck shell=bash
# Shared helpers for setup.sh: logging, version pins, platform detection, file
# editing and downloads. Sourced, never run. Must stay bash 3.2 compatible --
# see the note under "Version lock".
#
# Expects from the caller: DRY_RUN, LOCKFILE, LOCAL_BIN, BACKUP_DIR,
# BACKUP_WARN_AT, MANUAL_STEPS and WORK. scripts/verify.sh sources this too.

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
    value=$(pin_optional "$key")
    if [[ -z "$value" ]]; then
        error "versions.lock is missing required key: $key"
        exit 1
    fi
    printf '%s\n' "$value"
}

# The same lookup for keys that may legitimately be absent (e.g. <KEY>_CONSTRAINT).
pin_optional() {
    sed -n "s/^[[:space:]]*${1}[[:space:]]*=[[:space:]]*\\([^#]*\\).*/\\1/p" "$LOCKFILE" \
        | head -1 \
        | sed 's/[[:space:]]*$//'
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

# Detected once: these used to be re-derived on every use (detect_os alone ran
# 17 times per install, re-sourcing /etc/os-release each time on Linux).
OS=$(detect_os)
ARCH=$(detect_arch)

# Pick the spelling a release uses for this platform. Every project names
# platforms differently (Darwin/darwin/macos, amd64/x86_64), so each caller
# passes its own: `$(by_os Darwin Linux)_$(by_arch amd64 arm64)`.
by_os()   { if [[ "$OS" == "macos" ]]; then echo "$1"; else echo "$2"; fi; }
by_arch() { if [[ "$ARCH" == "x86_64" ]]; then echo "$1"; else echo "$2"; fi; }

# Rust target triple (ripgrep/fd/bat/delta release filenames).
RUST_TARGET="$(by_arch x86_64 aarch64)-$(by_os apple-darwin unknown-linux-musl)"

# -----------------------------------------------------------------------------
# Utilities
# -----------------------------------------------------------------------------

command_exists() { command -v "$1" >/dev/null 2>&1; }

# Install a Homebrew formula unless it is already installed.
brew_ensure() {
    brew list "$1" &>/dev/null || run brew install "$1"
}

# In --dry-run mode, log what would happen and succeed; otherwise fail, so the
# caller carries on:   dry_skip "would do X" && return 0
dry_skip() {
    $DRY_RUN || return 1
    info "[dry-run] $1"
}

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
        dry_skip "would UPDATE managed block '${name}' in $file" && return 0
        # Replace the region in place, preserving its position in the file.
        # The content is staged in a temp file because awk reads it with
        # getline, which cannot take it on stdin alongside the target file.
        local tmp blockfile
        tmp=$(mktemp "$WORK/tmp.XXXXXX")
        blockfile=$(mktemp "$WORK/tmp.XXXXXX")
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

    dry_skip "would append managed block '${name}' to $file" && return 0
    {
        printf '\n%s\n' "$begin"
        printf '%s\n' "$content"
        printf '%s\n' "$end"
    } >> "$file"
}

# Print only the lines of a file that are OUTSIDE "# >>> terminal-setup:"
# regions. Detection of legacy blocks has to run against this rather than the
# whole file: several of the legacy headers we look for are byte-identical to
# the first content line of the blocks this script itself writes.
unmanaged_region() {
    awk '
        /^# >>> terminal-setup:/ { managed = 1; next }
        /^# <<< terminal-setup:/ { managed = 0; next }
        !managed { print }
    ' "$1"
}

backup_if_exists() {
    [[ -e "$1" ]] || return 0
    dry_skip "would back up $1 to $BACKUP_DIR" && return 0
    mkdir -p "$BACKUP_DIR"
    cp -r "$1" "$BACKUP_DIR/$(basename "$1")"
    info "Backed up $1"
}

# Backups accumulate one directory per changed file per run. That was a real
# problem while migrate_legacy_zshrc was rewriting ~/.zshrc on every run (53
# directories had built up, 38 of them byte-identical); with that fixed, a new
# directory appears only when something genuinely changed.
#
# So this warns rather than deletes. An installer should not quietly discard
# the user's own config history, and the *oldest* snapshot — the pre-setup
# original — is the one most worth keeping, which is exactly what a naive
# "keep the newest N" would throw away first.
warn_stale_backups() {
    local root="${HOME}/.config-backups" count
    [[ -d "$root" ]] || return 0
    count=$(find "$root" -mindepth 1 -maxdepth 1 -type d | wc -l | tr -d ' ')
    if [[ "$count" -gt "$BACKUP_WARN_AT" ]]; then
        warn "${count} config snapshots in ${root} — delete the ones you no longer need."
    fi
    return 0
}

# The version line of a tool this script installs into LOCAL_BIN, or nothing
# if it is absent. One probe for the installers and --check, which used to type
# their own and disagree: --check asked $PATH, the installers asked LOCAL_BIN.
installed_version() {
    local bin="$LOCAL_BIN/$1"
    [[ -x "$bin" ]] || return 0
    case "$1" in
        jq)  "$bin" --version 2>/dev/null || true ;;
        k9s) "$bin" version 2>/dev/null | grep -i 'Version:' | head -1 || true ;;
        eza) "$bin" --version 2>/dev/null | sed -n 2p || true ;;
        *)   "$bin" --version 2>/dev/null | head -1 || true ;;
    esac
}

# Does an installed version line contain the pinned version? Tags carry a
# leading `v` (jq's `jq-`) that version output usually doesn't.
version_matches() {
    local want="${1#v}"
    want="${want#jq-}"
    [[ "$2" == *"$want"* ]]
}

# The first dotted version number in a line ("ripgrep 15.2.0 (rev …)" -> 15.2.0).
bare_version() {
    local re='[0-9][0-9.]*[0-9]'
    [[ "$1" =~ $re ]] && printf '%s' "${BASH_REMATCH[0]}"
    return 0
}

# Compare a pinned tag against an installed version string.
# Returns 0 (skip — already correct) or 1 (install/update needed).
at_pinned_version() {
    local name="$1" pinned_tag="$2" installed="$3"
    if [[ -z "$installed" ]]; then
        info "Installing ${name} ${pinned_tag}..."
        return 1
    fi
    if version_matches "$pinned_tag" "$installed"; then
        success "${name} ${pinned_tag} — pinned, up to date"
        return 0
    fi
    local cur; cur=$(bare_version "$installed")
    info "Changing ${name}: ${cur:-unknown} → ${pinned_tag} (pinned)"
    return 1
}

# In-place sed that works on both GNU (Linux) and BSD (macOS) sed
sed_inplace() {
    local expr="$1" file="$2"
    dry_skip "would edit $file: $expr" && return 0
    if [[ "$OS" == "macos" ]]; then
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

    dry_skip "would check out ${name} at ${ref} in $dir" && return 0

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
    local pkg="$1" os="${2:-$OS}"
    dry_skip "would install package '$pkg' via ${os}'s package manager" && return 0
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
    dry_skip "would download and install '$binary' from $url" && return 0

    local tmpdir
    tmpdir=$(mktemp -d "$WORK/dir.XXXXXX")

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

    cp "$bin_path" "$LOCAL_BIN/$binary"
    chmod 755 "$LOCAL_BIN/$binary"
    rm -rf "$tmpdir"
}

# Install a pinned release binary into LOCAL_BIN unless it is already at the
# pin. The URL is a template: {tag} is the pinned tag, {ver} the tag without its
# leading `v`, {target} the Rust triple. An archive (.tar.gz) is unpacked and
# searched for <bin>; anything else is the binary itself.
install_release() {
    local bin="$1" key="$2" url="$3" tag
    info "=== ${bin} ==="
    tag=$(pin "$key")
    at_pinned_version "$bin" "$tag" "$(installed_version "$bin")" && return 0
    url=${url//\{tag\}/$tag}
    url=${url//\{ver\}/${tag#v}}
    url=${url//\{target\}/$RUST_TARGET}
    case "$url" in
        *.tar.gz) install_from_tarball "$url" "$bin" ;;
        *)        install_from_binary_url "$url" "$bin" ;;
    esac
    success "${bin} ${tag} installed"
}

# Download a single binary file directly to LOCAL_BIN
install_from_binary_url() {
    local url="$1" binary="$2"
    dry_skip "would download '$binary' from $url" && return 0
    curl -fsSL "$url" -o "$LOCAL_BIN/$binary"
    chmod 755 "$LOCAL_BIN/$binary"
}

# -----------------------------------------------------------------------------
# Git
# -----------------------------------------------------------------------------

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
