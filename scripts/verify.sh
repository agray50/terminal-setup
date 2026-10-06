#!/usr/bin/env bash
# =============================================================================
# verify.sh — check that the config is internally consistent and functional.
# =============================================================================
# Run after changing anything in nvim/, or before committing. This is the check
# that was previously missing and let the README drift away from the config.
#
#   ./scripts/verify.sh            all checks
#   ./scripts/verify.sh keymaps    just the README/keymap consistency check
#
# Exits non-zero if any check fails, so it works in a pre-commit hook or CI.
# =============================================================================

set -uo pipefail

REPO="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
pass() { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; FAILURES=$((FAILURES + 1)); }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
head1() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

FAILURES=0
ONLY="${1:-all}"

# -----------------------------------------------------------------------------
# Lua syntax + formatting
# -----------------------------------------------------------------------------
check_lua() {
    head1 "Lua"
    local bad=0
    while IFS= read -r f; do
        if ! nvim --headless -c "lua local ok,e=loadfile('$f'); if not ok then io.stderr:write(tostring(e)) ; vim.cmd('cq') end" -c qa 2>>"$WORK/lua.err"; then
            fail "syntax error in $f"
            bad=1
        fi
    done < <(find "$REPO/nvim" -name '*.lua' | sort)
    [[ $bad -eq 0 ]] && pass "all Lua files parse"

    local stylua="$HOME/.local/share/nvim/mason/bin/stylua"
    if [[ -x "$stylua" ]]; then
        if "$stylua" --check "$REPO/nvim" >/dev/null 2>&1; then
            pass "stylua formatting clean"
        else
            fail "stylua would reformat files — run: stylua nvim/"
        fi
    else
        warn "stylua not installed; skipping format check"
    fi
}

# -----------------------------------------------------------------------------
# Shell
# -----------------------------------------------------------------------------
check_shell() {
    head1 "Shell"
    # setup.sh must parse under bash 3.2 — macOS still ships it as /bin/bash and
    # setup.sh has to bootstrap before it can install anything newer.
    if /bin/bash -n "$REPO/setup.sh" 2>/dev/null; then
        pass "setup.sh parses under bash $(/bin/bash --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)"
    else
        fail "setup.sh does NOT parse under /bin/bash (bash 3.2 compatibility broken)"
    fi
    if bash -n "$REPO/setup.sh" 2>/dev/null; then
        pass "setup.sh parses under current bash"
    else
        fail "setup.sh syntax error"
    fi

    local sc="$HOME/.local/share/nvim/mason/bin/shellcheck"
    if [[ -x "$sc" ]]; then
        if "$sc" -S warning "$REPO/setup.sh" "$REPO/scripts/verify.sh" >/dev/null 2>&1; then
            pass "shellcheck clean"
        else
            fail "shellcheck findings:"
            "$sc" -S warning "$REPO/setup.sh" "$REPO/scripts/verify.sh" 2>&1 | sed 's/^/      /' | head -20
        fi
    else
        warn "shellcheck not installed; skipping"
    fi
}

# -----------------------------------------------------------------------------
# versions.lock integrity
# -----------------------------------------------------------------------------
check_lockfile() {
    head1 "versions.lock"
    local lock="$REPO/versions.lock"
    if [[ ! -f "$lock" ]]; then
        fail "versions.lock missing"
        return
    fi
    local count
    count=$(grep -cE '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=' "$lock")
    pass "$count pinned versions"

    # Every pin must have a non-empty value.
    local empty
    empty=$(grep -E '^[[:space:]]*[A-Za-z_][A-Za-z0-9_]*=[[:space:]]*$' "$lock" || true)
    if [[ -n "$empty" ]]; then
        fail "pins with empty values: $empty"
    else
        pass "no empty pins"
    fi

    # The generated Mason pin must agree with the lockfile.
    local want have
    want=$(sed -n 's/^MASON_REGISTRY=\(.*\)/\1/p' "$lock" | head -1)
    have=$(sed -n 's/.*mason-registry@\([^"]*\)".*/\1/p' "$REPO/nvim/lua/mason-pin.lua" | head -1)
    if [[ "$want" == "$have" ]]; then
        pass "mason-pin.lua matches versions.lock ($want)"
    else
        fail "mason-pin.lua is stale: lock=$want generated=$have — run ./setup.sh"
    fi

    # Nothing in the install path may resolve a version from the network.
    if grep -nE '^\s*[a-z_]+\(\)' "$REPO/setup.sh" >/dev/null && \
       awk '/^do_update\(\)/{u=1} /^resolve_latest\(\)/{u=1} /^resolver_for\(\)/{u=1} /^github_latest|^mason_latest/{u=1} /^install_|^setup_/{u=0} u==0 && /github_latest_tag|mason_latest_registry|github_latest_commit/{print NR": "$0}' "$REPO/setup.sh" | grep -q .; then
        fail "install path resolves versions from the network (should only happen in --update)"
    else
        pass "install path never resolves versions from the network"
    fi
}

