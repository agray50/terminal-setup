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
# Startup notifications
# -----------------------------------------------------------------------------
# Several plugins report a misconfiguration via vim.notify and then carry on
# with a fallback instead of raising a Lua error. lualine does exactly this for
# an unknown theme name ("Theme `x` not found, falling back to `auto`"), so a
# wrong value is invisible to a pcall-based check and only shows up as a message
# the user has to notice. This asserts a clean start produces no notification at
# WARN level or above.
check_notifications() {
    head1 "Startup diagnostics"
    cat > "$WORK/notify.lua" <<'LUAEOF'
-- Load everything first. mini.notify REPLACES vim.notify during VeryLazy, so
-- the capture has to be installed after that or it is simply overwritten.
vim.cmd("doautocmd User VeryLazy")
vim.wait(3000)
vim.cmd.edit(vim.env.REPO_ROOT .. "/nvim/init.lua")
vim.wait(4000)

local captured = {}
local original = vim.notify
vim.notify = function(msg, level, opts)
	table.insert(captured, { msg = tostring(msg), level = level or vim.log.levels.INFO })
	return original(msg, level, opts)
end
vim.notify_once = vim.notify

pcall(function()
	require("lualine").refresh()
end)
-- lualine reports config problems through a 2s deferred vim.notify, so give it
-- time to fire rather than racing it.
vim.wait(3500)

local out = {}
for _, n in ipairs(captured) do
	if (n.level or 0) >= vim.log.levels.WARN then
		table.insert(out, "[notify] " .. n.msg:gsub("\n", " "))
	end
end

-- lualine does not report configuration problems as a Lua error, and its
-- vim.notify only says "run :LualineNotices for details". The detail lives in a
-- module-local table, so render it the way :LualineNotices does and read the
-- buffer. This is what makes a bad theme name (or any invalid option) visible:
-- lualine otherwise falls back to "auto" and carries on silently.
local ok, notices = pcall(require, "lualine.utils.notices")
if ok and notices.show_notices then
	local before = vim.api.nvim_get_current_win()
	if pcall(notices.show_notices) then
		local buf = vim.api.nvim_get_current_buf()
		for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
			-- Skip the markdown headers and blank padding the notice format adds.
			if line ~= "" and not line:match("^#") then
				table.insert(out, "[lualine] " .. line)
			end
		end
		pcall(vim.api.nvim_buf_delete, buf, { force = true })
		pcall(vim.api.nvim_set_current_win, before)
	end
end

-- :messages catches anything echoed rather than notified.
local msgs = vim.api.nvim_exec2("messages", { output = true }).output or ""
for _, line in ipairs(vim.split(msgs, "\n")) do
	if line:match("^E%d+:") then
		table.insert(out, "[messages] " .. line)
	end
end

vim.fn.writefile(out, vim.env.NOTIFYFILE)
LUAEOF
    if ! NOTIFYFILE="$WORK/notes.txt" REPO_ROOT="$REPO" \
        nvim --headless -c "luafile $WORK/notify.lua" -c "qa!" >/dev/null 2>&1; then
        fail "could not capture startup notifications"
        return
    fi
    if [[ -s "$WORK/notes.txt" ]]; then
        fail "startup produced warnings/errors:"
        sed 's/^/      /' "$WORK/notes.txt"
    else
        pass "no warnings, lualine notices or errors on a clean start"
    fi
}

# -----------------------------------------------------------------------------
# lualine theme actually resolves
# -----------------------------------------------------------------------------
check_lualine_theme() {
    head1 "lualine theme"
    local out
    out=$(nvim --headless -c 'lua
        vim.cmd("doautocmd User VeryLazy")
        vim.wait(2500)
        local theme = require("lualine.config").get_config().options.theme
        local resolves = type(theme) ~= "string" or pcall(require, "lualine.themes." .. theme)
        io.stdout:write((resolves and "OK " or "MISSING ") .. tostring(theme))
    ' -c "qa!" 2>/dev/null)
    case "$out" in
        OK\ *)      pass "theme resolves: ${out#OK }" ;;
        MISSING\ *) fail "lualine theme ${out#MISSING } does not exist — lualine silently falls back to auto" ;;
        *)          warn "could not determine lualine theme" ;;
    esac
}

