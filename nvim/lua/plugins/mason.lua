return {
	{
		"mason-org/mason.nvim",
		opts = {
			ui = {
				icons = {
					package_installed = "✓",
					package_pending = "➜",
					package_uninstalled = "✗",
				},
			},
		},
	},
	{
		"mason-org/mason-lspconfig.nvim",
		dependencies = {
			{ "mason-org/mason.nvim", opts = {} },
			"neovim/nvim-lspconfig",
		},
		opts = {
			ensure_installed = {
				"ts_ls",
				"jsonls",
				"html",
				"cssls",
				"tailwindcss",
				"lua_ls",
				"pyright",
				"eslint",
				"yamlls",
				"helm_ls",
				"terraformls",
				"jdtls",
				"gopls",
				"bashls",
			},
		},
	},
	{
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		dependencies = { "mason-org/mason.nvim" },
		opts = {
			ensure_installed = {
				-- Formatters
				"prettier",
				"stylua",
				"isort",
				"black",
				"goimports",
				"shfmt",
				-- Linters
				"pylint",
				"yamllint",
				"golangci-lint",
				"shellcheck",
				-- DAP adapters
				"debugpy",
				"delve",
				"js-debug-adapter",
				"bash-debug-adapter",
			},
		},
	},
}
