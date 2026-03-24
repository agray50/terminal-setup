return {
	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		opts = {
			spec = {
				-- Leader groups
				{ "<leader>d", group = "debug" },
				{ "<leader>f", group = "find (telescope)" },
				{ "<leader>g", group = "git" },
				{ "<leader>h", group = "hunk (gitsigns)" },
				{ "<leader>k", group = "lsp" },
				{ "<leader>m", group = "format" },
				{ "<leader>t", group = "toggle" },
				{ "<leader>u", group = "undotree" },
			},
		},
		keys = {
			{
				"<leader>?",
				function()
					require("which-key").show({ global = false })
				end,
				desc = "Buffer Local Keymaps (which-key)",
			},
		},
	},
}
