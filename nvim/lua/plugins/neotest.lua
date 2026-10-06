-- neotest — the <leader>t (test) group.
--
-- Reclaims <leader>t, which previously held two gitsigns toggles that now live
-- under <leader>u. Covers the languages in active use; <leader>dt in dap.lua
-- falls through to neotest for anything without a dedicated DAP test runner.

return {
	"nvim-neotest/neotest",
	dependencies = {
		"nvim-neotest/nvim-nio",
		"nvim-lua/plenary.nvim",
		"antoinemadec/FixCursorHold.nvim",
		"nvim-treesitter/nvim-treesitter",
		-- Adapters, one per language.
		"nvim-neotest/neotest-python",
		"nvim-neotest/neotest-jest",
		"fredrikaverpil/neotest-golang",
	},
	keys = {
		{
			"<leader>tt",
			function()
				require("neotest").run.run()
			end,
			desc = "󰙨 Run nearest test",
		},
		{
			"<leader>tf",
			function()
				require("neotest").run.run(vim.fn.expand("%"))
			end,
			desc = "󰙨 Run tests in file",
		},
		{
			"<leader>ta",
			function()
				require("neotest").run.run(vim.uv.cwd())
			end,
			desc = "󰙨 Run all tests",
		},
		{
			"<leader>tl",
			function()
				require("neotest").run.run_last()
			end,
			desc = "󰑓 Re-run last test",
		},
		{
			"<leader>td",
			function()
				require("neotest").run.run({ strategy = "dap" })
			end,
			desc = "󰃤 Debug nearest test",
		},
		{
			"<leader>tq",
			function()
				require("neotest").run.stop()
			end,
			desc = "󰓛 Stop running test",
		},
		{
			"<leader>ts",
			function()
				require("neotest").summary.toggle()
			end,
			desc = "󰙅 Toggle test summary",
		},
		{
			"<leader>to",
			function()
				require("neotest").output.open({ enter = true, auto_close = true })
			end,
			desc = "󰌧 Show test output",
		},
		{
			"<leader>tO",
			function()
				require("neotest").output_panel.toggle()
			end,
			desc = "󰌧 Toggle output panel",
		},
		{
			"<leader>tw",
			function()
				require("neotest").watch.toggle(vim.fn.expand("%"))
			end,
			desc = "󰈈 Toggle watch mode",
		},
		{
			"]t",
			function()
				require("neotest").jump.next({ status = "failed" })
			end,
			desc = "Next failed test",
		},
		{
			"[t",
			function()
				require("neotest").jump.prev({ status = "failed" })
			end,
			desc = "Previous failed test",
		},
	},
	config = function()
		require("neotest").setup({
			adapters = {
				require("neotest-python")({
					runner = "pytest",
					-- Use the project's own interpreter so tests see the right
					-- dependencies; falls back to whatever is on PATH.
					python = function()
						local venv = os.getenv("VIRTUAL_ENV")
						if venv then
							return venv .. "/bin/python"
						end
						return vim.fn.exepath("python3")
					end,
					dap = { justMyCode = false },
				}),
				require("neotest-jest")({
					jestCommand = "npx jest --",
					jestConfigFile = function(file)
						-- Monorepos put the jest config next to each package,
						-- not at the repo root.
						if string.find(file, "/packages/") then
							return string.match(file, "(.-/[^/]+/)src") .. "jest.config.js"
						end
						return vim.fn.getcwd() .. "/jest.config.js"
					end,
					env = { CI = true },
					cwd = function(file)
						if string.find(file, "/packages/") then
							return string.match(file, "(.-/[^/]+/)src")
						end
						return vim.fn.getcwd()
					end,
				}),
				-- neotest-golang rather than neotest-go: the latter is
				-- unmaintained and mis-parses table-driven subtests, which is
				-- how most real Go test suites are written.
				require("neotest-golang")({
					dap_go_enabled = true,
				}),
			},
			status = { virtual_text = true, signs = true },
			output = { open_on_run = false },
			quickfix = {
				-- Don't hijack the quickfix list on every run; <leader>xq is
				-- there when you want it.
				enabled = false,
			},
			icons = {
				passed = "󰄬",
				failed = "󰅖",
				running = "󰑓",
				skipped = "󰜺",
				unknown = "󰋗",
			},
		})
	end,
}
