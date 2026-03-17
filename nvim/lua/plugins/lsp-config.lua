return {
	{
		"mason-org/mason-lspconfig.nvim",
		opts = {
			ensure_installed = {
				"ts_ls",
				"html",
				"cssls",
				"tailwindcss",
				"lua_ls",
				"pyright",
				"eslint",
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

			-- Neovim 0.11 LSP defaults (built-in, no config needed):
			-- grn  rename        gra  code action     grr  references
			-- gri  impl          grt  type def        gO   doc symbols
			-- K    hover         <C-W>d  open float   [d/]d  diagnostics
			vim.api.nvim_create_autocmd("LspAttach", {
				callback = function()
					vim.keymap.set(
						"n",
						"grd",
						"<cmd>Telescope lsp_definitions<CR>",
						{ desc = "Go to definition", noremap = true, silent = true }
					)
					vim.keymap.set(
						"n",
						"grD",
						vim.lsp.buf.declaration,
						{ desc = "Go to declaration", noremap = true, silent = true }
					)
					vim.keymap.set(
						"n",
						"grq",
						"<cmd>Telescope diagnostics bufnr=0<CR>",
						{ desc = "Show buffer diagnostics", noremap = true, silent = true }
					)
					vim.keymap.set("n", "grN", function()
						return ":IncRename " .. vim.fn.expand("<cword>")
					end, { desc = "Rename (IncRename)", expr = true, noremap = true, silent = true })
					vim.keymap.set(
						"n",
						"grs",
						":LspRestart<CR>",
						{ desc = "Restart LSP", noremap = true, silent = true }
					)
				end,
			})

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
