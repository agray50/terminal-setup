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
				"rust_analyzer",
			},
		},
	},
	{
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		dependencies = { "mason-org/mason.nvim" },
		opts = {
			-- Disable the built-in mason-nvim-dap cross-reference: with no DAP
			-- adapters in ensure_installed below, this integration only exists
			-- to `require("mason-nvim-dap.mappings.source")`, which would force
			-- mason-nvim-dap.nvim (and the whole nvim-dap stack) to load on
			-- every startup even though nothing here needs it anymore.
			integrations = {
				["mason-nvim-dap"] = false,
			},
			ensure_installed = {
				-- Formatters
				"prettier",
				"stylua",
				"isort",
				"black",
				"goimports",
				"rustfmt",
				"shfmt",
				"google-java-format",
				-- Linters
				"pylint",
				"yamllint",
				"golangci-lint",
				"shellcheck",
				"checkstyle",
				-- DAP adapters are installed via mason-nvim-dap.nvim's own
				-- ensure_installed (see dap.lua) instead of here — that keeps
				-- installation lazy, tied to nvim-dap's first use, rather than
				-- forcing mason-nvim-dap.nvim (and therefore the whole nvim-dap
				-- stack) to load on every startup just to resolve adapter names.
			},
		},
	},
}
