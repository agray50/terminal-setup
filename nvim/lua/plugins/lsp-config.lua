return {
	{
		"neovim/nvim-lspconfig",
		config = function()
			-- Only servers needing custom config are declared here.
			-- All others are enabled automatically by mason-lspconfig.

			-- jdtls requires a per-project workspace data directory
			vim.lsp.config("jdtls", {
				cmd = {
					"jdtls",
					"-data",
					vim.fn.stdpath("data") .. "/jdtls-workspace/" .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t"),
				},
			})

			vim.lsp.config("helm_ls", {
				settings = {
					["helm-ls"] = { yamlls = { enabled = false } },
				},
			})

	
			vim.api.nvim_create_autocmd("LspAttach", {
				callback = function(ev)
					local opts = { noremap = true, silent = true, buffer = ev.buf }

					-- Navigation
					vim.keymap.set(
						"n",
						"<leader>kd",
						"<cmd>Telescope lsp_definitions<CR>",
						vim.tbl_extend("force", opts, { desc = "󰈮 Go to definition" })
					)
					vim.keymap.set(
						"n",
						"<leader>kD",
						vim.lsp.buf.declaration,
						vim.tbl_extend("force", opts, { desc = "󰈮 Go to declaration" })
					)
					vim.keymap.set(
						"n",
						"<leader>kr",
						"<cmd>Telescope lsp_references<CR>",
						vim.tbl_extend("force", opts, { desc = "󰈇 References" })
					)
					vim.keymap.set(
						"n",
						"<leader>ki",
						"<cmd>Telescope lsp_implementations<CR>",
						vim.tbl_extend("force", opts, { desc = "󰡱 Implementation" })
					)
					vim.keymap.set(
						"n",
						"<leader>kt",
						"<cmd>Telescope lsp_type_definitions<CR>",
						vim.tbl_extend("force", opts, { desc = "󰜢 Type definition" })
					)
					vim.keymap.set(
						"n",
						"<leader>ks",
						"<cmd>Telescope lsp_document_symbols<CR>",
						vim.tbl_extend("force", opts, { desc = "󰫧 Document symbols" })
					)
					vim.keymap.set(
						"n",
						"<leader>kS",
						"<cmd>Telescope lsp_workspace_symbols<CR>",
						vim.tbl_extend("force", opts, { desc = "󰫧 Workspace symbols" })
					)

					-- Actions
					vim.keymap.set(
						"n",
						"<leader>ka",
						vim.lsp.buf.code_action,
						vim.tbl_extend("force", opts, { desc = "󰅯 Code action" })
					)
					vim.keymap.set(
						"n",
						"<leader>kn",
						vim.lsp.buf.rename,
						vim.tbl_extend("force", opts, { desc = "󰑕 Rename symbol" })
					)

					-- Diagnostics
					vim.keymap.set(
						"n",
						"<leader>ke",
						"<cmd>Telescope diagnostics bufnr=0<CR>",
						vim.tbl_extend("force", opts, { desc = "󰅚 Buffer diagnostics" })
					)
					vim.keymap.set(
						"n",
						"<leader>kE",
						"<cmd>Telescope diagnostics<CR>",
						vim.tbl_extend("force", opts, { desc = "󰅚 Workspace diagnostics" })
					)
					vim.keymap.set(
						"n",
						"<leader>kl",
						vim.diagnostic.open_float,
						vim.tbl_extend("force", opts, { desc = "󰋽 Line diagnostic float" })
					)

					-- Hover / info
					vim.keymap.set(
						"n",
						"<leader>kk",
						vim.lsp.buf.hover,
						vim.tbl_extend("force", opts, { desc = "󰈙 Hover" })
					)
					vim.keymap.set(
						"n",
						"<leader>kh",
						vim.lsp.buf.signature_help,
						vim.tbl_extend("force", opts, { desc = "󰊕 Signature help" })
					)

					-- LSP management
					vim.keymap.set("n", "<leader>kR", function()
						vim.lsp.stop_client(vim.lsp.get_clients({ bufnr = 0 }))
						vim.defer_fn(function()
							vim.cmd("edit")
						end, 100)
					end, vim.tbl_extend("force", opts, { desc = "󰑓 Restart LSP" }))
					vim.keymap.set(
						"n",
						"<leader>kI",
						"<cmd>LspInfo<CR>",
						vim.tbl_extend("force", opts, { desc = "󰋼 LSP info" })
					)
				end,
			})

			local severity = vim.diagnostic.severity

			vim.diagnostic.config({
				signs = {
					text = {
						[severity.ERROR] = "󰅚 ",
						[severity.WARN] = "󰀪 ",
						[severity.HINT] = "󰌶 ",
						[severity.INFO] = "󰋽 ",
					},
				},
			})
		end,
	},
}
