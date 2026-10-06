-- Bootstrap lazy.nvim, then load core config and plugin specs.
--
-- Layout:
--   lua/core/      options, keymaps, autocmds (no plugin dependencies)
--   lua/plugins/   one file per concern; each is a lazy.nvim spec
--   lua/util/      small shared helpers (floating terminals, panel registry)
--
-- Versions: plugins are pinned in lazy-lock.json; Mason packages are pinned by
-- the registry snapshot in lua/mason-pin.lua, which setup.sh generates from
-- versions.lock. Nothing here resolves "latest" at runtime.

local lazypath = vim.fn.stdpath("data") .. "/lazy/lazy.nvim"
if not (vim.uv or vim.loop).fs_stat(lazypath) then
	vim.api.nvim_echo({ { "Installing lazy.nvim (first run only)...\n", "WarningMsg" } }, true, {})
	local lazyrepo = "https://github.com/folke/lazy.nvim.git"
	local out = vim.fn.system({ "git", "clone", "--filter=blob:none", "--branch=stable", lazyrepo, lazypath })
	if vim.v.shell_error ~= 0 then
		vim.api.nvim_echo({
			{ "Failed to clone lazy.nvim:\n", "ErrorMsg" },
			{ out, "WarningMsg" },
			{ "\nPress any key to exit..." },
		}, true, {})
		vim.fn.getchar()
		os.exit(1)
	end
end
vim.opt.rtp:prepend(lazypath)

-- Options must come before lazy.setup so mapleader is set when plugin specs
-- register their <leader> keys.
require("core.options")
require("core.keymaps")
require("core.autocmds")

require("lazy").setup({
	spec = { { import = "plugins" } },
	defaults = { lazy = false },
	install = { colorscheme = { "catppuccin-mocha", "habamax" } },
	checker = { enabled = false }, -- never auto-check for updates; see README
	change_detection = { notify = false },
	performance = {
		rtp = {
			-- Disable built-in plugins that are either replaced by something
			-- here or simply unused. Each one is runtime path and sourcing cost.
			disabled_plugins = {
				"gzip",
				"tarPlugin",
				"tohtml",
				"tutor",
				"zipPlugin",
				"netrwPlugin", -- replaced by neo-tree
				"rplugin", -- no remote plugins
			},
		},
	},
	ui = { border = "rounded" },
})
