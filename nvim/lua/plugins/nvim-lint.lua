-- nvim-lint — linters for languages whose LSP doesn't already cover them.
--
-- Deliberately NOT configured for: Python (the ruff LSP lints and fixes),
-- JS/TS (the eslint LSP lints and provides fix actions), Terraform (terraformls
-- validates; tflint adds the correctness rules it doesn't), Rust (clippy via
-- rustaceanvim).

return {
	"mfussenegger/nvim-lint",
	event = { "BufReadPre", "BufNewFile" },
	config = function()
		local lint = require("lint")

		---Does this project configure the given tool? Linters that require a
		---config file error out without one, and those errors surface as
		---mysterious diagnostics or notifications on every save.
		---@param markers string[] filenames that indicate the tool is configured
		local function project_has(markers)
			return function()
				local root = vim.fs.root(0, markers)
				return root ~= nil
			end
		end

		lint.linters_by_ft = {
			java = { "checkstyle" },
			yaml = { "yamllint" },
			go = { "golangcilint" },
			sh = { "shellcheck" },
			bash = { "shellcheck" },
			zsh = { "shellcheck" },
			dockerfile = { "hadolint" },
			terraform = { "tflint" },
			markdown = { "markdownlint-cli2" },
		}

		-- checkstyle with no config resolves nothing and exits non-zero, which
		-- is almost certainly a source of the "random errors" this config used
		-- to produce in Java projects. Gate it on the project actually having a
		-- checkstyle config, mirroring how conform.lua gates Spotless.
		lint.linters.checkstyle.condition = project_has({
			"checkstyle.xml",
			"config/checkstyle/checkstyle.xml",
			".checkstyle.xml",
			"checkstyle-config.xml",
		})

		-- tflint needs an initialised plugin cache for provider rules; without
		-- a config it still runs but only with core rules, which is fine. It
		-- does, however, need to be inside a terraform project.
		lint.linters.tflint.condition = project_has({ ".terraform", "main.tf", ".tflint.hcl" })

		-- yamllint flags a lot of style in Kubernetes/Helm output that nobody
		-- controls (long lines, duplicated keys across documents). Relax it to
		-- the rules that catch real mistakes.
		lint.linters.yamllint.args = {
			"--format",
			"parsable",
			"-d",
			"{extends: relaxed, rules: {line-length: disable, truthy: {check-keys: false}}}",
			"-",
		}

		local lint_augroup = vim.api.nvim_create_augroup("nvim_lint", { clear = true })

		-- Previously this fired on BufEnter, which spawned a linter subprocess
		-- every single time you switched buffers — including while cycling
		-- through a picker preview. BufWritePost is when lint results can
		-- actually have changed; InsertLeave catches edits you haven't saved.
		vim.api.nvim_create_autocmd({ "BufWritePost", "InsertLeave" }, {
			group = lint_augroup,
			callback = function()
				-- Never lint a buffer that isn't a real file on disk, or one
				-- that's been marked as too large to process.
				if vim.bo.buftype ~= "" or vim.b.large_file then
					return
				end
				lint.try_lint(nil, { ignore_errors = true })
			end,
		})

		vim.keymap.set("n", "<leader>cl", function()
			lint.try_lint()
		end, { desc = "󰁨 Lint this file now" })

		-- Which linters would run here? Useful when a file isn't being linted
		-- and it isn't obvious whether that's config or a missing binary.
		vim.keymap.set("n", "<leader>cL", function()
			local names = lint.linters_by_ft[vim.bo.filetype] or {}
			if #names == 0 then
				vim.notify(("No nvim-lint linters for filetype %q"):format(vim.bo.filetype))
				return
			end
			local lines = {}
			for _, name in ipairs(names) do
				local linter = lint.linters[name]
				local cmd = linter and (type(linter.cmd) == "function" and linter.cmd() or linter.cmd)
				local available = cmd and vim.fn.executable(cmd) == 1
				local gated = linter and linter.condition and not linter.condition({})
				table.insert(
					lines,
					("%s  %s%s"):format(
						available and "✓" or "✗",
						name,
						gated and "  (skipped: no project config)" or ""
					)
				)
			end
			vim.notify(table.concat(lines, "\n"), vim.log.levels.INFO, { title = "Linters for " .. vim.bo.filetype })
		end, { desc = "󰋼 Show linters for this filetype" })
	end,
}
