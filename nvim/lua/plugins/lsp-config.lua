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

			-- set keybinds
			vim.api.nvim_create_autocmd("LspAttach", {
				callback = function()
					-- set vim.keymaps
					vim.keymap.set(
						"n",
						"<leader>lr",
						"<cmd>Telescope lsp_references<CR>",
						{ desc = "Show LSP references", noremap = true, silent = true }
					)
					vim.keymap.set(
						"n",
						"<leader>lD",
						vim.lsp.buf.declaration,
						{ desc = "Go to declaration", noremap = true, silent = true }
					)
					vim.keymap.set(
						"n",
						"<leader>ld",
						"<cmd>Telescope lsp_definitions<CR>",
						{ desc = "Show LSP definitions", noremap = true, silent = true }
					)
					vim.keymap.set(
						"n",
						"<leader>li",
						"<cmd>Telescope lsp_implementations<CR>",
						{ desc = "Show LSP implementations", noremap = true, silent = true }
					)
					vim.keymap.set(
						"n",
						"<leader>lt",
						"<cmd>Telescope lsp_type_definitions<CR>",
						{ desc = "Show LSP type definitions", noremap = true, silent = true }
					)
					vim.keymap.set(
						"n",
						"<leader>D",
						"<cmd>Telescope diagnostics bufnr=0<CR>",
						{ desc = "Show buffer diagnostics", noremap = true, silent = true }
					)
					vim.keymap.set(
						"n",
						"<leader>d",
						vim.diagnostic.open_float,
						{ desc = "Show line diagnostics", noremap = true, silent = true }
					)
					vim.keymap.set("n", "[d", function()
						vim.diagnostic.jump({ count = -1 })
					end, { desc = "Go to previous diagnostics", noremap = true, silent = true })
					vim.keymap.set("n", "]d", function()
						vim.diagnostic.jump({ count = 1 })
					end, { desc = "Go to next diagnostic", noremap = true, silent = true })
					vim.keymap.set(
						"n",
						"K",
						vim.lsp.buf.hover,
						{ desc = "Show documentation for what is under the cursor", noremap = true, silent = true }
					)
					vim.keymap.set(
						{ "n", "v" },
						"<leader>ca",
						vim.lsp.buf.code_action,
						{ desc = "See available code actions", noremap = true, silent = true }
					) -- in visual mode, this will apply to the current selection
					vim.keymap.set("n", "<leader>rn", function()
						return ":IncRename " .. vim.fn.expand("<cword>")
					end, { desc = "Smart rename", expr = true, noremap = true, silent = true }) -- depends on inc-rename plugin
					vim.keymap.set(
						"n",
						"<leader>rs",
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
