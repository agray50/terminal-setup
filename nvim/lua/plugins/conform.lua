return {
	"stevearc/conform.nvim",
	event = { "BufReadPre", "BufNewFile" },
	config = function()
		local conform = require("conform")

		conform.setup({
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
