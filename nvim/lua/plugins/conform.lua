-- conform.nvim — formatting, on save and on demand (<leader>cf).

return {
	"stevearc/conform.nvim",
	event = { "BufReadPre", "BufNewFile" },
	cmd = "ConformInfo",
	keys = {
		{
			"<leader>cf",
			function()
				require("conform").format({ lsp_format = "fallback", async = false, timeout_ms = 30000 })
			end,
			mode = { "n", "v" },
			desc = "󰉶 Format file or selection",
		},
		{ "<leader>cC", "<cmd>ConformInfo<cr>", desc = "󰋼 Formatter info for this buffer" },
	},
	config = function()
		local conform = require("conform")

		-- Spotless only runs if a project actually configures it; otherwise
		-- `./mvnw`/`./gradlew spotlessApply` has to resolve the plugin from
		-- scratch (no version pinned anywhere), which is slow/unreliable and,
		-- combined with stop_after_first below, would leave conform stuck on
		-- a hanging Spotless invocation instead of falling back to
		-- google-java-format.
		local function pom_or_gradle_has_spotless(wrapper, build_files)
			return function(_, ctx)
				local root = vim.fs.root(ctx.dirname, wrapper)
				if not root then
					return false
				end
				for _, name in ipairs(build_files) do
					local f = io.open(root .. "/" .. name, "r")
					if f then
						local content = f:read("*a")
						f:close()
						if content:find("spotless", 1, true) then
							return true
						end
					end
				end
				return false
			end
		end

		-- prettierd is a daemon: the first format starts it, every later one is
		-- near-instant. Fall back to plain prettier when the daemon can't start
		-- (which happens on a fresh machine before node is installed).
		local function prettier()
			return { "prettierd", "prettier", stop_after_first = true }
		end

		conform.setup({
			formatters = {
				spotless_maven = {
					condition = pom_or_gradle_has_spotless("mvnw", { "pom.xml" }),
				},
				spotless_gradle = {
					condition = pom_or_gradle_has_spotless("gradlew", { "build.gradle", "build.gradle.kts" }),
				},
				-- Respect a project's own prettier config; only fall back to
				-- prettier's defaults when the project has none.
				prettierd = {
					require_cwd = false,
				},
			},
			formatters_by_ft = {
				-- JS / TS / React
				javascript = prettier(),
				javascriptreact = prettier(),
				typescript = prettier(),
				typescriptreact = prettier(),
				-- Web / styling
				css = prettier(),
				scss = prettier(),
				less = prettier(),
				html = prettier(),
				-- Data / config
				json = prettier(),
				jsonc = prettier(),
				yaml = prettier(),
				markdown = prettier(),
				["markdown.mdx"] = prettier(),
				graphql = prettier(),
				toml = { "taplo" },
				-- Python: ruff replaces isort + black. One Rust binary instead
				-- of three Python processes, and it does both jobs.
				python = { "ruff_organize_imports", "ruff_format" },
				-- Other languages
				lua = { "stylua" },
				go = { "goimports", "gofumpt" },
				rust = { "rustfmt" },
				java = { "spotless_gradle", "spotless_maven", "google-java-format", stop_after_first = true },
				sh = { "shfmt" },
				bash = { "shfmt" },
				zsh = { "shfmt" },
				sql = { "sql_formatter" },
				terraform = { "terraform_fmt" },
				tf = { "terraform_fmt" },
				hcl = { "terraform_fmt" },
				-- Trim trailing whitespace and fix final newline everywhere
				-- else, including filetypes with no real formatter.
				["_"] = { "trim_whitespace", "trim_newlines" },
			},
			format_on_save = function(bufnr)
				-- An escape hatch for files that must not be reformatted (a
				-- vendored file, or a repo whose CI disagrees with these
				-- formatters): :lua vim.b.disable_autoformat = true
				if vim.b[bufnr].disable_autoformat or vim.g.disable_autoformat then
					return
				end
				if vim.b[bufnr].large_file then
					return
				end
				return {
					lsp_format = "fallback",
					async = false,
					-- java's spotless_maven/spotless_gradle formatters shell out
					-- to a full Maven/Gradle process (JVM startup + plugin
					-- resolution), which routinely takes several seconds — far
					-- past a typical formatter's runtime — so this needs a
					-- generous ceiling to avoid timing out.
					timeout_ms = 30000,
				}
			end,
		})

		-- Toggle format-on-save, buffer-local or global. Lives under the UI
		-- toggles group with every other on/off switch.
		vim.keymap.set("n", "<leader>uf", function()
			vim.b.disable_autoformat = not vim.b.disable_autoformat
			vim.notify(
				(vim.b.disable_autoformat and "󰔢 " or "󰔡 ")
					.. "Format on save (buffer): "
					.. (vim.b.disable_autoformat and "off" or "on")
			)
		end, { desc = "Toggle format on save (buffer)" })

		vim.keymap.set("n", "<leader>uF", function()
			vim.g.disable_autoformat = not vim.g.disable_autoformat
			vim.notify(
				(vim.g.disable_autoformat and "󰔢 " or "󰔡 ")
					.. "Format on save (global): "
					.. (vim.g.disable_autoformat and "off" or "on")
			)
		end, { desc = "Toggle format on save (global)" })
	end,
}
