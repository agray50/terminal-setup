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
# jdtls keeps writing to its workspace for a moment after nvim exits, so a
# single rm races with it and leaves the temp tree behind. Retry once.
cleanup() {
    rm -rf "$WORK" 2>/dev/null && return
    sleep 2
    rm -rf "$WORK" 2>/dev/null || true
}
trap cleanup EXIT

# Shared with setup.sh (git_version_at_least). Sourced before the helpers below
# so this script's own pass/fail/warn output format wins.
# shellcheck source=../lib/common.sh
source "$REPO/lib/common.sh"

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'
pass() { echo -e "  ${GREEN}✓${NC} $1"; }
fail() { echo -e "  ${RED}✗${NC} $1"; FAILURES=$((FAILURES + 1)); }
warn() { echo -e "  ${YELLOW}!${NC} $1"; }
indent() { sed 's/^/      /'; }
head1() { echo -e "\n${BLUE}=== $1 ===${NC}"; }

FAILURES=0
ONLY="${1:-all}"

# -----------------------------------------------------------------------------
# Lua syntax + formatting
# -----------------------------------------------------------------------------
check_lua() {
    head1 "Lua"
    # One nvim parses every file (`-l` runs a script without loading the
    # config); one process per file cost ~2s for no extra coverage.
    cat > "$WORK/parse.lua" <<'LUAEOF'
for _, f in ipairs(arg) do
	local ok, e = loadfile(f)
	if not ok then
		print(e)
	end
end
LUAEOF
    local errs
    errs=$(find "$REPO/nvim" -name '*.lua' -print0 | xargs -0 nvim -l "$WORK/parse.lua" 2>&1)
    if [[ -n "$errs" ]]; then
        fail "Lua syntax errors:"
        indent <<<"$errs"
    else
        pass "all Lua files parse"
    fi

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
    # setup.sh and its lib/ must parse under bash 3.2 — macOS still ships it as
    # /bin/bash and setup.sh has to bootstrap before it can install anything
    # newer. `bash -n` does not follow `source`, so each file is checked itself.
    local -a files=("$REPO/setup.sh" "$REPO"/lib/*.sh)
    local f bad32="" bad=""
    for f in "${files[@]}"; do
        /bin/bash -n "$f" 2>/dev/null || bad32="$bad32 ${f#"$REPO"/}"
        bash -n "$f" 2>/dev/null || bad="$bad ${f#"$REPO"/}"
    done
    if [[ -z "$bad32" ]]; then
        pass "${#files[@]} files parse under bash $(/bin/bash --version | head -1 | grep -oE '[0-9]+\.[0-9]+' | head -1)"
    else
        fail "does NOT parse under /bin/bash (bash 3.2 compatibility broken):$bad32"
    fi
    if [[ -z "$bad" ]]; then
        pass "${#files[@]} files parse under current bash"
    else
        fail "syntax error:$bad"
    fi

    local sc="$HOME/.local/share/nvim/mason/bin/shellcheck" findings
    if [[ -x "$sc" ]]; then
        if findings=$("$sc" -x -S warning "${files[@]}" "$REPO/scripts/verify.sh" 2>&1); then
            pass "shellcheck clean"
        else
            fail "shellcheck findings:"
            indent <<<"$findings" | head -20
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

    # Nothing in the install path may resolve a version from the network: the
    # network resolvers are called only by resolve_latest, and resolve_latest*
    # only by do_update (--update). Tracks the enclosing function by its
    # definition line, so it holds wherever the functions live.
    local leaks
    leaks=$(find "$REPO/setup.sh" "$REPO/lib" -name '*.sh' 2>/dev/null | sort | xargs awk '
        /^[A-Za-z_][A-Za-z0-9_]*\(\)/ { fn = $0; sub(/\(.*/, "", fn); next }
        /^[[:space:]]*#/ { next }
        /(^|[^A-Za-z0-9_])(github_latest_tag|github_latest_tag_only|github_latest_commit|mason_latest_registry)([^A-Za-z0-9_]|$)/ && fn != "resolve_latest" { print FILENAME ":" FNR ": " fn }
        /(^|[^A-Za-z0-9_])resolve_latest(_in_series)?([^A-Za-z0-9_]|$)/ && fn != "do_update" { print FILENAME ":" FNR ": " fn }
    ')
    if [[ -n "$leaks" ]]; then
        fail "versions resolved from the network outside --update:"
        indent <<<"$leaks"
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
# One headless session shared by the theme, statusline and notify checks. They
# used to start three, each with its own fixed sleeps (~20s between them, under
# 1s of real work). Waits now end as soon as their condition holds.
#
# Writes $WORK/ui.txt: "THEME OK|MISSING <name>", "STATUS <flags>" and one
# "NOTE <text>" per problem. Run once; later callers reuse the file.
ui_probe() {
    [[ -f "$WORK/ui.txt" ]] && return 0
    cat > "$WORK/ui.lua" <<'LUAEOF'
local out = {}

-- Capture before anything else happens: earlier versions installed this after
-- ~7s of waiting, so every notification sent before then went unseen.
-- mini.notify REPLACES vim.notify during VeryLazy, so wrap whatever it leaves.
vim.cmd("doautocmd User VeryLazy")
local captured = {}
local original = vim.notify
vim.notify = function(msg, level, opts)
	table.insert(captured, { msg = tostring(msg), level = level or vim.log.levels.INFO })
	return original(msg, level, opts)
end
vim.notify_once = vim.notify

-- A real tracked file: lua_ls and gitsigns attach to it, as in daily use.
vim.cmd.edit(vim.env.REPO_ROOT .. "/nvim/init.lua")
vim.wait(10000, function()
	return #vim.lsp.get_clients({ bufnr = 0 }) > 0 and vim.b.gitsigns_status_dict ~= nil
end, 50)
-- Servers report startup problems just after attaching, not during it.
vim.wait(500)

-- Theme: lualine falls back to "auto" on an unknown name and carries on.
local cfg = require("lualine.config").get_config().options
local theme = cfg.theme
local resolves = type(theme) ~= "string" or pcall(require, "lualine.themes." .. theme)
table.insert(out, (resolves and "THEME OK " or "THEME MISSING ") .. tostring(theme))

-- Statusline: separators configured, and actually present once rendered.
pcall(function()
	require("lualine").refresh()
end)
local sep = (cfg.section_separators or {}).left or ""
local sub = (cfg.component_separators or {}).left or ""
vim.o.columns = 120
local s = vim.api.nvim_eval_statusline(vim.o.statusline, { maxwidth = 120 })
table.insert(out, "STATUS " .. table.concat({
	sep ~= "" and "SEP_SET" or "SEP_EMPTY",
	sub ~= "" and "SUB_SET" or "SUB_EMPTY",
	(sep ~= "" and s.str:find(sep, 1, true)) and "SEP_RENDERED" or "SEP_ABSENT",
	#s.str > 20 and "HAS_CONTENT" or "EMPTY_LINE",
}, " "))

-- Notifications at WARN or above.
for _, n in ipairs(captured) do
	if n.level >= vim.log.levels.WARN then
		table.insert(out, "NOTE [notify] " .. n.msg:gsub("\n", " "))
	end
end

-- lualine does not report configuration problems as a Lua error, and its
-- vim.notify (deferred 2s) only says "run :LualineNotices for details". The
-- detail lives in a module-local table, so render it the way :LualineNotices
-- does and read the buffer -- no need to wait out the deferred notify.
local ok, notices = pcall(require, "lualine.utils.notices")
if ok and notices.show_notices and pcall(notices.show_notices) then
	local buf = vim.api.nvim_get_current_buf()
	for _, line in ipairs(vim.api.nvim_buf_get_lines(buf, 0, -1, false)) do
		-- Skip the markdown headers and blank padding the notice format adds.
		if line ~= "" and not line:match("^#") then
			table.insert(out, "NOTE [lualine] " .. line)
		end
	end
end

-- :messages catches anything echoed rather than notified.
local msgs = vim.api.nvim_exec2("messages", { output = true }).output or ""
for _, line in ipairs(vim.split(msgs, "\n")) do
	if line:match("^E%d+:") then
		table.insert(out, "NOTE [messages] " .. line)
	end
end

vim.fn.writefile(out, vim.env.UIFILE)
LUAEOF
    UIFILE="$WORK/ui.txt" REPO_ROOT="$REPO" \
        nvim --headless -c "luafile $WORK/ui.lua" -c "qa!" >/dev/null 2>&1
    [[ -f "$WORK/ui.txt" ]] || : > "$WORK/ui.failed"
}

