vim.g.mapleader = " "

-- Display
vim.opt.nu = true
vim.opt.relativenumber = true
vim.opt.cursorline = true
vim.opt.signcolumn = "yes"
vim.opt.wrap = false
vim.opt.guicursor = ""

-- Indentation
vim.opt.tabstop = 2
vim.opt.softtabstop = 2
vim.opt.shiftwidth = 2
vim.opt.expandtab = true
vim.opt.smartindent = true

-- Search
vim.opt.ignorecase = true
vim.opt.smartcase = true

-- Splits
vim.opt.splitright = true
vim.opt.splitbelow = true

-- Behaviour
vim.opt.scrolloff = 8
vim.opt.swapfile = false
vim.opt.undofile = true
vim.opt.mouse = "a"
vim.opt.clipboard = "unnamedplus"

-- Folding (treesitter-based, all folds open by default)
-- nvim-treesitter manages parser attachment; do not call vim.treesitter.start manually
vim.opt.foldmethod = "expr"
vim.opt.foldexpr = "v:lua.vim.treesitter.foldexpr()"
vim.opt.foldlevel = 99
vim.opt.foldlevelstart = 99

-- Window navigation (shared with vim-tmux-navigator)
vim.keymap.set("n", "<C-h>", ":wincmd h<CR>", { desc = "Move to window left" })
vim.keymap.set("n", "<C-j>", ":wincmd j<CR>", { desc = "Move to window below" })
vim.keymap.set("n", "<C-k>", ":wincmd k<CR>", { desc = "Move to window above" })
vim.keymap.set("n", "<C-l>", ":wincmd l<CR>", { desc = "Move to window right" })

-- Editing
vim.keymap.set("v", "J", ":m '>+1<CR>gv=gv", { desc = "Move selection down" })
vim.keymap.set("v", "K", ":m '<-2<CR>gv=gv", { desc = "Move selection up" })
vim.keymap.set("n", "J", "mzJ`z", { desc = "Join line below, keep cursor position" })
vim.keymap.set("n", "<C-d>", "<C-d>zz", { desc = "Scroll down half page, center cursor" })
vim.keymap.set("n", "<C-u>", "<C-u>zz", { desc = "Scroll up half page, center cursor" })
vim.keymap.set("n", "n", "nzzzv", { desc = "Next search result, center cursor" })
vim.keymap.set("n", "N", "Nzzzv", { desc = "Prev search result, center cursor" })

-- Clipboard
vim.keymap.set("x", "<leader>p", [["_dP]], { desc = "Paste without yanking replaced text" })
vim.keymap.set({ "n", "v" }, "<leader>y", [["+y]], { desc = "Yank to system clipboard" })
vim.keymap.set("n", "<leader>Y", [["+Y]], { desc = "Yank line to system clipboard" })
vim.keymap.set({ "n", "v" }, "<leader>X", '"_d', { desc = "Delete without yanking" })
vim.keymap.set("v", "<LeftRelease>", '"+y', { noremap = true, silent = true, desc = "Yank visual selection on mouse release" })

-- Insert mode
vim.keymap.set("i", "jk", "<Esc>", { desc = "Exit insert mode" })

-- Utility
vim.keymap.set("n", "<leader>Q", function()
	pcall(function() require("dapui").close() end)
	pcall(vim.cmd, "DiffviewClose")
	pcall(vim.cmd, "Neotree close")
	pcall(vim.cmd, "UndotreeHide")
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.bo[buf].filetype == "fugitive" then
			pcall(vim.api.nvim_buf_delete, buf, { force = true })
		end
	end
end, { desc = "Close all tool panels" })
vim.keymap.set("n", "<leader>s", [[:%s/\<<C-r><C-w>\>/<C-r><C-w>/gI<Left><Left><Left>]], { desc = "Search and replace word under cursor" })
vim.keymap.set("n", "<leader>x", "<cmd>!chmod +x %<CR>", { silent = true, desc = "Make current file executable" })
