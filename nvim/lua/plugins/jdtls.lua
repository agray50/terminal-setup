-- Java — nvim-jdtls.
--
-- Replaces the plain `vim.lsp.config("jdtls")` setup. All four workarounds from
-- that config are preserved verbatim below (Lombok javaagent, insertReplace
-- disabled, autobuild off, star-import thresholds) — they were hard-won and the
-- underlying jdtls bugs have not changed. What's gained on top:
--
--   * organize imports, extract variable/method/constant, extract interface
--   * real DAP integration via java-debug-adapter + java-test, so
--     <leader>dt debugs the single test under the cursor
--   * per-project workspaces that don't collide between repos
--
-- mason-lspconfig deliberately does NOT enable jdtls (see mason.lua's
-- automatic_enable.exclude) — otherwise a second, unconfigured client would
-- attach to the same buffer.

return {
	{
		"mfussenegger/nvim-jdtls",
		ft = { "java" },
		dependencies = { "mason-org/mason.nvim" },
		config = function()
			local mason = vim.fn.stdpath("data") .. "/mason"

			local function jdtls_config()
				-- One workspace per project, keyed by directory name. jdtls
				-- corrupts its index if two projects share a data directory.
				local root_markers = { "gradlew", "mvnw", ".git", "pom.xml", "build.gradle", "build.gradle.kts" }
				local root_dir = vim.fs.root(0, root_markers) or vim.fn.getcwd()
				local project_name = vim.fn.fnamemodify(root_dir, ":p:h:t")
				local workspace = vim.fn.stdpath("data") .. "/jdtls-workspace/" .. project_name

				-- java-debug-adapter and java-test are loaded into jdtls as
				-- "bundles"; this is what makes DAP and the test runner work.
				local bundles = {}
				local debug_jar = vim.fn.glob(
					mason .. "/packages/java-debug-adapter/extension/server/com.microsoft.java.debug.plugin-*.jar",
					true
				)
				if debug_jar ~= "" then
					vim.list_extend(bundles, vim.split(debug_jar, "\n"))
				end
				local test_jars = vim.fn.glob(mason .. "/packages/java-test/extension/server/*.jar", true)
				if test_jars ~= "" then
					-- The runner jar must be excluded or jdtls fails to start.
					for _, jar in ipairs(vim.split(test_jars, "\n")) do
						if not jar:match("com%.microsoft%.java%.test%.runner%-jar%-with%-dependencies%.jar$") then
							table.insert(bundles, jar)
						end
					end
				end

				return {
					cmd = {
						mason .. "/bin/jdtls",
						-- jdtls's own compiler (ECJ) doesn't understand
						-- Lombok-generated methods (e.g. @Getter/@Setter) unless
						-- Lombok is loaded as a javaagent — without this, real
						-- getters/setters show as "undefined" diagnostics even
						-- though Maven builds fine.
						"--jvm-arg=-javaagent:" .. mason .. "/share/jdtls/lombok.jar",
						"-data",
						workspace,
					},
					root_dir = root_dir,
					init_options = {
						bundles = bundles,
						-- Tells jdtls it can rely on the client (blink) to
						-- resolve additionalTextEdits, which is what actually
						-- inserts the import line.
						extendedClientCapabilities = vim.tbl_deep_extend(
							"force",
							require("jdtls").extendedClientCapabilities,
							{ resolveAdditionalTextEditsSupport = true }
						),
					},
					capabilities = vim.tbl_deep_extend("force", require("blink.cmp").get_lsp_capabilities(), {
						-- jdtls's InsertReplaceEdit "replace" range/text for
						-- import completions is buggy
						-- (eclipse-jdtls/eclipse.jdt.ls#353, #591), producing
						-- stray "*;" and leftover text when blink's
						-- keyword.range = "full" picks the replace range.
						-- Disabling this makes jdtls fall back to a plain,
						-- insert-only TextEdit.
						textDocument = {
							completion = {
								completionItem = { insertReplaceSupport = false },
							},
						},
					}),
					settings = {
						java = {
							-- Disable jdtls's background builder so it never
							-- writes .class files to target/classes, where it
							-- can race with and corrupt Maven's own build
							-- output. Diagnostics/completion still work via
							-- jdtls's in-memory compiler; only the on-disk
							-- incremental build is disabled.
							autobuild = { enabled = false },
							sources = {
								organizeImports = {
									-- Keep explicit imports; don't collapse to
									-- wildcard `*` imports.
									starThreshold = 9999,
									staticStarThreshold = 9999,
								},
							},
							-- Code generation: makes the extract/generate
							-- refactorings produce idiomatic output.
							codeGeneration = {
								toString = {
									template = "${object.className}{${member.name()}=${member.value}, ${otherMembers}}",
								},
								hashCodeEquals = { useJava7Objects = true },
								useBlocks = true,
							},
							completion = {
								-- Never auto-import from these: they shadow the
								-- java.* types you almost always mean.
								filteredTypes = {
									"com.sun.*",
									"io.micrometer.shaded.*",
									"java.awt.*",
									"jdk.*",
									"sun.*",
								},
								importOrder = { "java", "javax", "com", "org" },
							},
							inlayHints = {
								parameterNames = { enabled = "all" },
							},
							references = { includeDecompiledSources = true },
							implementationsCodeLens = { enabled = true },
							referencesCodeLens = { enabled = true },
							signatureHelp = { enabled = true, description = { enabled = true } },
							-- Format with Spotless/google-java-format via
							-- conform instead; two formatters fight otherwise.
							format = { enabled = false },
						},
					},
				}
			end

			-- jdtls must be started per-buffer, not via vim.lsp.enable, because
			-- root_dir and the workspace path differ per project.
			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("jdtls_attach", { clear = true }),
				pattern = "java",
				callback = function(ev)
					if vim.fn.executable(mason .. "/bin/jdtls") == 0 then
						vim.notify("jdtls not installed — run :MasonInstall jdtls", vim.log.levels.WARN)
						return
					end
					require("jdtls").start_or_attach(jdtls_config())

					-- Java-specific refactorings, under the same <leader>c
					-- (code) prefix as every other language's actions.
					local jdtls = require("jdtls")
					local function map(mode, key, fn, desc)
						vim.keymap.set(mode, key, fn, { buffer = ev.buf, desc = desc })
					end

					map("n", "<leader>co", jdtls.organize_imports, "󰒺 Organize imports (jdtls)")
					map("n", "<leader>cv", jdtls.extract_variable, "󰀫 Extract variable")
					map("v", "<leader>cv", function()
						jdtls.extract_variable(true)
					end, "󰀫 Extract variable from selection")
					map("n", "<leader>cn", jdtls.extract_constant, "󰏿 Extract constant")
					map("v", "<leader>cn", function()
						jdtls.extract_constant(true)
					end, "󰏿 Extract constant from selection")
					map("v", "<leader>cm", function()
						jdtls.extract_method(true)
					end, "󰊕 Extract method from selection")
					map("n", "<leader>cu", jdtls.update_project_config, "󰑓 Update project config (jdtls)")
				end,
			})
		end,
	},

	-- Rust — rustaceanvim owns rust_analyzer entirely (hence the exclude in
	-- mason.lua). Gives expand-macro, runnables, and codelldb integration that
	-- a plain rust_analyzer config cannot.
	{
		"mrcjkb/rustaceanvim",
		version = "^6",
		ft = { "rust" },
		config = function()
			vim.g.rustaceanvim = {
				server = {
					default_settings = {
						["rust-analyzer"] = {
							-- clippy gives substantially richer diagnostics than
							-- plain `cargo check`.
							check = { command = "clippy", extraArgs = { "--all-targets" } },
							cargo = { allFeatures = true, buildScripts = { enable = true } },
							procMacro = { enable = true },
							inlayHints = {
								lifetimeElisionHints = { enable = "skip_trivial" },
								closureReturnTypeHints = { enable = "with_block" },
							},
						},
					},
					on_attach = function(_, bufnr)
						vim.keymap.set("n", "<leader>cA", function()
							vim.cmd.RustLsp("codeAction")
						end, { buffer = bufnr, desc = "󰅯 Rust code action (grouped)" })
						vim.keymap.set("n", "<leader>cE", function()
							vim.cmd.RustLsp("expandMacro")
						end, { buffer = bufnr, desc = "󰨭 Expand macro" })
						vim.keymap.set("n", "<leader>cD", function()
							vim.cmd.RustLsp("openDocs")
						end, { buffer = bufnr, desc = "󰈙 Open docs.rs for symbol" })
					end,
				},
				dap = {
					-- Reuse the codelldb that mason-nvim-dap installed.
					autoload_configurations = true,
				},
			}
		end,
	},
}
