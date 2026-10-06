-- Editor options. Keymaps are in core/keymaps.lua, autocmds in core/autocmds.lua.

vim.g.mapleader = " "
vim.g.maplocalleader = "\\"

-- Display
vim.opt.number = true
vim.opt.relativenumber = true
vim.opt.cursorline = true
vim.opt.signcolumn = "yes"
vim.opt.wrap = false
vim.opt.guicursor = ""
vim.opt.termguicolors = true
vim.opt.showmode = false -- lualine already shows the mode
vim.opt.laststatus = 3 -- one global statusline, not one per split
vim.opt.pumheight = 12 -- cap completion popup height
vim.opt.winminwidth = 5
vim.opt.list = true
vim.opt.listchars = { tab = "» ", trail = "·", nbsp = "␣" }
-- foldcolumn is off (below), so the fold* fields are deliberately omitted —
-- fillchars requires exactly one character per field, and unset fields are
-- simply unused. diff fills the deleted-line region in diff mode, which
-- diffview and :Gvdiffsplit both rely on being legible.
vim.opt.fillchars = {
	diff = "\u{2571}",
	eob = " ",
}

-- Indentation
vim.opt.tabstop = 2
vim.opt.softtabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.smartindent = true
vim.opt.shiftround = true

-- Search
vim.opt.ignorecase = true
vim.opt.smartcase = true
vim.opt.inccommand = "split" -- live preview of :s/… results

-- Splits
vim.opt.splitright = true
vim.opt.splitbelow = true
vim.opt.splitkeep = "screen" -- opening a split no longer scrolls the old window

-- Behaviour
vim.opt.scrolloff = 8
vim.opt.sidescrolloff = 8
vim.opt.swapfile = false
vim.opt.undofile = true
vim.opt.undolevels = 10000
vim.opt.mouse = "a"
vim.opt.updatetime = 200 -- drives CursorHold (gitsigns blame, diagnostics)
vim.opt.timeoutlen = 400 -- which-key popup delay
vim.opt.confirm = true -- prompt instead of failing on :q with changes
vim.opt.virtualedit = "block"
vim.opt.completeopt = "menu,menuone,noselect"
vim.opt.sessionoptions = { "buffers", "curdir", "tabpages", "winsize", "help" }

-- Clipboard.
--
-- Deliberately NOT `clipboard = "unnamedplus"`. That setting routes every yank
-- AND every delete through the system clipboard, so `d`, `x` and `c` silently
-- clobber whatever you had copied from the browser. Instead the unnamed
-- register stays local and <leader>y / <leader>p (core/keymaps.lua) make
-- crossing into the system clipboard an explicit choice.
--
-- When SSH'd in there is no local display server; use OSC 52 so the explicit
-- yanks reach the host terminal clipboard instead of silently going nowhere.
if vim.env.SSH_TTY ~= nil or vim.env.SSH_CLIENT ~= nil then
	local osc52 = require("vim.ui.clipboard.osc52")
	-- OSC 52 payloads are base64-encoded and written straight into the SSH
	-- terminal stream; a huge yank turns into a huge escape sequence that
	-- visibly stalls the session, so skip (and warn) above this size.
	local OSC52_MAX_BYTES = 100 * 1024
	local function guarded_copy(register)
		local copy = osc52.copy(register)
		return function(lines)
			local size = 0
			for _, line in ipairs(lines) do
				size = size + #line + 1
			end
			if size > OSC52_MAX_BYTES then
				vim.notify(
					string.format("OSC 52: skipped clipboard sync of %dKB yank (over SSH size limit)", size / 1024),
					vim.log.levels.WARN
				)
				return
			end
			copy(lines)
		end
	end
	vim.g.clipboard = {
		name = "OSC 52",
		copy = { ["+"] = guarded_copy("+"), ["*"] = guarded_copy("*") },
		paste = { ["+"] = osc52.paste("+"), ["*"] = osc52.paste("*") },
	}
end

-- Folding — treesitter supplies foldexpr per-buffer (see plugins/treesitter.lua).
-- These keep every fold open by default so folding never hides code unasked.
vim.opt.foldlevel = 99
vim.opt.foldlevelstart = 99
vim.opt.foldcolumn = "0"
vim.opt.foldtext = ""

-- Diff — used by diffview, :Gvdiffsplit and gitsigns.diffthis.
vim.opt.diffopt:append({ "linematch:60", "algorithm:histogram", "indent-heuristic" })

-- Disable unused built-in providers. Each one is a `has('python3')`-style probe
-- at startup; skipping them removes work and silences four checkhealth warnings.
vim.g.loaded_python3_provider = 0
vim.g.loaded_ruby_provider = 0
vim.g.loaded_perl_provider = 0
vim.g.loaded_node_provider = 0
