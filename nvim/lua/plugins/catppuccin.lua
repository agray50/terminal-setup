return {
	{
		"catppuccin/nvim",
		lazy = false,
		name = "catppuccin",
		priority = 1000,

		config = function()
			require("catppuccin").setup({
				auto_integrations = true,
				lsp_styles = {
					underlines = {
						errors = { "undercurl" },
						hints = { "undercurl" },
						warnings = { "undercurl" },
						information = { "undercurl" },
					},
				},
			})
			vim.cmd.colorscheme("catppuccin-mocha")
		end,
	},
}