# -----------------------------------------------------------------------------
# Statusline renders with its separators and icons intact
# -----------------------------------------------------------------------------
# Writing config files through a shell heredoc has twice silently stripped
# 3-byte Private Use Area codepoints (U+E000-U+F8FF) while leaving 4-byte ones
# (U+F0000+) intact, turning glyph strings into "". Neither Lua nor lualine
# complains: 'fillchars' threw an error the first time, but an empty separator
# is simply accepted and the statusline renders flat with no divisions.
# This renders the statusline and asserts the structure is actually there.
check_statusline() {
    head1 "Statusline"

    # 1. No icon/symbol/separator field in the config may be an empty string.
    local stripped
    stripped=$(grep -rn --include='*.lua' -E \
        '(left|right|added|modified|removed|error|warn|info|hint|readonly|unix|dos|mac|icon)[[:space:]]*=[[:space:]]*""' \
        "$REPO/nvim" || true)
    if [[ -n "$stripped" ]]; then
        fail "glyph fields that are empty strings (codepoints likely stripped):"
        echo "$stripped" | sed 's/^/      /'
    else
        pass "no empty glyph fields in nvim config"
    fi

    # 2. The rendered statusline must contain its separators and some content.
    local out
    out=$(REPO_ROOT="$REPO" nvim --headless -c 'lua
        vim.cmd("doautocmd User VeryLazy")
        vim.wait(2500)
        vim.cmd.edit(vim.env.REPO_ROOT .. "/nvim/init.lua")
        vim.wait(4000)
        pcall(function() require("lualine").refresh() end)
        local cfg = require("lualine.config").get_config().options
        local sep = (cfg.section_separators or {}).left or ""
        local sub = (cfg.component_separators or {}).left or ""
        vim.o.columns = 120
        local s = vim.api.nvim_eval_statusline(vim.o.statusline, { maxwidth = 120 })
        local parts = {}
        table.insert(parts, (sep ~= "" and "SEP_SET" or "SEP_EMPTY"))
        table.insert(parts, (sub ~= "" and "SUB_SET" or "SUB_EMPTY"))
        table.insert(parts, (sep ~= "" and s.str:find(sep, 1, true)) and "SEP_RENDERED" or "SEP_ABSENT")
        table.insert(parts, (#s.str > 20) and "HAS_CONTENT" or "EMPTY_LINE")
        io.stdout:write(table.concat(parts, " "))
    ' -c "qa!" 2>/dev/null)

    case "$out" in
        *SEP_EMPTY*|*SUB_EMPTY*)
            fail "statusline separators are empty strings — it will render flat (glyphs stripped?)" ;;
        *SEP_ABSENT*)
            fail "separators are configured but do not appear in the rendered statusline" ;;
        *EMPTY_LINE*)
            fail "statusline rendered with almost no content" ;;
        *SEP_RENDERED*HAS_CONTENT*)
            pass "statusline renders with separators and content" ;;
        *)
            warn "could not evaluate the statusline (got: ${out:-nothing})" ;;
    esac
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
    notify)   check_notifications ;;
    theme)    check_lualine_theme ;;
    statusline) check_statusline ;;
    keymaps)  check_keymaps ;;
    all)      check_lua; check_shell; check_lockfile; check_lualine_theme
              check_statusline; check_notifications; check_keymaps ;;
    *)        echo "Usage: $0 [all|lua|shell|lock|theme|statusline|notify|keymaps]"; exit 2 ;;
esac

echo ""
if [[ $FAILURES -eq 0 ]]; then
    echo -e "${GREEN}All checks passed.${NC}"
    exit 0
fi
echo -e "${RED}${FAILURES} check(s) failed.${NC}"
exit 1
