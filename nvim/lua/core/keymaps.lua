-- Global keymaps.
--
-- Plugin-specific keys live in their own plugin spec's `keys` table so they
-- also act as the lazy-load trigger. This file holds only what works without
-- any plugin loaded.
--
-- SCHEME
--   g…            LSP navigation (Neovim 0.11+ natives, rerouted via fzf-lua)
--   ]x / [x       next/previous <thing>
--   <leader>b     buffer      <leader>f  find        <leader>g  git
--   <leader>c     code/LSP    <leader>d  debug       <leader>t  test
--   <leader>u     UI toggles  <leader>w  window      <leader>q  quit
--   <leader>x     diagnostics <leader>s  search      <leader>D  database
--
-- Each group is a noun, every prefix has exactly one meaning, and anything that
-- opens has a matching way to close it.

local map = vim.keymap.set

-- ---------------------------------------------------------------------------
-- Window and pane navigation (shared with vim-tmux-navigator)
-- ---------------------------------------------------------------------------
-- The plugin remaps these when loaded; these are the fallbacks for when nvim
-- is running outside tmux.
map("n", "<C-h>", "<C-w>h", { desc = "Window left" })
map("n", "<C-j>", "<C-w>j", { desc = "Window below" })
map("n", "<C-k>", "<C-w>k", { desc = "Window above" })
map("n", "<C-l>", "<C-w>l", { desc = "Window right" })

-- Resize with arrows — repeatable without re-reaching for the leader.
map("n", "<C-Up>", "<cmd>resize +2<cr>", { desc = "Taller window" })
map("n", "<C-Down>", "<cmd>resize -2<cr>", { desc = "Shorter window" })
map("n", "<C-Left>", "<cmd>vertical resize -2<cr>", { desc = "Narrower window" })
map("n", "<C-Right>", "<cmd>vertical resize +2<cr>", { desc = "Wider window" })

-- ---------------------------------------------------------------------------
-- Editing
-- ---------------------------------------------------------------------------
map("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
map("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })
map("n", "J", "mzJ`z", { desc = "Join line below, keep cursor" })

-- Keep the cursor centred when jumping around.
map("n", "<C-d>", "<C-d>zz", { desc = "Half page down, centred" })
map("n", "<C-u>", "<C-u>zz", { desc = "Half page up, centred" })
map("n", "n", "nzzzv", { desc = "Next search result, centred" })
map("n", "N", "Nzzzv", { desc = "Prev search result, centred" })

-- Indent without losing the selection.
map("v", "<", "<gv", { desc = "Outdent selection" })
map("v", ">", ">gv", { desc = "Indent selection" })

-- Exit insert / terminal mode.
map("i", "jk", "<Esc>", { desc = "Exit insert mode" })
map("t", "<C-\\><C-n>", [[<C-\><C-n>]], { desc = "Exit terminal mode" })

-- Esc also clears search highlight, so a stale match never lingers.
map("n", "<Esc>", "<cmd>nohlsearch<cr>", { desc = "Clear search highlight" })

-- ---------------------------------------------------------------------------
-- Clipboard — explicit, because `clipboard=unnamedplus` is deliberately off
-- (see the comment in core/options.lua).
-- ---------------------------------------------------------------------------
map({ "n", "v" }, "<leader>y", [["+y]], { desc = "Yank to system clipboard" })
map("n", "<leader>Y", [["+Y]], { desc = "Yank line to system clipboard" })
map({ "n", "v" }, "<leader>P", [["+p]], { desc = "Paste from system clipboard" })
-- Paste over a selection without the replaced text landing in the register.
map("x", "<leader>p", [["_dP]], { desc = "Paste without yanking replaced" })
map({ "n", "v" }, "<leader>X", [["_d]], { desc = "Delete without yanking" })
map("v", "<LeftRelease>", '"+y', { silent = true, desc = "Yank selection on mouse release" })

-- ---------------------------------------------------------------------------
-- Buffers — <leader>b
-- ---------------------------------------------------------------------------
map("n", "<S-h>", "<cmd>bprevious<cr>", { desc = "Previous buffer" })
map("n", "<S-l>", "<cmd>bnext<cr>", { desc = "Next buffer" })
map("n", "<leader>bn", "<cmd>bnext<cr>", { desc = "Next buffer" })
map("n", "<leader>bp", "<cmd>bprevious<cr>", { desc = "Previous buffer" })
map("n", "<leader>b`", "<cmd>e #<cr>", { desc = "Last used buffer" })
map("n", "<leader>bs", "<cmd>write<cr>", { desc = "Save buffer" })
map("n", "<leader>bS", "<cmd>wall<cr>", { desc = "Save all buffers" })

-- Delete a buffer while keeping the window layout intact. Plain :bdelete closes
-- the window too, which collapses your splits every time you close a file.
local function bufremove(force)
	return function()
		local buf = vim.api.nvim_get_current_buf()
		if vim.bo[buf].modified and not force then
			local choice = vim.fn.confirm(("Save changes to %q?"):format(vim.fn.bufname(buf)), "&Yes\n&No\n&Cancel")
			if choice == 1 then
				vim.cmd.write()
			elseif choice == 3 then
				return
			end
		end
		-- Move every window showing this buffer to its alternate first.
		for _, win in ipairs(vim.fn.win_findbuf(buf)) do
			vim.api.nvim_win_call(win, function()
				if vim.api.nvim_win_get_buf(win) ~= buf then
					return
				end
				local alt = vim.fn.bufnr("#")
				if alt ~= buf and vim.fn.buflisted(alt) == 1 then
					vim.api.nvim_win_set_buf(win, alt)
					return
				end
				if not pcall(vim.cmd, "bprevious") then
					vim.cmd("enew")
				end
			end)
		end
		pcall(vim.cmd, (force and "bdelete! " or "bdelete ") .. buf)
	end
end

map("n", "<leader>bd", bufremove(false), { desc = "Delete buffer (keep layout)" })
map("n", "<leader>bD", bufremove(true), { desc = "Delete buffer (force)" })
map("n", "<leader>bo", function()
	local current = vim.api.nvim_get_current_buf()
	local closed = 0
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if buf ~= current and vim.bo[buf].buflisted and not vim.bo[buf].modified then
			pcall(vim.api.nvim_buf_delete, buf, {})
			closed = closed + 1
		end
	end
	vim.notify(("Closed %d other buffer%s"):format(closed, closed == 1 and "" or "s"))
end, { desc = "Delete other buffers" })

-- ---------------------------------------------------------------------------
-- Windows — <leader>w
-- ---------------------------------------------------------------------------
map("n", "<leader>wv", "<C-w>v", { desc = "Split vertical" })
map("n", "<leader>ws", "<C-w>s", { desc = "Split horizontal" })
map("n", "<leader>wc", "<C-w>c", { desc = "Close window" })
map("n", "<leader>wo", "<C-w>o", { desc = "Close other windows" })
map("n", "<leader>w=", "<C-w>=", { desc = "Equalise window sizes" })
map("n", "<leader>ww", "<C-w>w", { desc = "Cycle windows" })
map("n", "<leader>wx", "<C-w>x", { desc = "Swap with next window" })
map("n", "<leader>wm", function()
	-- Zoom: remember the layout, maximise, restore on second press.
	if vim.t.zoomed then
		vim.cmd("wincmd =")
		vim.t.zoomed = false
	else
		vim.cmd("resize | vertical resize")
		vim.t.zoomed = true
	end
end, { desc = "Maximise / restore window" })

-- ---------------------------------------------------------------------------
-- Quit and close — <leader>q
-- ---------------------------------------------------------------------------
map("n", "<leader>qq", "<cmd>qall<cr>", { desc = "Quit all" })
map("n", "<leader>qQ", "<cmd>qall!<cr>", { desc = "Quit all (discard changes)" })
map("n", "<leader>qw", "<cmd>wqall<cr>", { desc = "Save all and quit" })
-- The one key that gets you back to a clean editor from any state. Backed by
-- util/panels.lua's registry rather than a hardcoded list.
map("n", "<leader>qz", function()
	require("util.panels").close_all()
end, { desc = "󰅖 Close all tool panels" })

-- ---------------------------------------------------------------------------
-- Search and replace — <leader>s
-- ---------------------------------------------------------------------------
map(
	"n",
	"<leader>sr",
	[[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]],
	{ desc = "Replace word under cursor (buffer)" }
)
map("v", "<leader>sr", [[:s/\%V]], { desc = "Replace within selection" })
-- Search for the visual selection rather than the word under the cursor.
map("x", "<leader>s*", [[y/\V<C-r>=escape(@",'/\')<CR><CR>]], { desc = "Search for selection" })

-- ---------------------------------------------------------------------------
-- Terminal — <C-\> toggles a floating shell (shared helper with lazygit)
-- ---------------------------------------------------------------------------
map({ "n", "t" }, "<C-\\>", function()
	require("util.float").toggle({
		name = "shell",
		cmd = vim.o.shell,
		title = "terminal",
		scale = 0.85,
	})
end, { desc = "Toggle floating terminal" })

-- ---------------------------------------------------------------------------
-- Quickfix and location list
-- ---------------------------------------------------------------------------
map("n", "]q", "<cmd>cnext<cr>zz", { desc = "Next quickfix item" })
map("n", "[q", "<cmd>cprevious<cr>zz", { desc = "Previous quickfix item" })
map("n", "]l", "<cmd>lnext<cr>zz", { desc = "Next loclist item" })
map("n", "[l", "<cmd>lprevious<cr>zz", { desc = "Previous loclist item" })

-- ---------------------------------------------------------------------------
-- Diagnostics navigation (plain vim.diagnostic — no plugin needed)
-- ---------------------------------------------------------------------------
map("n", "]d", function()
	vim.diagnostic.jump({ count = 1, float = true })
end, { desc = "Next diagnostic" })
map("n", "[d", function()
	vim.diagnostic.jump({ count = -1, float = true })
end, { desc = "Previous diagnostic" })
map("n", "]e", function()
	vim.diagnostic.jump({ count = 1, float = true, severity = vim.diagnostic.severity.ERROR })
end, { desc = "Next error" })
map("n", "[e", function()
	vim.diagnostic.jump({ count = -1, float = true, severity = vim.diagnostic.severity.ERROR })
end, { desc = "Previous error" })

-- ---------------------------------------------------------------------------
-- UI toggles — <leader>u
-- ---------------------------------------------------------------------------
-- A small helper so each toggle reports its new state rather than leaving you
-- guessing which way it just went.
local function toggle(desc, get, set)
	return function()
		local new = not get()
		set(new)
		vim.notify((new and "󰔡 " or "󰔢 ") .. desc .. ": " .. (new and "on" or "off"))
	end
end

map(
	"n",
	"<leader>uw",
	toggle("Wrap", function()
		return vim.wo.wrap
	end, function(v)
		vim.wo.wrap = v
	end),
	{ desc = "Toggle wrap" }
)

map(
	"n",
	"<leader>ul",
	toggle("Relative numbers", function()
		return vim.wo.relativenumber
	end, function(v)
		vim.wo.relativenumber = v
	end),
	{ desc = "Toggle relative numbers" }
)

map(
	"n",
	"<leader>un",
	toggle("Line numbers", function()
		return vim.wo.number
	end, function(v)
		vim.wo.number = v
	end),
	{ desc = "Toggle line numbers" }
)

map(
	"n",
	"<leader>us",
	toggle("Spell check", function()
		return vim.wo.spell
	end, function(v)
		vim.wo.spell = v
	end),
	{ desc = "Toggle spell check" }
)

map(
	"n",
	"<leader>ud",
	toggle("Diagnostics", function()
		return vim.diagnostic.is_enabled()
	end, function(v)
		vim.diagnostic.enable(v)
	end),
	{ desc = "Toggle diagnostics" }
)

map(
	"n",
	"<leader>uc",
	toggle("Conceal", function()
		return vim.wo.conceallevel > 0
	end, function(v)
		vim.wo.conceallevel = v and 2 or 0
	end),
	{ desc = "Toggle conceal" }
)

-- virtual_lines shows the full diagnostic under the cursor line, which is
-- readable but shifts the text below it. virtual_text is compact but truncates.
-- This switches between them rather than forcing one choice permanently.
map("n", "<leader>uv", function()
	local cfg = vim.diagnostic.config() or {}
	local using_lines = cfg.virtual_lines ~= false and cfg.virtual_lines ~= nil
	if using_lines then
		vim.diagnostic.config({
			virtual_lines = false,
			virtual_text = { spacing = 2, prefix = "󰝤", source = "if_many" },
		})
		vim.notify("󰔢 Diagnostics: inline virtual text")
	else
		vim.diagnostic.config({
			virtual_lines = { current_line = true },
			virtual_text = false,
		})
		vim.notify("󰔡 Diagnostics: expanded virtual lines")
	end
end, { desc = "Toggle diagnostic display style" })

-- Inlay hints are genuinely useful in TS/Go/Rust and genuinely noisy in review.
map("n", "<leader>uh", function()
	local enabled = not vim.lsp.inlay_hint.is_enabled({ bufnr = 0 })
	vim.lsp.inlay_hint.enable(enabled, { bufnr = 0 })
	vim.notify((enabled and "󰔡 " or "󰔢 ") .. "Inlay hints: " .. (enabled and "on" or "off"))
end, { desc = "Toggle inlay hints" })

-- k9s in the same float as lazygit and the terminal.
map("n", "<leader>uk", function()
	if vim.fn.executable("k9s") == 0 then
		vim.notify("k9s not found in PATH — run ./setup.sh", vim.log.levels.ERROR)
		return
	end
	require("util.float").toggle({ name = "k9s", cmd = "k9s", title = "k9s", scale = 0.95 })
end, { desc = "󱃾 Toggle k9s (Kubernetes)" })

-- ---------------------------------------------------------------------------
-- Code — <leader>c. LSP-specific keys are added per-buffer on LspAttach
-- (see plugins/lsp-config.lua); these work with or without a server attached.
-- ---------------------------------------------------------------------------
map("n", "<leader>cx", "<cmd>!chmod +x %<cr>", { silent = true, desc = "Make file executable" })
map("n", "<leader>cp", function()
	vim.fn.setreg("+", vim.fn.expand("%:p"))
	vim.notify("Copied: " .. vim.fn.expand("%:p"))
end, { desc = "Copy file path" })
