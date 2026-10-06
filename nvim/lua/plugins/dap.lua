-- Debugging — nvim-dap, under <leader>d.
--
-- Per-language test debugging is wired up here too: <leader>dt debugs the
-- nearest test in Python, Go and Java, which is the thing a debugger is
-- actually used for most days.

return {
	{
		"mfussenegger/nvim-dap",
		dependencies = {
			{
				"rcarriga/nvim-dap-ui",
				dependencies = { "nvim-neotest/nvim-nio" },
			},
			"theHamsta/nvim-dap-virtual-text",
			{
				"jay-babu/mason-nvim-dap.nvim",
				dependencies = { "mason-org/mason.nvim" },
				opts = {
					-- An empty handlers table enables mason-nvim-dap's default
					-- handler for every source, which is what registers the
					-- adapters with nvim-dap.
					handlers = {},
					-- Install/configure these on first DAP use rather than via
					-- mason-tool-installer, which would otherwise force this
					-- whole plugin (and nvim-dap with it) to load on every
					-- startup.
					ensure_installed = {
						"codelldb", -- Rust, C, C++
						"debugpy", -- Python
						"delve", -- Go
						"js-debug-adapter", -- Node, Chrome, React
						"bash-debug-adapter", -- Bash
					},
					automatic_installation = true,
				},
			},
			-- Python and Go get dedicated extensions because "debug this one
			-- test" needs adapter-specific knowledge that plain nvim-dap
			-- configurations can't express.
			{
				"mfussenegger/nvim-dap-python",
				ft = "python",
				config = function()
					-- Use the debugpy that Mason installed, not whatever is in
					-- the active virtualenv — the venv usually doesn't have it,
					-- and nvim-dap-python's default guess fails silently.
					local mason_python = vim.fn.stdpath("data") .. "/mason/packages/debugpy/venv/bin/python"
					if vim.fn.executable(mason_python) == 1 then
						require("dap-python").setup(mason_python)
					else
						require("dap-python").setup("python3")
					end
					-- Default to pytest for test discovery.
					require("dap-python").test_runner = "pytest"
				end,
			},
			{
				"leoluz/nvim-dap-go",
				ft = "go",
				opts = {
					delve = {
						-- Without this, debugging a test in a package with build
						-- tags fails to find the test binary.
						build_flags = "",
						detached = vim.fn.has("win32") == 0,
					},
				},
			},
		},
		keys = {
			-- Breakpoints
			{
				"<leader>db",
				function()
					require("dap").toggle_breakpoint()
				end,
				desc = "󰝥 Toggle breakpoint",
			},
			{
				"<leader>dB",
				function()
					vim.ui.input({ prompt = "Breakpoint condition: " }, function(cond)
						if cond and cond ~= "" then
							require("dap").set_breakpoint(cond)
						end
					end)
				end,
				desc = "󰟃 Conditional breakpoint",
			},
			{
				"<leader>dL",
				function()
					vim.ui.input({ prompt = "Log point message: " }, function(msg)
						if msg and msg ~= "" then
							require("dap").set_breakpoint(nil, nil, msg)
						end
					end)
				end,
				desc = "󰛿 Log point",
			},
			{
				"<leader>dC",
				function()
					require("dap").clear_breakpoints()
				end,
				desc = "󰅗 Clear all breakpoints",
			},
			{
				"<leader>dl",
				function()
					require("dap").list_breakpoints()
				end,
				desc = "󰌧 List breakpoints (quickfix)",
			},

			-- Session control
			{
				"<leader>dc",
				function()
					require("dap").continue()
				end,
				desc = "󰐊 Continue / start",
			},
			{
				"<leader>dr",
				function()
					require("dap").restart()
				end,
				desc = "󰑓 Restart session",
			},
			{
				"<leader>dq",
				function()
					require("dap").terminate()
				end,
				desc = "󰓛 Terminate session",
			},
			{
				"<leader>dp",
				function()
					require("dap").pause()
				end,
				desc = "󰏤 Pause",
			},
			{
				"<leader>dg",
				function()
					require("dap").run_to_cursor()
				end,
				desc = "󰜎 Run to cursor",
			},

			-- Stepping
			{
				"<leader>di",
				function()
					require("dap").step_into()
				end,
				desc = "󰆹 Step into",
			},
			{
				"<leader>do",
				function()
					require("dap").step_over()
				end,
				desc = "󰆷 Step over",
			},
			{
				"<leader>dO",
				function()
					require("dap").step_out()
				end,
				desc = "󰆸 Step out",
			},
			{
				"<leader>dj",
				function()
					require("dap").down()
				end,
				desc = "󰁅 Down a stack frame",
			},
			{
				"<leader>dk",
				function()
					require("dap").up()
				end,
				desc = "󰁝 Up a stack frame",
			},

			-- Inspection
			{
				"<leader>du",
				function()
					require("dapui").toggle()
				end,
				desc = "󰙀 Toggle DAP UI",
			},
			{
				"<leader>de",
				function()
					require("dapui").eval()
				end,
				mode = { "n", "v" },
				desc = "󰆤 Eval expression",
			},
			{
				"<leader>dw",
				function()
					vim.ui.input({ prompt = "Watch expression: " }, function(expr)
						if expr and expr ~= "" then
							require("dapui").elements.watches.add(expr)
						end
					end)
				end,
				desc = "󰂥 Add watch",
			},
			{
				"<leader>dR",
				function()
					require("dap").repl.toggle()
				end,
				desc = "󰞷 Toggle DAP REPL",
			},

			-- Debug the nearest test. Dispatches per filetype because each
			-- language's adapter exposes this differently.
			{
				"<leader>dt",
				function()
					local ft = vim.bo.filetype
					if ft == "python" then
						require("dap-python").test_method()
					elseif ft == "go" then
						require("dap-go").debug_test()
					elseif ft == "java" then
						require("jdtls").test_nearest_method()
					else
						-- neotest knows about the remaining languages and can run
						-- any of its adapters under a DAP strategy.
						local ok, neotest = pcall(require, "neotest")
						if ok then
							neotest.run.run({ strategy = "dap" })
						else
							vim.notify("No DAP test runner for filetype: " .. ft, vim.log.levels.WARN)
						end
					end
				end,
				desc = "󰙨 Debug nearest test",
			},
			{
				"<leader>dT",
				function()
					local ft = vim.bo.filetype
					if ft == "python" then
						require("dap-python").test_class()
					elseif ft == "go" then
						require("dap-go").debug_test()
					elseif ft == "java" then
						require("jdtls").test_class()
					else
						local ok, neotest = pcall(require, "neotest")
						if ok then
							neotest.run.run({ vim.fn.expand("%"), strategy = "dap" })
						end
					end
				end,
				desc = "󰙨 Debug test class / file",
			},
		},
		config = function()
			local dap = require("dap")
			local dapui = require("dapui")

			dapui.setup({
				-- Two panels: variables/watches/stack on the left, repl and
				-- console below. Keeps the source window wide enough to read.
				layouts = {
					{
						elements = {
							{ id = "scopes", size = 0.35 },
							{ id = "watches", size = 0.25 },
							{ id = "stacks", size = 0.25 },
							{ id = "breakpoints", size = 0.15 },
						},
						position = "left",
						size = 42,
					},
					{
						elements = {
							{ id = "repl", size = 0.5 },
							{ id = "console", size = 0.5 },
						},
						position = "bottom",
						size = 12,
					},
				},
				floating = { border = "rounded" },
			})

			require("nvim-dap-virtual-text").setup({
				-- Show the value of each variable inline, but only while a
				-- session is actually stopped — otherwise it's visual noise.
				enabled = true,
				only_first_definition = false,
				all_references = false,
				virt_text_pos = "eol",
			})

			-- Load .vscode/launch.json if the project has one. Means existing
			-- VSCode debug configurations work here with no translation —
			-- useful while you're still moving between editors.
			local ok, vscode = pcall(require, "dap.ext.vscode")
			if ok then
				local launch_json = vim.fn.getcwd() .. "/.vscode/launch.json"
				if vim.fn.filereadable(launch_json) == 1 then
					vscode.load_launchjs(launch_json, {
						["pwa-node"] = { "javascript", "typescript" },
						["node"] = { "javascript", "typescript" },
						["pwa-chrome"] = { "javascriptreact", "typescriptreact", "javascript", "typescript" },
						["debugpy"] = { "python" },
						["go"] = { "go" },
						["java"] = { "java" },
						["codelldb"] = { "rust", "c", "cpp" },
					})
				end
			end

			-- js-debug-adapter: register the adapters explicitly.
			--
			-- mason-nvim-dap installs the package but its default handler does
			-- NOT register the "pwa-node"/"pwa-chrome" adapter names that the
			-- configurations below (and any .vscode/launch.json) refer to — so
			-- without this, every JS/TS/React debug attempt fails with
			-- "Adapter 'pwa-node' is not defined". Verified against the
			-- installed layout: Mason ships a dapDebugServer.js that speaks DAP
			-- over a TCP port.
			local js_debug = vim.fn.stdpath("data") .. "/mason/packages/js-debug-adapter/js-debug/src/dapDebugServer.js"
			if vim.uv.fs_stat(js_debug) then
				for _, adapter in ipairs({ "pwa-node", "pwa-chrome", "node-terminal", "pwa-extensionHost" }) do
					dap.adapters[adapter] = {
						type = "server",
						host = "localhost",
						port = "${port}",
						executable = {
							command = "node",
							args = { js_debug, "${port}" },
						},
					}
				end
				-- .vscode/launch.json files in the wild still use the legacy
				-- "node"/"chrome" type names; alias them onto the same adapter
				-- so those configs work unchanged.
				dap.adapters["node"] = dap.adapters["pwa-node"]
				dap.adapters["chrome"] = dap.adapters["pwa-chrome"]
			else
				vim.notify(
					"js-debug-adapter not installed — JS/TS debugging unavailable. "
						.. "Run :MasonInstall js-debug-adapter",
					vim.log.levels.WARN
				)
			end

			-- Node / React configurations, which js-debug-adapter needs spelled
			-- out. Covers attaching to a running dev server as well as
			-- launching one, plus Chrome for front-end debugging.
			for _, lang in ipairs({ "javascript", "typescript", "javascriptreact", "typescriptreact" }) do
				dap.configurations[lang] = dap.configurations[lang] or {}
				vim.list_extend(dap.configurations[lang], {
					{
						type = "pwa-node",
						request = "launch",
						name = "Launch current file (node)",
						program = "${file}",
						cwd = "${workspaceFolder}",
						sourceMaps = true,
					},
					{
						type = "pwa-node",
						request = "attach",
						name = "Attach to running node process",
						processId = function()
							return require("dap.utils").pick_process()
						end,
						cwd = "${workspaceFolder}",
						sourceMaps = true,
					},
					{
						type = "pwa-chrome",
						request = "launch",
						name = "Launch Chrome against localhost:3000",
						url = "http://localhost:3000",
						webRoot = "${workspaceFolder}",
						sourceMaps = true,
						-- A separate profile dir keeps the debug session from
						-- inheriting (and corrupting) your real Chrome profile.
						userDataDir = "${workspaceFolder}/.vscode/chrome-debug-profile",
					},
				})
			end

			-- Open the UI with the session and close it when the session ends,
			-- so the panels never linger after you've finished debugging.
			dap.listeners.after.event_initialized["dapui_config"] = function()
				dapui.open()
			end
			dap.listeners.before.event_terminated["dapui_config"] = function()
				dapui.close()
			end
			dap.listeners.before.event_exited["dapui_config"] = function()
				dapui.close()
			end

			-- Nerd font signs
			vim.fn.sign_define("DapBreakpoint", { text = "󰝥", texthl = "DapBreakpoint" })
			vim.fn.sign_define("DapBreakpointCondition", { text = "󰟃", texthl = "DapBreakpointCondition" })
			vim.fn.sign_define("DapLogPoint", { text = "󰛿", texthl = "DapLogPoint" })
			vim.fn.sign_define(
				"DapStopped",
				{ text = "󰁕", texthl = "DapStopped", linehl = "DapStopped", numhl = "DapStopped" }
			)
			vim.fn.sign_define("DapBreakpointRejected", { text = "󰅗", texthl = "DapBreakpointRejected" })
		end,
	},
}