check_notifications() {
    head1 "Startup diagnostics"
    ui_probe
    if [[ -f "$WORK/ui.failed" ]]; then
        fail "could not capture startup notifications"
        return
    fi
    local notes
    notes=$(sed -n 's/^NOTE //p' "$WORK/ui.txt")
    if [[ -n "$notes" ]]; then
        fail "startup produced warnings/errors:"
        indent <<<"$notes"
    else
        pass "no warnings, lualine notices or errors on a clean start"
    fi
}

# -----------------------------------------------------------------------------
# lualine theme actually resolves
# -----------------------------------------------------------------------------
check_lualine_theme() {
    head1 "lualine theme"
    ui_probe
    local out
    out=$(sed -n 's/^THEME //p' "$WORK/ui.txt" 2>/dev/null)
    case "$out" in
        OK\ *)      pass "theme resolves: ${out#OK }" ;;
        MISSING\ *) fail "lualine theme ${out#MISSING } does not exist — lualine silently falls back to auto" ;;
        *)          warn "could not determine lualine theme" ;;
    esac
}

# -----------------------------------------------------------------------------
# Shared gitconfig stays compatible with the oldest supported git
# -----------------------------------------------------------------------------
# This repo is used on macOS (git 2.50) and Ubuntu 20.04 (git 2.24). Git
# VALIDATES some config values rather than ignoring unknown ones, so a value the
# local git does not understand makes EVERY git command fail:
#
#   error: unknown style 'zdiff3' given for 'merge.conflictstyle'
#
# Those settings must live in the generated per-machine git/gitconfig.local, not
# in the committed git/gitconfig. This check enforces that.
MIN_GIT="2.24"

