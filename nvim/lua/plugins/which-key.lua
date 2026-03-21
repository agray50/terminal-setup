return {
	{
		"folke/which-key.nvim",
		event = "VeryLazy",
		opts = {
			spec = {
				-- Leader groups
				{ "<leader>f", group = "find (telescope)" },
				{ "<leader>g", group = "git" },
				{ "<leader>h", group = "hunk (gitsigns)" },
				{ "<leader>l", group = "lsp" },
				{ "<leader>m", group = "format" },
				{ "<leader>t", group = "toggle" },
				-- gr* LSP builtins (Neovim 0.11)
				{ "gr", group = "lsp" },
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
