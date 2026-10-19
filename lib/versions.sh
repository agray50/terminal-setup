# shellcheck shell=bash
# --update and --check for setup.sh. The only code in this repo that resolves
# versions from the network, and only ever from --update: scripts/verify.sh
# asserts the network resolvers below are called from resolve_latest alone, and
# resolve_latest only from do_update. Sourced after lib/common.sh.

# -----------------------------------------------------------------------------
# Network resolvers -- ONLY called by --update
# -----------------------------------------------------------------------------

# Resolve latest release tag from a GitHub repo (e.g. "v1.2.3" or "14.1.1").
# ONLY called by --update. The install path never resolves versions.
github_latest_tag() {
    curl -fsLI --retry 2 --retry-delay 1 --retry-connrefused \
        "https://github.com/$1/releases/latest" -o /dev/null -w '%{url_effective}' 2>/dev/null \
        | sed 's|.*/tag/||'
}

# Latest tag (not release) — for repos that tag but never publish releases.
github_latest_tag_only() {
    curl -fsL --retry 2 --retry-delay 1 --retry-connrefused \
        "https://api.github.com/repos/$1/tags?per_page=1" 2>/dev/null \
        | sed -n 's/.*"name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

# Latest commit SHA on the default branch — for repos with no tags at all.
github_latest_commit() {
    curl -fsL --retry 2 --retry-delay 1 --retry-connrefused \
        "https://api.github.com/repos/$1/commits?per_page=1" 2>/dev/null \
        | sed -n 's/.*"sha"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
}

# Latest mason-registry snapshot tag.
mason_latest_registry() {
    curl -fsL --retry 2 --retry-delay 1 --retry-connrefused \
        "https://api.github.com/repos/mason-org/mason-registry/releases?per_page=1" 2>/dev/null \
        | sed -n 's/.*"tag_name"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' | head -1
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
    curl -fsL --retry 2 --retry-delay 1 --retry-connrefused \
        "https://api.github.com/repos/${repo}/tags?per_page=100" 2>/dev/null \
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

# Every resolver above is a `curl | sed` pipeline and this script runs under
# `set -euo pipefail`, so `latest=$(resolve_latest ...)` propagated curl's exit
# status: one transient failure part-way through --update (curl 56, "failure
# receiving network data", observed against GitHub mid-run) aborted the entire
# run with a bare exit code, no message, and versions.lock untouched. Swallow
# the status and return an empty string instead — do_update already treats ""
# as unresolved, keeps the existing pin, warns, and counts it.
resolve_latest() {
    local spec="$1" kind repo out=""
    kind="${spec%%:*}"
    repo="${spec#*:}"
    case "$kind" in
        release) out=$(github_latest_tag "$repo" || true) ;;
        tag)     out=$(github_latest_tag_only "$repo" || true) ;;
        commit)  out=$(github_latest_commit "$repo" || true) ;;
        mason)   out=$(mason_latest_registry || true) ;;
    esac
    printf '%s' "$out"
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
    local tmp; tmp=$(mktemp "$WORK/tmp.XXXXXX")
    # Read the <KEY>_CONSTRAINT pins up front rather than re-scanning the file
    # being looped over once per line.
    local constraints
    constraints=$(grep -E '^[[:space:]]*[A-Za-z0-9_]+_CONSTRAINT[[:space:]]*=' "$LOCKFILE" || true)

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
        constraint=$(sed -n "s/^[[:space:]]*${key}_CONSTRAINT[[:space:]]*=[[:space:]]*\\([^#]*\\).*/\\1/p" <<<"$constraints" \
            | head -1 | sed 's/[[:space:]]*$//')
        if [[ -n "$constraint" && -n "$latest" ]]; then
            if [[ "${latest#v}" != "${constraint}"* ]]; then
                local series
                series=$(resolve_latest_in_series "$spec" "$constraint" || true)
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
    # Guard required: bash 3.2 (macOS /bin/bash) treats "${a[@]}" on an empty
    # array as unbound under `set -u`.
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

    local drift=0 row name bin key pinned installed
    for row in neovim:nvim:NVIM_VERSION fzf:fzf:FZF_VERSION ripgrep:rg:RIPGREP_VERSION \
        fd:fd:FD_VERSION bat:bat:BAT_VERSION jq:jq:JQ_VERSION yq:yq:YQ_VERSION \
        k9s:k9s:K9S_VERSION lazygit:lazygit:LAZYGIT_VERSION delta:delta:DELTA_VERSION \
        tree-sitter:tree-sitter:TREE_SITTER_CLI_VERSION; do
        IFS=: read -r name bin key <<<"$row"
        pinned=$(pin "$key")
        installed=$(installed_version "$bin")
        if [[ -z "$installed" ]]; then
            printf "  %-16s %-22s %s\n" "$name" "$pinned" "NOT INSTALLED"
            drift=$((drift + 1))
        elif version_matches "$pinned" "$installed"; then
            printf "  %-16s %-22s ok\n" "$name" "$pinned"
        else
            printf "  %-16s %-22s DRIFT (installed: %s)\n" "$name" "$pinned" "$(bare_version "$installed")"
            drift=$((drift + 1))
        fi
    done

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
