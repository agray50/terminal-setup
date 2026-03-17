return {
	{
		"saghen/blink.cmp",
		dependencies = { "rafamadriz/friendly-snippets" },
		version = "1.*",

		---@module 'blink.cmp'
		---@type blink.cmp.Config
		opts = {
			keymap = {
				preset = "none",
				["<C-space>"] = { "show", "show_documentation", "hide_documentation" },
				["<C-e>"] = { "hide" },
				["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
				["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
				["<CR>"] = { "accept", "fallback" },
				["<C-k>"] = { "scroll_documentation_up", "fallback" },
				["<C-j>"] = { "scroll_documentation_down", "fallback" },
			},

			appearance = {
				nerd_font_variant = "mono",
			},

			signature = { enabled = true },

			completion = { documentation = { auto_show = true } },

			sources = {
				default = { "lsp", "path", "snippets", "buffer" },
			},

			fuzzy = { implementation = "prefer_rust_with_warning" },
		},
		opts_extend = { "sources.default" },
	},
}