# -----------------------------------------------------------------------------
# Keymaps: every key documented in the README must exist in the live config
# -----------------------------------------------------------------------------
check_keymaps() {
    head1 "Keymaps vs README"
    cat > "$WORK/dump.lua" <<'LUAEOF'
-- Dump every mapping, global AND buffer-local.
--
-- Many keys (LSP actions, gitsigns hunks, dadbod query execution) only exist
-- once a provider attaches to a buffer, so this opens real buffers and waits
-- for them rather than dumping from an empty editor — otherwise ~30 genuinely
-- present keys look missing.
vim.cmd("Lazy! load " .. table.concat({
	"which-key.nvim", "fzf-lua", "trouble.nvim", "nvim-dap", "neotest",
	"conform.nvim", "nvim-lint", "todo-comments.nvim", "flash.nvim",
	"mini.nvim", "neo-tree.nvim", "gitsigns.nvim", "diffview.nvim",
	"vim-fugitive", "nvim-treesitter-textobjects", "vim-dadbod-ui",
}, " "))
vim.cmd("doautocmd User VeryLazy")
vim.wait(2000)

local out, seen = {}, {}
local function add(lhs)
	if lhs and lhs ~= "" and not seen[lhs] then
		seen[lhs] = true
		table.insert(out, lhs)
	end
end

local function collect()
	for _, mode in ipairs({ "n", "v", "x", "o", "i", "t", "c" }) do
		for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
			add(m.lhs)
		end
		for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, mode)) do
			add(m.lhs)
		end
	end
end

-- A tracked Lua file in this repo: attaches lua_ls (LSP keys) and, because the
-- repo is a git worktree, gitsigns (hunk keys).
vim.cmd.edit(vim.env.REPO_ROOT .. "/nvim/init.lua")
vim.wait(12000, function()
	return #vim.lsp.get_clients({ bufnr = 0 }) > 0
end, 250)
vim.wait(2500) -- let gitsigns attach and LspAttach keymaps register
collect()

-- A SQL buffer registers the dadbod query-execution keys.
vim.cmd("enew")
vim.bo.filetype = "sql"
vim.wait(1200)
collect()

vim.fn.writefile(out, vim.env.DUMPFILE)
LUAEOF
    if ! DUMPFILE="$WORK/keys.txt" REPO_ROOT="$REPO" \
        nvim --headless -c "luafile $WORK/dump.lua" -c "qa!" >/dev/null 2>&1; then
        fail "could not dump keymaps"
        return
    fi
    local n; n=$(wc -l < "$WORK/keys.txt" | tr -d ' ')
    pass "dumped $n live mappings"

    KEYS_FILE="$WORK/keys.txt" README_FILE="$REPO/README.md" python3 "$REPO/scripts/check_readme_keys.py"
    if [[ $? -eq 0 ]]; then
        pass "every key documented in README.md exists in the config"
    else
        fail "README documents keys that do not exist (see above)"
    fi
}

case "$ONLY" in
    lua)      check_lua ;;
    shell)    check_shell ;;
    lock)     check_lockfile ;;
    keymaps)  check_keymaps ;;
    all)      check_lua; check_shell; check_lockfile; check_keymaps ;;
    *)        echo "Usage: $0 [all|lua|shell|lock|keymaps]"; exit 2 ;;
esac

echo ""
if [[ $FAILURES -eq 0 ]]; then
    echo -e "${GREEN}All checks passed.${NC}"
    exit 0
fi
echo -e "${RED}${FAILURES} check(s) failed.${NC}"
exit 1
