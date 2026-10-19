-- LSP configuration.
--
-- Only servers needing custom settings appear here; the rest are enabled
-- automatically by mason-lspconfig (see plugins/mason.lua).
--
-- Keymaps: LSP *navigation* uses Neovim's own g-prefix defaults (0.11+),
-- rerouted through fzf-lua for previews. LSP *actions* live under <leader>c.
-- The previous <leader>k group was removed — it duplicated keys Neovim ships.

return {
	{
		"neovim/nvim-lspconfig",
		event = { "BufReadPre", "BufNewFile" },
		dependencies = {
			"saghen/blink.cmp",
			-- SchemaStore supplies JSON/YAML schemas: package.json, tsconfig,
			-- GitHub Actions, docker-compose and Kubernetes manifests all get
			-- validation and completion from it.
			"b0o/schemastore.nvim",
		},
		config = function()
			-- Advertise blink.cmp's completion capabilities (snippets,
			-- resolveSupport for additionalTextEdits/documentation/detail) to
			-- every server. Neovim merges this into each vim.lsp.config below.
			vim.lsp.config("*", {
				capabilities = require("blink.cmp").get_lsp_capabilities(),
			})

			-------------------------------------------------------------
			-- Java (jdtls) — started by nvim-jdtls, configured there.
			-- See plugins/jdtls.lua; all the Lombok/import/autobuild
			-- workarounds live in that file now.
			-------------------------------------------------------------

			-------------------------------------------------------------
			-- TypeScript / JavaScript / React
			-------------------------------------------------------------
			vim.lsp.config("vtsls", {
				settings = {
					vtsls = {
						-- Lets `:VtsExec organize_imports` etc. work, and makes
						-- moving a file update every import that referenced it.
						experimental = {
							completion = { enableServerSideFuzzyMatch = true },
							maxInlayHintLength = 30,
						},
						autoUseWorkspaceTsdk = true,
					},
					typescript = {
						updateImportsOnFileMove = { enabled = "always" },
						suggest = { completeFunctionCalls = true },
						inlayHints = {
							parameterNames = { enabled = "literals" },
							parameterTypes = { enabled = true },
							variableTypes = { enabled = false },
							propertyDeclarationTypes = { enabled = true },
							functionLikeReturnTypes = { enabled = true },
							enumMemberValues = { enabled = true },
						},
						preferences = {
							importModuleSpecifier = "non-relative",
						},
					},
					javascript = {
						updateImportsOnFileMove = { enabled = "always" },
						inlayHints = {
							parameterNames = { enabled = "literals" },
							functionLikeReturnTypes = { enabled = true },
						},
					},
				},
			})

			-------------------------------------------------------------
			-- Python
			-------------------------------------------------------------
			-- ruff handles linting and fixes; basedpyright handles types and
			-- navigation. Disabling basedpyright's own linter avoids two
			-- servers reporting the same unused-import twice.
			vim.lsp.config("basedpyright", {
				settings = {
					basedpyright = {
						analysis = {
							typeCheckingMode = "standard",
							autoSearchPaths = true,
							useLibraryCodeForTypes = true,
							diagnosticSeverityOverrides = {
								reportUnusedImport = "none", -- ruff's F401
								reportUnusedVariable = "none", -- ruff's F841
							},
						},
					},
				},
			})
			vim.lsp.config("ruff", {
				init_options = {
					settings = { organizeImports = true },
				},
			})

			-------------------------------------------------------------
			-- Go
			-------------------------------------------------------------
			vim.lsp.config("gopls", {
				settings = {
					gopls = {
						gofumpt = true,
						usePlaceholders = true,
						completeUnimported = true,
						staticcheck = true,
						-- Without this, gopls ignores _test.go build tags and
						-- reports phantom errors in tagged integration tests.
						buildFlags = { "-tags=integration" },
						analyses = {
							unusedparams = true,
							unusedwrite = true,
							nilness = true,
							useany = true,
							shadow = true,
						},
						hints = {
							assignVariableTypes = true,
							compositeLiteralFields = true,
							constantValues = true,
							functionTypeParameters = true,
							parameterNames = true,
							rangeVariableTypes = true,
						},
						codelenses = {
							generate = true,
							test = true,
							tidy = true,
							upgrade_dependency = true,
						},
					},
				},
			})

			-------------------------------------------------------------
			-- Lua
			-------------------------------------------------------------
			vim.lsp.config("lua_ls", {
				settings = {
					Lua = {
						workspace = { checkThirdParty = false },
						codeLens = { enable = true },
						hint = { enable = true, arrayIndex = "Disable" },
						doc = { privateName = { "^_" } },
						diagnostics = {
							-- lazydev.nvim supplies the vim.* definitions.
							globals = { "vim" },
						},
						format = { enable = false }, -- stylua does this
					},
				},
			})

			-------------------------------------------------------------
			-- JSON / YAML — schemas from SchemaStore
			-------------------------------------------------------------
			-- The catalog behind schemastore is a single 573 KB Lua table, and
			-- requiring it here loaded it on the first buffer of *any*
			-- filetype — ~6ms to set up JSON schemas before opening a .go
			-- file. before_init runs only once the server is actually
			-- starting, and settings are sent to the server after it, so this
			-- is the documented place to resolve them lazily.
			vim.lsp.config("jsonls", {
				before_init = function(_, config)
					config.settings.json.schemas = require("schemastore").json.schemas()
				end,
				settings = {
					json = {
						schemas = {},
						validate = { enable = true },
					},
				},
			})

			vim.lsp.config("yamlls", {
				-- Deferred for the same reason as jsonls above.
				before_init = function(_, config)
					config.settings.yaml.schemas = require("schemastore").yaml.schemas()
				end,
				settings = {
					yaml = {
						-- SchemaStore is more reliable than yamlls's own
						-- schemaStore, which fetches at runtime and fails offline.
						schemaStore = { enable = false, url = "" },
						schemas = {},
						validate = true,
						keyOrdering = false, -- k8s manifests are not alphabetical
					},
				},
				-- Helm templates are Go templates (see core/autocmds.lua's
				-- filetype rules); yamlls would flag every {{ }} as invalid.
				filetypes = { "yaml", "yaml.docker-compose", "yaml.gitlab" },
			})

			-------------------------------------------------------------
			-- Helm
			-------------------------------------------------------------
			vim.lsp.config("helm_ls", {
				settings = {
					["helm-ls"] = {
						-- helm-ls can delegate to yamlls, but that reintroduces
						-- the {{ }} false positives it exists to avoid.
						yamlls = { enabled = false },
					},
				},
			})

			-------------------------------------------------------------
			-- CSS / Tailwind
			-------------------------------------------------------------
			-- Tailwind v4 moves config into CSS (@theme, @apply, @plugin,
			-- @custom-variant, @utility, @source); cssls doesn't recognise
			-- these at-rules and flags them as errors, so silence that lint.
			vim.lsp.config("cssls", {
				settings = {
					css = { lint = { unknownAtRules = "ignore" } },
					scss = { lint = { unknownAtRules = "ignore" } },
					less = { lint = { unknownAtRules = "ignore" } },
				},
			})

			vim.lsp.config("tailwindcss", {
				-- Restrict to filetypes that can actually contain Tailwind classes.
				-- The default list includes markdown and a long tail of template
				-- languages, so tailwindcss was attaching to every README and
				-- emitting "Unknown filetype" warnings for languages not in use.
				filetypes = {
					"html",
					"css",
					"scss",
					"less",
					"javascript",
					"javascriptreact",
					"typescript",
					"typescriptreact",
					"vue",
					"svelte",
				},
				-- Upstream's root_dir falls back to `.git` (for v4, which needs no
				-- config file), so a 105 MB server spawned in every JS/TS repo.
				-- Require real evidence instead: a config file, or tailwindcss
				-- (incl. @tailwindcss/*) in package.json — which v4 still needs.
				root_dir = function(bufnr, on_dir)
					local util = require("lspconfig.util")
					local fname = vim.api.nvim_buf_get_name(bufnr)
					local markers = {
						"tailwind.config.js",
						"tailwind.config.cjs",
						"tailwind.config.mjs",
						"tailwind.config.ts",
						"theme/static_src/tailwind.config.js", -- django-tailwind
					}
					markers = util.insert_package_json(markers, "tailwindcss", fname)
					markers = util.root_markers_with_field(markers, { "mix.lock", "Gemfile.lock" }, "tailwind", fname)
					local found = vim.fs.find(markers, { path = fname, upward = true })[1]
					if found then
						on_dir(vim.fs.dirname(found))
					end
				end,
				settings = {
					tailwindCSS = {
						-- Recognise Tailwind classes inside cva/clsx/cn helpers
						-- and className-like props, which is where they live in
						-- a React codebase.
						classAttributes = { "class", "className", "classList", "ngClass" },
						experimental = {
							classRegex = {
								{ "cva\\(([^)]*)\\)", "[\"'`]([^\"'`]*).*?[\"'`]" },
								{ "cx\\(([^)]*)\\)", "(?:'|\"|`)([^']*)(?:'|\"|`)" },
								{ "cn\\(([^)]*)\\)", "(?:'|\"|`)([^']*)(?:'|\"|`)" },
								{ "clsx\\(([^)]*)\\)", "(?:'|\"|`)([^']*)(?:'|\"|`)" },
							},
						},
					},
				},
			})

			-------------------------------------------------------------
			-- SQL
			-------------------------------------------------------------
			-- Without a connection sqls offers nothing dadbod, snippets and
			-- sql-formatter don't already, but it greets every SQL buffer with
			-- "LSP[sqls] no database connection". Start it only once it has a
			-- config: ~/.config/sqls/config.yml, or a project config.yml that
			-- declares connections (upstream matches any config.yml at all).
			-- sqls only reads the former by itself, so point it at the latter.
			local function sqls_project_config(dir)
				local path = vim.fs.find("config.yml", { path = dir, upward = true })[1]
				local ok, lines = pcall(vim.fn.readfile, path or "")
				if ok and vim.iter(lines):any(function(l)
					return l:match("^connections:")
				end) then
					return path
				end
			end
			vim.lsp.config("sqls", {
				cmd = function(dispatchers, config)
					local cmd = { "sqls" }
					local project = config.root_dir and sqls_project_config(config.root_dir)
					if project then
						vim.list_extend(cmd, { "-config", project })
					end
					return vim.lsp.rpc.start(cmd, dispatchers, { cwd = config.root_dir })
				end,
				root_dir = function(bufnr, on_dir)
					local fname = vim.api.nvim_buf_get_name(bufnr)
					local project = sqls_project_config(vim.fs.dirname(fname))
					if project then
						on_dir(vim.fs.dirname(project))
					elseif vim.uv.fs_stat(vim.fn.expand("~/.config/sqls/config.yml")) then
						on_dir(vim.fs.root(bufnr, ".git") or vim.fs.dirname(fname))
					end
				end,
			})

			-------------------------------------------------------------
			-- GraphQL
			-------------------------------------------------------------
			-- The default filetype list includes every JS/TS variant so it can
			-- find gql`...` template literals, which means it attaches to every
			-- React file and duplicates vtsls's diagnostics. Restrict it to
			-- actual GraphQL documents.
			vim.lsp.config("graphql", {
				filetypes = { "graphql", "gql" },
			})

			-------------------------------------------------------------
			-- Terraform
			-------------------------------------------------------------
			vim.lsp.config("terraformls", {
				settings = {
					terraform = {
						validation = { enableEnhancedValidation = true },
					},
				},
			})

			-------------------------------------------------------------
			-- Keymaps, registered per-buffer when a server attaches
			-------------------------------------------------------------
			vim.api.nvim_create_autocmd("LspAttach", {
				callback = function(ev)
					local function map(mode, key, action, desc)
						vim.keymap.set(mode, key, action, {
							buffer = ev.buf,
							silent = true,
							desc = desc,
						})
					end

					local fzf = require("fzf-lua")
					local client = vim.lsp.get_client_by_id(ev.data.client_id)

					-- Navigation: Neovim 0.11+ already binds grr/gri/grn/gra/gO.
					-- These override them to go through fzf-lua, so you get a
					-- preview instead of a bare quickfix list.
					map("n", "gd", fzf.lsp_definitions, "󰈮 Go to definition")
					map("n", "gD", fzf.lsp_declarations, "󰈮 Go to declaration")
					map("n", "grr", fzf.lsp_references, "󰈇 References")
					map("n", "gri", fzf.lsp_implementations, "󰡱 Implementations")
					map("n", "grt", fzf.lsp_typedefs, "󰜢 Type definition")
					map("n", "gO", fzf.lsp_document_symbols, "󰫧 Document symbols")
					-- One picker showing definitions, references and
					-- implementations together — useful when you don't yet know
					-- which of them you actually want.
					map("n", "gh", fzf.lsp_finder, "󰍉 Symbol finder (all)")

					-- Hover / signature. K is already a Neovim default; gK adds
					-- signature help, and <C-s> gives it in insert mode where
					-- you actually need the argument list.
					map("n", "gK", vim.lsp.buf.signature_help, "󰊕 Signature help")
					map("i", "<C-s>", vim.lsp.buf.signature_help, "󰊕 Signature help")

					-- Actions, under <leader>c (code).
					map({ "n", "v" }, "<leader>ca", vim.lsp.buf.code_action, "󰅯 Code action")
					map("n", "<leader>cr", vim.lsp.buf.rename, "󰑕 Rename symbol")
					map("n", "<leader>cd", vim.diagnostic.open_float, "󰋽 Line diagnostics")
					map("n", "<leader>cI", "<cmd>checkhealth vim.lsp<cr>", "󰋼 LSP info")
					map("n", "<leader>cR", function()
						vim.lsp.enable(client and client.name or "", false)
						vim.cmd("edit")
						vim.schedule(function()
							vim.lsp.enable(client and client.name or "")
						end)
					end, "󰑓 Restart this LSP client")

					-- Organize imports. Exposed uniformly across languages even
					-- though each server names the action differently.
					map("n", "<leader>co", function()
						vim.lsp.buf.code_action({
							context = { only = { "source.organizeImports" }, diagnostics = {} },
							apply = true,
						})
					end, "󰒺 Organize imports")

					-- Fix-all (eslint, ruff) — the bulk cleanup action.
					map("n", "<leader>cF", function()
						vim.lsp.buf.code_action({
							context = { only = { "source.fixAll" }, diagnostics = {} },
							apply = true,
						})
					end, "󰁨 Fix all (auto-fixable)")

					-- Inlay hints on by default where the server supports them;
					-- <leader>uh toggles per buffer.
					if client and client:supports_method("textDocument/inlayHint") then
						vim.lsp.inlay_hint.enable(true, { bufnr = ev.buf })
					end

					-- Document highlight: underline other references to the
					-- symbol under the cursor, like VSCode does.
					if client and client:supports_method("textDocument/documentHighlight") then
						local group = vim.api.nvim_create_augroup("lsp_document_highlight_" .. ev.buf, { clear = true })
						vim.api.nvim_create_autocmd({ "CursorHold", "CursorHoldI" }, {
							group = group,
							buffer = ev.buf,
							callback = vim.lsp.buf.document_highlight,
						})
						vim.api.nvim_create_autocmd({ "CursorMoved", "CursorMovedI" }, {
							group = group,
							buffer = ev.buf,
							callback = vim.lsp.buf.clear_references,
						})
					end
				end,
			})

			-------------------------------------------------------------
			-- Diagnostics presentation
			-------------------------------------------------------------
			local severity = vim.diagnostic.severity

			vim.diagnostic.config({
				severity_sort = true,
				signs = {
					text = {
						[severity.ERROR] = "󰅚 ",
						[severity.WARN] = "󰀪 ",
						[severity.HINT] = "󰌶 ",
						[severity.INFO] = "󰋽 ",
					},
				},
				-- Expanded diagnostic under the cursor line only. <leader>uv
				-- switches to compact inline virtual text when the vertical
				-- shifting gets in the way.
				virtual_lines = { current_line = true },
				virtual_text = false,
				float = {
					border = "rounded",
					source = true,
					header = "",
					prefix = "",
				},
			})
		end,
	},
}
