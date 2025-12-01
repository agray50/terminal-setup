return {
	{
		"mason-org/mason.nvim",
		opts = {
			ensure_installed = {
				"ts_ls",
				"html",
				"cssls",
				"tailwindcss",
				"lua_ls",
				"pyright",
				"eslint",
				"jdtls",
				"yamlls",
				"helm_ls",
				"terraformls",
			},
		},
		dependencies = {
			{ "mason-org/mason.nvim", opts = {} },
			"neovim/nvim-lspconfig",
		},
	},
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
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		opts = {
			ensure_installed = {
				"prettier",
				"stylua",
				"isort",
				"black",
				"pylint",
				"eslint_d",
				"checkstyle",
				"yamllint",
			},
		},
		dependencies = {
			"williamboman/mason.nvim",
		},
	},
	{
		"neovim/nvim-lspconfig",
		config = function()
			vim.lsp.config("lua_ls", {})
			vim.lsp.config("html", {})
			vim.lsp.config("cssls", {})
			vim.lsp.config("tailwindcss", {})
			vim.lsp.config("pyright", {})
			vim.lsp.config("eslint", {})
			vim.lsp.config("jdtls", {})
			vim.lsp.config("yamlls", {})
			vim.lsp.config("helm_ls", {
				settings = {
					["helm-ls"] = { yamlls = { enabled = false } },
				},
			})
			vim.lsp.config("terraform_ls", {})

			-- set keybinds
			vim.keymap.set("n", "gR", "<cmd>Telescope lsp_references<CR>", { desc = "Show LSP references" }) -- show definition, references
			vim.keymap.set("n", "gD", vim.lsp.buf.declaration, { desc = "Go to declaration" }) -- go to declaration
			vim.keymap.set("n", "gd", vim.lsp.buf.definition, { desc = "Show LSP definition" }) -- show lsp definition
			vim.keymap.set("n", "gi", "<cmd>Telescope lsp_implementations<CR>", { desc = "Show LSP implementations" }) -- show lsp implementations
			vim.keymap.set("n", "gt", "<cmd>Telescope lsp_type_definitions<CR>", { desc = "Show LSP type definitions" }) -- show lsp type definitions
			vim.keymap.set({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, { desc = "See available code actions" }) -- see available code actions, in visual mode will apply to selection
			vim.keymap.set("n", "<leader>rn", vim.lsp.buf.rename, { desc = "Smart rename" }) -- smart rename
			vim.keymap.set(
				"n",
				"<leader>D",
				"<cmd>Telescope diagnostics bufnr=0<CR>",
				{ desc = "Show buffer diagnostics" }
			) -- show  diagnostics for file
			vim.keymap.set("n", "<leader>d", vim.diagnostic.open_float, { desc = "Show line diagnostics" }) -- show diagnostics for line
			vim.keymap.set("n", "[d", function()
				vim.diagnostic.jump({ count = -1, float = true })
			end, { desc = "Go to previous diagnostic" }) -- jump to previous diagnostic in buffer
			--
			vim.keymap.set("n", "]d", function()
				vim.diagnostic.jump({ count = 1, float = true })
			end, { desc = "Go to next diagnostic" }) -- jump to next diagnostic in buffer
			vim.keymap.set("n", "K", vim.lsp.buf.hover, { desc = "Show documentation for what is under cursor" }) -- show documentation for what is under cursor
			vim.keymap.set("n", "<leader>rs", ":LspRestart<CR>", { desc = "Restart LSP" }) -- mapping to restart lsp if necessary

			local severity = vim.diagnostic.severity

			vim.diagnostic.config({
				signs = {
					text = {
						[severity.ERROR] = " ",
						[severity.WARN] = " ",
						[severity.HINT] = "󰠠 ",
						[severity.INFO] = " ",
					},
				},
			})
		end,
	},
}
