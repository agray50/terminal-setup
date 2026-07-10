return {
	{
		"mfussenegger/nvim-dap",
		dependencies = {
			"rcarriga/nvim-dap-ui",
			"nvim-neotest/nvim-nio",
			"theHamsta/nvim-dap-virtual-text",
			{
				"jay-babu/mason-nvim-dap.nvim",
				dependencies = { "mason-org/mason.nvim" },
				opts = {
					handlers = {},
					-- Install/configure these on first DAP use rather than via
					-- mason-tool-installer, which would otherwise force this whole
					-- plugin (and nvim-dap with it) to load on every startup.
					ensure_installed = {
						"codelldb",
						"debugpy",
						"delve",
						"js-debug-adapter",
						"bash-debug-adapter",
					},
					automatic_installation = true,
				},
			},
		},
		keys = {
			{ "<leader>db", function() require("dap").toggle_breakpoint() end, desc = "󰝥 Toggle breakpoint" },
			{ "<leader>dB", function() require("dap").set_breakpoint(vim.fn.input("Breakpoint condition: ")) end, desc = "󰟃 Conditional breakpoint" },
			{ "<leader>dl", function() require("dap").set_breakpoint(nil, nil, vim.fn.input("Log message: ")) end, desc = "󰛿 Log point" },
			{ "<leader>dc", function() require("dap").continue() end, desc = "󰐊 Continue / start" },
			{ "<leader>di", function() require("dap").step_into() end, desc = "󰆹 Step into" },
			{ "<leader>do", function() require("dap").step_over() end, desc = "󰆷 Step over" },
			{ "<leader>dO", function() require("dap").step_out() end, desc = "󰆸 Step out" },
			{ "<leader>dr", function() require("dap").restart() end, desc = "󰑓 Restart" },
			{ "<leader>dq", function() require("dap").terminate() end, desc = "󰓛 Terminate" },
			{ "<leader>du", function() require("dapui").toggle() end, desc = "󰙀 Toggle UI" },
			{ "<leader>de", function() require("dapui").eval() end, mode = { "n", "v" }, desc = "󰆤 Eval expression" },
		},
		config = function()
			local dap = require("dap")
			local dapui = require("dapui")

			dapui.setup()
			require("nvim-dap-virtual-text").setup()

			-- Auto open/close UI with session lifecycle
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
			vim.fn.sign_define("DapStopped", { text = "󰁕", texthl = "DapStopped", linehl = "DapStopped", numhl = "DapStopped" })
			vim.fn.sign_define("DapBreakpointRejected", { text = "󰅗", texthl = "DapBreakpointRejected" })
		end,
	},
}
