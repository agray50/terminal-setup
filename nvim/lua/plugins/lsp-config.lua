return {
	{
		"neovim/nvim-lspconfig",
		config = function()
			-- Only servers needing custom config are declared here.
			-- All others are enabled automatically by mason-lspconfig.

			-- Advertise blink.cmp's completion capabilities (snippets, resolveSupport
			-- for additionalTextEdits/documentation/detail, etc.) to every LSP server.
			-- Neovim merges this into each server's own vim.lsp.config() below.
			vim.lsp.config("*", {
				capabilities = require("blink.cmp").get_lsp_capabilities(),
			})

			-- jdtls requires a per-project workspace data directory
			vim.lsp.config("jdtls", {
				cmd = {
					"jdtls",
					"-data",
					vim.fn.stdpath("data") .. "/jdtls-workspace/" .. vim.fn.fnamemodify(vim.fn.getcwd(), ":t"),
				},
				init_options = {
					-- Tells jdtls it can rely on the client (blink) to resolve
					-- additionalTextEdits, which is what actually inserts the import line.
					extendedClientCapabilities = {
						resolveAdditionalTextEditsSupport = true,
					},
				},
				-- jdtls's InsertReplaceEdit "replace" range/text for import completions is
				-- buggy (eclipse-jdtls/eclipse.jdt.ls#353, #591), producing stray "*;" and
				-- leftover text when blink's keyword.range = "full" picks the replace range.
				-- Disabling this makes jdtls fall back to a plain, insert-only TextEdit.
				capabilities = {
					textDocument = {
						completion = {
							completionItem = {
								insertReplaceSupport = false,
							},
						},
					},
				},
				-- Disable jdtls's background builder so it never writes .class files
				-- to target/classes, where it can race with and corrupt Maven's own
				-- build output. Diagnostics/completion still work via jdtls's
				-- in-memory compiler; only the on-disk incremental build is disabled.
				settings = {
					java = {
						autobuild = { enabled = false },
						sources = {
							organizeImports = {
								-- Keep explicit imports; don't collapse to wildcard `*` imports.
								starThreshold = 9999,
								staticStarThreshold = 9999,
							},
						},
					},
				},
			})

			vim.lsp.config("helm_ls", {
				settings = {
					["helm-ls"] = { yamlls = { enabled = false } },
				},
			})

			-- Use clippy instead of cargo check for richer diagnostics
			vim.lsp.config("rust_analyzer", {
				settings = {
					["rust-analyzer"] = {
						checkOnSave = { command = "clippy" },
						cargo = { allFeatures = true },
					},
				},
			})

			-- Enable schema store so yamlls recognises Kubernetes, GitHub Actions, etc.
			vim.lsp.config("yamlls", {
				settings = {
					yaml = {
						schemaStore = { enable = true },
					},
				},
			})

			vim.api.nvim_create_autocmd("LspAttach", {
				callback = function(ev)
					local opts = { noremap = true, silent = true, buffer = ev.buf }

					local function map(key, action, desc)
						vim.keymap.set("n", key, action, vim.tbl_extend("force", opts, { desc = desc }))
					end

					-- Navigation
					map("<leader>kd", "<cmd>Telescope lsp_definitions<CR>",     "󰈮 Go to definition")
					map("<leader>kD", vim.lsp.buf.declaration,                  "󰈮 Go to declaration")
					map("<leader>kr", "<cmd>Telescope lsp_references<CR>",      "󰈇 References")
					map("<leader>ki", "<cmd>Telescope lsp_implementations<CR>", "󰡱 Implementation")
					map("<leader>kt", "<cmd>Telescope lsp_type_definitions<CR>","󰜢 Type definition")
					map("<leader>ks", "<cmd>Telescope lsp_document_symbols<CR>","󰫧 Document symbols")
					map("<leader>kS", "<cmd>Telescope lsp_workspace_symbols<CR>","󰫧 Workspace symbols")

					-- Actions
					map("<leader>ka", vim.lsp.buf.code_action,  "󰅯 Code action")
					map("<leader>kn", vim.lsp.buf.rename,       "󰑕 Rename symbol")

					-- Diagnostics
					map("<leader>ke", "<cmd>Telescope diagnostics bufnr=0<CR>", "󰅚 Buffer diagnostics")
					map("<leader>kE", "<cmd>Telescope diagnostics<CR>",         "󰅚 Workspace diagnostics")
					map("<leader>kl", vim.diagnostic.open_float,                "󰋽 Line diagnostic float")

					-- Hover / info
					map("<leader>kk", vim.lsp.buf.hover,          "󰈙 Hover")
					map("<leader>kh", vim.lsp.buf.signature_help, "󰊕 Signature help")
					map("<leader>kI", "<cmd>lsp<CR>",             "󰋼 LSP info")

					-- LSP management (0.12 built-in :lsp command)
					map("<leader>kR", "<cmd>lsp restart<CR>", "󰑓 Restart LSP")
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
				-- Show diagnostic inline below the current line (0.11+)
				virtual_lines = { current_line = true },
			})
		end,
	},
}