check_gitconfig_compat() {
    head1 "gitconfig compatibility (min git ${MIN_GIT})"
    local cfg="$REPO/git/gitconfig"
    [[ -f "$cfg" ]] || { fail "git/gitconfig missing"; return; }

    # "setting=value|minimum git version" — values git validates and rejects.
    local -a gated=(
        "conflictstyle *= *zdiff3|2.35"
        "autocorrect *= *prompt|2.37"
    )
    local bad=0 entry pattern minver hit
    for entry in "${gated[@]}"; do
        pattern="${entry%%|*}"
        minver="${entry##*|}"
        hit=$(grep -nE "^[[:space:]]*${pattern}" "$cfg" || true)
        if [[ -n "$hit" ]]; then
            fail "needs git >= ${minver}, but git/gitconfig is shared with git ${MIN_GIT} machines:"
            indent <<<"$hit"
            echo "      -> move it to setup_gitconfig_version in setup.sh"
            bad=1
        fi
    done
    [[ $bad -eq 0 ]] && pass "no version-gated values in the committed gitconfig"

    # The generated file must exist and must match the local git.
    local local_cfg="$REPO/git/gitconfig.local"
    if [[ ! -f "$local_cfg" ]]; then
        warn "git/gitconfig.local not generated yet — run ./setup.sh"
        return
    fi
    local want
    if git_version_at_least 2.35; then want="zdiff3"; else want="diff3"; fi
    if grep -qE "^[[:space:]]*conflictstyle = ${want}$" "$local_cfg"; then
        pass "gitconfig.local matches local git ($(git --version | sed -n 's/^git version //p')): conflictstyle=${want}"
    else
        fail "gitconfig.local does not match the local git version — re-run ./setup.sh"
    fi

    # Prove git can actually read the whole config.
    if git -C "$REPO" status >/dev/null 2>&1; then
        pass "git reads the resulting config without error"
    else
        fail "git errors reading the config:"
        git -C "$REPO" status 2>&1 | indent | head -3
    fi
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
        indent <<<"$stripped"
    else
        pass "no empty glyph fields in nvim config"
    fi

    # 2. The rendered statusline must contain its separators and some content.
    ui_probe
    local out
    out=$(sed -n 's/^STATUS //p' "$WORK/ui.txt" 2>/dev/null)

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

-- One "lhs<TAB>desc<TAB>rhs" line per mapping, for the README check. The rhs
-- matters because plugins' own mappings often have no desc -- the broken <C-\\>
-- was vim-tmux-navigator's, an rhs of :TmuxNavigatePrevious.
local out, seen = {}, {}
local function field(v)
	return (v or ""):gsub("[\t\n]", " ")
end
local function add(m)
	if m.lhs and m.lhs ~= "" and not seen[m.lhs] then
		seen[m.lhs] = true
		table.insert(out, table.concat({ m.lhs, field(m.desc), field(m.rhs) }, "\t"))
	end
end

local function collect()
	for _, mode in ipairs({ "n", "v", "x", "o", "i", "t", "c" }) do
		for _, m in ipairs(vim.api.nvim_get_keymap(mode)) do
			add(m)
		end
		for _, m in ipairs(vim.api.nvim_buf_get_keymap(0, mode)) do
			add(m)
		end
	end
end

-- A tracked Lua file in this repo: attaches lua_ls (LSP keys) and, because the
-- repo is a git worktree, gitsigns (hunk keys).
vim.cmd.edit(vim.env.REPO_ROOT .. "/nvim/init.lua")
-- Done once both have mapped the buffer: gitsigns' on_attach (]c) and the
-- LspAttach handler (gd). gitsigns' status dict appears before its keys do.
local function buffer_mapped(lhs)
	return vim.fn.maparg(lhs, "n", false, true).buffer == 1
end
vim.wait(12000, function()
	return buffer_mapped("]c") and buffer_mapped("gd")
end, 50)
collect()

-- A SQL buffer registers the dadbod query-execution keys.
vim.cmd("enew")
vim.bo.filetype = "sql"
vim.wait(3000, function()
	return #vim.api.nvim_buf_get_keymap(0, "n") > 0
end, 50)
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

    if KEYS_FILE="$WORK/keys.txt" README_FILE="$REPO/README.md" python3 "$REPO/scripts/check_readme_keys.py"; then
        pass "README and live keymaps agree: documented keys exist and do what it says, described leader keys are documented"
    else
        fail "README and live keymaps disagree (see above)"
    fi

    # Pressing the keys, not just finding them: nvim 0.12 rejects a <C-U>
    # inside <cmd> (E492), which left every <C-h/j/k/l> mapped but inert.
    # Outside tmux the navigator falls back to wincmd, so a vsplit is enough.
    cat > "$WORK/panes.lua" <<'LUAEOF'
vim.cmd("Lazy! load vim-tmux-navigator")
vim.cmd("vsplit")
vim.cmd("wincmd h")
local function press(key)
	local before = vim.api.nvim_get_current_win()
	vim.v.errmsg = ""
	vim.api.nvim_feedkeys(vim.keycode(key), "xt", false)
	return vim.api.nvim_get_current_win() ~= before and vim.v.errmsg == ""
end
local ok = press("<C-l>") and press("<C-h>")
vim.fn.writefile({ ok and "ok" or ("fail: " .. vim.v.errmsg) }, vim.env.OUTFILE)
LUAEOF
    local out
    out=$(env -u TMUX OUTFILE="$WORK/panes.txt" \
        nvim --headless -c "luafile $WORK/panes.lua" -c "qa!" >/dev/null 2>&1; cat "$WORK/panes.txt" 2>/dev/null)
    if [[ "$out" == ok ]]; then
        pass "<C-h>/<C-l> move between splits"
    else
        fail "<C-h>/<C-l> do not move between splits (${out:-no result})"
    fi
}

