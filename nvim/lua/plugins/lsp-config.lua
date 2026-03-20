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
					"-data", vim.fn.stdpath("data") .. "/jdtls-workspace/" .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t"),
				},
			})

			vim.lsp.config("helm_ls", {
				settings = {
					["helm-ls"] = { yamlls = { enabled = false } },
				},
			})

			-- Neovim 0.11 LSP defaults (built-in, no config needed):
			-- grn  rename        gra  code action     grr  references
			-- gri  impl          grt  type def        gO   doc symbols
			-- K    hover         <C-W>d  open float   [d/]d  diagnostics
			vim.api.nvim_create_autocmd("LspAttach", {
				callback = function()
					vim.keymap.set("n", "grd", "<cmd>Telescope lsp_definitions<CR>", { desc = "Go to definition", noremap = true, silent = true })
					vim.keymap.set("n", "grD", vim.lsp.buf.declaration, { desc = "Go to declaration", noremap = true, silent = true })
					vim.keymap.set("n", "grq", "<cmd>Telescope diagnostics bufnr=0<CR>", { desc = "Show buffer diagnostics", noremap = true, silent = true })
					vim.keymap.set("n", "grs", ":LspRestart<CR>", { desc = "Restart LSP", noremap = true, silent = true })
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
