return {
	"stevearc/conform.nvim",
	event = { "BufReadPre", "BufNewFile" },
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

		conform.setup({
			formatters = {
				spotless_maven = {
					condition = pom_or_gradle_has_spotless("mvnw", { "pom.xml" }),
				},
				spotless_gradle = {
					condition = pom_or_gradle_has_spotless(
						"gradlew",
						{ "build.gradle", "build.gradle.kts" }
					),
				},
			},
			formatters_by_ft = {
				javascript = { "prettier" },
				typescript = { "prettier" },
				javascriptreact = { "prettier" },
				typescriptreact = { "prettier" },
				css = { "prettier" },
				html = { "prettier" },
				json = { "prettier" },
				yaml = { "prettier" },
				markdown = { "prettier" },
				lua = { "stylua" },
				java = { "spotless_gradle", "spotless_maven", "google-java-format", stop_after_first = true },
				python = { "isort", "black" },
				go = { "goimports" },
				rust = { "rustfmt" },
				terraform = { "terraform_fmt" },
				tf = { "terraform_fmt" },
				hcl = { "terraform_fmt" },
				sh = { "shfmt" },
				bash = { "shfmt" },
			},
			format_on_save = {
				lsp_format = "fallback",
				async = false,
				-- java's spotless_maven/spotless_gradle formatters shell out to a
				-- full Maven/Gradle process (JVM startup + plugin resolution), which
				-- routinely takes several seconds — far past a typical formatter's
				-- runtime — so this needs a generous ceiling to avoid timing out.
				timeout_ms = 30000,
			},
		})

		vim.keymap.set({ "n", "v" }, "<leader>lf", function()
			conform.format({
				lsp_format = "fallback",
				async = false,
				timeout_ms = 30000,
			})
		end, { desc = "Trigger formatting for current file or range" })
	end,
}