# -----------------------------------------------------------------------------
# Shell init blocks (nvm / pyenv / goenv)
# -----------------------------------------------------------------------------
# These blocks caused the worst bug in this repo's history: each stub delegated
# its own `unset -f` to a shared `_<tool>_lazy_load` helper, so in any shell
# where that helper did not survive -- notably tools that snapshot an rc file
# and drop `_`-prefixed functions, treating them as completion helpers -- the
# stub called a missing loader, never unset itself, and then called itself.
# `node`, `python3`, `go` and eight other everyday commands recursed until zsh
# ran out of stack.
#
# Two properties are asserted, against `./setup.sh --print-block <tool>` so this
# tests what a *fresh* machine gets rather than whatever is in ~/.zshrc now:
#
#   1. No stub can recurse, even with every helper it might rely on deleted and
#      with the real binary absent from PATH.
#   2. The interpreter directories land on PATH eagerly. Behind a shell function
#      they were invisible to every process that does not source an rc file --
#      nvim's language servers and debug adapters among them, which is why
#      basedpyright and debugpy were silently running against the system Python
#      rather than the pyenv-selected one.
check_shell_init() {
    head1 "Shell init blocks"

    if ! command -v zsh >/dev/null 2>&1; then
        warn "zsh not found; skipping shell init checks"
        return
    fi
    mkdir -p "$WORK/emptyhome"

    local tool block
    for tool in nvm pyenv goenv; do
        block="$WORK/$tool.zsh"
        # Exactly what setup.sh writes into a fresh ~/.zshrc.
        if ! "$REPO/setup.sh" --print-block "$tool" > "$block" 2>/dev/null || [[ ! -s "$block" ]]; then
            fail "$tool: ./setup.sh --print-block $tool produced nothing"
            continue
        fi

        # Every public stub the block defines, e.g. "pyenv() {" -> pyenv.
        local -a stubs
        # shellcheck disable=SC2207
        stubs=($(grep -oE '^[a-z][a-z0-9_]*\(\)' "$block" | tr -d '()'))
        if [[ ${#stubs[@]} -eq 0 ]]; then
            fail "$tool: block defines no stub functions"
            continue
        fi

        local fn recursed=0 out
        for fn in "${stubs[@]}"; do
            # Hostile conditions: helper functions deleted, real binary absent,
            # and the tool root pointed somewhere empty. FUNCNEST turns runaway
            # recursion into a single identifiable error instead of a hang.
            out=$(FUNCNEST=40 HOME="$WORK/emptyhome" zsh -c "
                source '$block' 2>/dev/null
                for f in \${(k)functions}; do [[ \$f == _* ]] && unset -f \$f; done
                PATH=/usr/bin:/bin
                $fn --version
            " 2>&1)
            if grep -q 'maximum nested function level' <<<"$out"; then
                fail "$tool: \`$fn\` recurses when its helpers are missing"
                recursed=1
            fi
        done
        [[ $recursed -eq 0 ]] && pass "$tool: ${#stubs[@]} stub(s) terminate without recursion"
    done

    # Property 2 -- the directories a non-shell consumer needs must be exported,
    # not hidden behind a function call. Checked only where the tool is actually
    # installed, so this stays meaningful on a machine that skipped one.
    local -a want=()
    [[ -d "$HOME/.pyenv/shims" ]] && want+=("pyenv:$HOME/.pyenv/shims")
    [[ -d "$HOME/.goenv/shims" ]] && want+=("goenv:$HOME/.goenv/shims")
    [[ -d "$HOME/.nvm/versions/node" ]] && want+=("nvm:/.nvm/versions/node/")

    if [[ ${#want[@]} -eq 0 ]]; then
        warn "no version managers installed; skipping PATH check"
        return
    fi

    # Source all three blocks in one shell, exactly as .zshrc does.
    local newpath
    newpath=$(zsh -c "
        PATH=/usr/bin:/bin
        source '$WORK/nvm.zsh'; source '$WORK/pyenv.zsh'; source '$WORK/goenv.zsh'
        print -r -- \$PATH
    " 2>/dev/null)

    local entry name dir
    for entry in "${want[@]}"; do
        name="${entry%%:*}"; dir="${entry#*:}"
        if [[ ":$newpath:" == *"$dir"* ]]; then
            pass "$name: interpreter directory exported to PATH eagerly"
        else
            fail "$name: $dir never reaches PATH — non-shell consumers get the system version"
        fi
    done
}

# -----------------------------------------------------------------------------
# Per-language support
# -----------------------------------------------------------------------------
# The check that catches the original complaint -- "random errors because
# something has gone out of date or isn't working correctly". Every other check
# here is static; this one stands up a realistic mini-project and asserts, for
# each language in the stack, that the language server actually attaches, that
# conform would run the intended formatter, and that nvim-lint has a linter
# whose binary exists.
#
# The fixture carries real root markers (package.json, go.mod, Cargo.toml,
# pom.xml, Chart.yaml, .git) because most servers refuse to start without one --
# a bare scratch file in /tmp silently proves nothing.
#
# This is the slowest check by far (jdtls alone takes ~30s), so it is excluded
# from `all` and run explicitly: ./scripts/verify.sh languages
# Builds the shared fixture project once per run; both check_languages and
# check_dap stand their assertions up against it.
make_fixture() {
    local fx="$WORK/fixture"
    [[ -d "$fx/.git" ]] && return 0
    mkdir -p "$fx"/{src,k8s,chart/templates,sql,sql-noconn,rs/src,java/src/main/java}

    printf '{ "name": "fixture", "version": "1.0.0", "dependencies": { "react": "^18.0.0" } }\n' > "$fx/package.json"
    printf '{ "compilerOptions": { "jsx": "react-jsx", "strict": true, "target": "ES2020" } }\n' > "$fx/tsconfig.json"
    printf 'export const App = () => {\n  const x: number = 1;\n  return <div className="p-4">{x}</div>;\n};\n' > "$fx/src/App.tsx"
    printf 'export function add(a: number, b: number): number { return a + b }\n' > "$fx/src/util.ts"
    printf 'import os\n\n\ndef main() -> None:\n    print(os.getcwd())\n' > "$fx/main.py"
    printf '[project]\nname = "fixture"\nversion = "0.1.0"\n' > "$fx/pyproject.toml"
    printf 'module fixture\n\ngo 1.24\n' > "$fx/go.mod"
    printf 'package main\n\nimport "fmt"\n\nfunc main() { fmt.Println("hi") }\n' > "$fx/main.go"
    printf 'terraform {\n  required_version = ">= 1.0"\n}\n\nresource "null_resource" "a" {}\n' > "$fx/main.tf"
    printf '#!/usr/bin/env bash\nset -euo pipefail\necho "hello"\n' > "$fx/script.sh"
    printf 'FROM alpine:3.20\nRUN apk add --no-cache curl\n' > "$fx/Dockerfile"
    printf 'key: value\nlist:\n  - a\n  - b\n' > "$fx/conf.yaml"
    printf '[tool]\nname = "x"\n' > "$fx/conf.toml"
    printf '# Title\n\nSome text.\n' > "$fx/README.md"
    printf '.btn { color: red; }\n' > "$fx/style.css"
    printf 'SELECT 1;\n' > "$fx/sql/q.sql"
    # sqls only starts once it has a connection (see lsp-config.lua).
    printf 'connections:\n  - driver: sqlite3\n    dataSourceName: %s/sql/fixture.db\n' "$fx" > "$fx/sql/config.yml"
    printf 'SELECT 1;\n' > "$fx/sql-noconn/q.sql"
    printf 'local M = {}\nreturn M\n' > "$fx/conf.lua"
    printf 'query { user { id } }\n' > "$fx/q.graphql"
    printf 'apiVersion: apps/v1\nkind: Deployment\nmetadata:\n  name: a\nspec:\n  replicas: 1\n' > "$fx/k8s/deployment.yaml"
    printf 'apiVersion: v2\nname: fixture\nversion: 0.1.0\n' > "$fx/chart/Chart.yaml"
    printf 'replicaCount: 1\n' > "$fx/chart/values.yaml"
    printf 'apiVersion: v1\nkind: ConfigMap\nmetadata:\n  name: {{ .Release.Name }}\n' > "$fx/chart/templates/cm.yaml"
    printf '[package]\nname = "fixture"\nversion = "0.1.0"\nedition = "2021"\n' > "$fx/rs/Cargo.toml"
    printf 'fn main() { println!("hi"); }\n' > "$fx/rs/src/main.rs"
    printf '<project><modelVersion>4.0.0</modelVersion><groupId>f</groupId><artifactId>f</artifactId><version>1</version></project>\n' > "$fx/java/pom.xml"
    printf 'public class Main { public static void main(String[] a) { System.out.println("hi"); } }\n' > "$fx/java/src/main/java/Main.java"
    # gitsigns and several root_dir resolvers key off a repository.
    ( cd "$fx" && git init -q . && git add -A \
        && git -c user.email=v@v -c user.name=v commit -qm fixture ) >/dev/null 2>&1
}

# Run a fixture probe written by check_languages / check_dap, then report its
# output: one "OK|FAIL<TAB>name<TAB>detail" line per language.
run_tsv_probe() {
    local what="$1" script="$2" out="$3" summary="$4" fx="$WORK/fixture"
    if ! ( cd "$fx" && FIXTURE="$fx" OUTFILE="$out" \
            nvim --headless -c "luafile $script" -c "qa!" ) >/dev/null 2>&1; then
        fail "$what probe did not complete"
        return
    fi
    if [[ ! -s "$out" ]]; then
        fail "$what probe produced no results"
        return
    fi
    local status name detail n_ok=0
    while IFS=$'\t' read -r status name detail; do
        if [[ "$status" == "OK" ]]; then
            n_ok=$((n_ok + 1))
        else
            fail "$name — $detail"
        fi
    done < "$out"
    [[ $n_ok -gt 0 ]] && pass "$n_ok language(s): $summary"
}

check_languages() {
    head1 "Per-language support"
    make_fixture

    cat > "$WORK/lang.lua" <<'LUAEOF'
local F = vim.env.FIXTURE
local out = {}

-- A server that attaches but greets every buffer with a warning is exactly the
-- "random errors" this config exists to avoid (sqls did, on every SQL file, at
-- INFO level -- hence INFO, not WARN), so capture notifications per buffer.
-- mini.notify replaces vim.notify at VeryLazy; install the capture after it or
-- it is simply overwritten.
vim.cmd("doautocmd User VeryLazy")
local notes = {}
local original = vim.notify
vim.notify = function(msg, level, opts)
	if (level or 0) >= vim.log.levels.INFO then
		notes[#notes + 1] = tostring(msg):gsub("\n", " ")
	end
	return original(msg, level, opts)
end

-- file | filetype | every LSP that must attach | formatters conform must run | linters that must be registered and executable
-- | (optional) LSPs that must NOT attach
local cases = {
	-- No Tailwind in the fixture, so its 105 MB server must stay out.
	{ "src/App.tsx", "typescriptreact", { "vtsls" }, { "prettierd" }, {}, { "tailwindcss" } },
	{ "src/util.ts", "typescript", { "vtsls" }, { "prettierd" }, {} },
	{ "main.py", "python", { "basedpyright", "ruff" }, { "ruff_organize_imports", "ruff_format" }, {} },
	{ "main.go", "go", { "gopls" }, { "goimports", "gofumpt" }, { "golangcilint" } },
	{ "main.tf", "terraform", { "terraformls" }, { "terraform_fmt" }, { "tflint" } },
	{ "script.sh", "sh", { "bashls" }, { "shfmt" }, { "shellcheck" } },
	{ "Dockerfile", "dockerfile", { "dockerls" }, {}, { "hadolint" } },
	{ "conf.yaml", "yaml", { "yamlls" }, { "prettierd" }, { "yamllint" } },
	{ "k8s/deployment.yaml", "yaml", { "yamlls" }, { "prettierd" }, { "yamllint" } },
	{ "chart/templates/cm.yaml", "helm", { "helm_ls" }, {}, {} },
	{ "package.json", "json", { "jsonls" }, { "prettierd" }, {} },
	{ "conf.toml", "toml", { "taplo" }, { "taplo" }, {} },
	{ "style.css", "css", { "cssls" }, { "prettierd" }, {} },
	{ "README.md", "markdown", { "marksman" }, { "prettierd" }, { "markdownlint-cli2" } },
	{ "sql/q.sql", "sql", { "sqls" }, { "sql_formatter" }, {} },
	-- No connection configured: sqls must stay out rather than complain.
	{ "sql-noconn/q.sql", "sql", {}, { "sql_formatter" }, {}, { "sqls" } },
	{ "conf.lua", "lua", { "lua_ls" }, { "stylua" }, {} },
	{ "q.graphql", "graphql", { "graphql" }, { "prettierd" }, {} },
	-- rustaceanvim registers the client under its hyphenated upstream name.
	{ "rs/src/main.rs", "rust", { "rust-analyzer" }, { "rustfmt" }, {} },
	{ "java/src/main/java/Main.java", "java", { "jdtls" }, { "google-java-format" }, { "checkstyle" } },
}

local conform = require("conform")
local lint = require("lint")

local function missing(want, got)
	local gaps = {}
	for _, w in ipairs(want) do
		if not vim.tbl_contains(got, w) then
			gaps[#gaps + 1] = w
		end
	end
	return gaps
end

for _, c in ipairs(cases) do
	local file, want_ft, want_lsp, want_fmt, want_lint, forbid_lsp = c[1], c[2], c[3], c[4], c[5], c[6] or {}
	notes = {}
	vim.cmd.edit(F .. "/" .. file)
	local buf = vim.api.nvim_get_current_buf()
	local ft = vim.bo[buf].filetype
	local problems = {}

	if ft ~= want_ft then
		problems[#problems + 1] = ("filetype %q, expected %q"):format(ft, want_ft)
	end

	-- Wait until *every* expected server has attached, not just the first --
	-- ruff attaches in a few hundred ms while basedpyright takes seconds, and
	-- stopping at the first one would hide a server that never starts.
	local got_lsp = {}
	if #want_lsp > 0 then
		vim.wait(45000, function()
			got_lsp = {}
			for _, cl in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
				got_lsp[#got_lsp + 1] = cl.name
			end
			return #missing(want_lsp, got_lsp) == 0
		end, 250)
		local gaps = missing(want_lsp, got_lsp)
		if #gaps > 0 then
			problems[#problems + 1] = "no LSP: " .. table.concat(gaps, ", ")
		end
	end

	-- What conform would actually run on save, not merely what is configured.
	local got_fmt = {}
	local list = conform.list_formatters_to_run and conform.list_formatters_to_run(buf)
		or conform.list_formatters(buf)
	for _, f in ipairs(list) do
		got_fmt[#got_fmt + 1] = f.name
		if f.available == false then
			problems[#problems + 1] = ("formatter %s unavailable: %s"):format(f.name, f.available_msg or "?")
		end
	end
	local fgaps = missing(want_fmt, got_fmt)
	if #fgaps > 0 then
		problems[#problems + 1] = "no formatter: " .. table.concat(fgaps, ", ")
	end

	-- Registered linters, and whether the binary behind each one exists.
	local got_lint = {}
	for _, name in ipairs(lint.linters_by_ft[ft] or {}) do
		got_lint[#got_lint + 1] = name
		local l = lint.linters[name]
		local cmd = l and (type(l.cmd) == "function" and l.cmd() or l.cmd)
		if not (cmd and vim.fn.executable(cmd) == 1) then
			problems[#problems + 1] = ("linter %s: %s not executable"):format(name, tostring(cmd))
		end
	end
	local lgaps = missing(want_lint, got_lint)
	if #lgaps > 0 then
		problems[#problems + 1] = "no linter: " .. table.concat(lgaps, ", ")
	end

	-- Servers report startup problems shortly after attaching, not during it.
	vim.wait(1500)
	for _, cl in ipairs(vim.lsp.get_clients({ bufnr = buf })) do
		if vim.tbl_contains(forbid_lsp, cl.name) then
			problems[#problems + 1] = "unwanted LSP: " .. cl.name
		end
	end
	for _, n in ipairs(notes) do
		problems[#problems + 1] = "notified: " .. n
	end

	out[#out + 1] = (#problems == 0 and "OK\t" or "FAIL\t") .. file .. "\t" .. table.concat(problems, "; ")
end

vim.fn.writefile(out, vim.env.OUTFILE)
LUAEOF

    run_tsv_probe language "$WORK/lang.lua" "$WORK/lang.txt" "LSP attaches, formatter resolves, linter executable, no warnings"
}

# -----------------------------------------------------------------------------
# Debug adapters
# -----------------------------------------------------------------------------
# An adapter being installed does not make a language debuggable: nvim-dap needs
# both an adapter *and* at least one configuration before a debug key does
# anything. Java got this wrong silently — the java-debug bundles loaded, the
# adapter registered, and every debug key was a no-op because the main-class
# configurations were never resolved.
#
# Asserts, per language: the adapter is registered, the binary behind it is
# executable, and at least one configuration exists. Java is driven through a
# real jdtls session against the fixture, so it is slow; like check_languages
# this is excluded from `all` and run as ./scripts/verify.sh dap
check_dap() {
    head1 "Debug adapters"
    make_fixture

    cat > "$WORK/dap.lua" <<'LUAEOF'
local F = vim.env.FIXTURE
require("lazy").load({ plugins = { "nvim-dap", "mason-nvim-dap.nvim" } })

-- Open one real buffer per language: the dedicated extensions register their
-- adapters and configurations on FileType, not at startup.
for _, f in ipairs({ "main.py", "main.go", "script.sh", "src/App.tsx", "rs/src/main.rs" }) do
	vim.cmd.edit(F .. "/" .. f)
	vim.wait(1500)
end

-- Java is the slow one: jdtls has to start, attach and resolve main classes
-- before any configuration exists.
vim.cmd.edit(F .. "/java/src/main/java/Main.java")
vim.wait(90000, function()
	for _, c in ipairs(vim.lsp.get_clients({ bufnr = 0 })) do
		if c.name == "jdtls" then
			return true
		end
	end
	return false
end, 500)
vim.wait(30000, function()
	return (require("dap").configurations.java or {})[1] ~= nil
end, 500)

local dap = require("dap")
local out = {}

-- language -> adapter that must be registered
local want = {
	python = "python",
	go = "go",
	sh = "bash",
	javascript = "pwa-node",
	typescript = "pwa-node",
	typescriptreact = "pwa-node",
	rust = "codelldb",
	java = "java",
}

for lang, adapter_name in pairs(want) do
	local problems = {}
	local a = dap.adapters[adapter_name]
	if a == nil then
		problems[#problems + 1] = "adapter " .. adapter_name .. " not registered"
	else
		-- Adapters defined as a function resolve their command per-session;
		-- there is nothing static to check, so only table forms are probed.
		local cmd = type(a) == "table" and (a.command or (a.executable and a.executable.command)) or nil
		if type(cmd) == "string" and vim.fn.executable(cmd) ~= 1 then
			problems[#problems + 1] = ("adapter %s: %s not executable"):format(adapter_name, cmd)
		end
	end
	local cfgs = dap.configurations[lang] or {}
	if #cfgs == 0 then
		problems[#problems + 1] = "no debug configurations — every debug key is a no-op here"
	end
	out[#out + 1] = (#problems == 0 and "OK\t" or "FAIL\t")
		.. lang
		.. "\t"
		.. (#problems > 0 and table.concat(problems, "; ") or (#cfgs .. " config(s)"))
end

table.sort(out)
vim.fn.writefile(out, vim.env.OUTFILE)
LUAEOF

    run_tsv_probe DAP "$WORK/dap.lua" "$WORK/dap.txt" "adapter registered, executable, with configurations"
}

case "$ONLY" in
    lua)      check_lua ;;
    shell)    check_shell ;;
    lock)     check_lockfile ;;
    notify)   check_notifications ;;
    theme)    check_lualine_theme ;;
    statusline) check_statusline ;;
    gitcompat)  check_gitconfig_compat ;;
    keymaps)  check_keymaps ;;
    shellinit) check_shell_init ;;
    languages) check_languages ;;
    dap)      check_dap ;;
    all)      check_lua; check_shell; check_shell_init; check_lockfile; check_gitconfig_compat
              check_lualine_theme; check_statusline; check_notifications
              check_keymaps ;;
    *)        echo "Usage: $0 [all|lua|shell|shellinit|lock|gitcompat|theme|statusline|notify|keymaps|languages|dap]"; exit 2 ;;
esac

echo ""
if [[ $FAILURES -eq 0 ]]; then
    echo -e "${GREEN}All checks passed.${NC}"
    exit 0
fi
echo -e "${RED}${FAILURES} check(s) failed.${NC}"
exit 1
