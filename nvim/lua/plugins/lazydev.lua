-- lazydev — makes the Neovim Lua API (vim.*, plugin modules) resolve in lua_ls
-- while editing this config. Only loads for Lua files.
return {
	{
		"folke/lazydev.nvim",
		ft = "lua",
		opts = {
			library = {
				{ path = "${3rd}/luv/library", words = { "vim%.uv" } },
				-- Type definitions for the plugins configured here, so their
				-- opts tables are checked and completed too.
				{ path = "lazy.nvim", words = { "LazySpec" } },
				{ path = "snacks.nvim", words = { "Snacks" } },
			},
		},
	},
	-- Extend blink's Lua sources with lazydev. opts_extend (declared in
	-- blink.lua) appends rather than replaces, so this doesn't clobber the
	-- default source list.
	{
		"saghen/blink.cmp",
		optional = true,
		opts = {
			sources = {
				per_filetype = {
					lua = { "lazydev", "lsp", "path", "snippets", "buffer" },
				},
			},
		},
	},
}
