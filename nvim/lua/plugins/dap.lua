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
					-- auto-configure adapters installed via mason-tool-installer
					handlers = {},
				},
			},
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

			-- Breakpoints
			vim.keymap.set("n", "<leader>db", dap.toggle_breakpoint, { desc = "󰝥 Toggle breakpoint" })
			vim.keymap.set("n", "<leader>dB", function()
				dap.set_breakpoint(vim.fn.input("Breakpoint condition: "))
			end, { desc = "󰟃 Conditional breakpoint" })
			vim.keymap.set("n", "<leader>dl", function()
				dap.set_breakpoint(nil, nil, vim.fn.input("Log message: "))
			end, { desc = "󰛿 Log point" })

			-- Session control
			vim.keymap.set("n", "<leader>dc", dap.continue, { desc = "󰐊 Continue / start" })
			vim.keymap.set("n", "<leader>di", dap.step_into, { desc = "󰆹 Step into" })
			vim.keymap.set("n", "<leader>do", dap.step_over, { desc = "󰆷 Step over" })
			vim.keymap.set("n", "<leader>dO", dap.step_out, { desc = "󰆸 Step out" })
			vim.keymap.set("n", "<leader>dr", dap.restart, { desc = "󰑓 Restart" })
			vim.keymap.set("n", "<leader>dq", dap.terminate, { desc = "󰓛 Terminate" })

			-- UI
			vim.keymap.set("n", "<leader>du", dapui.toggle, { desc = "󰙀 Toggle UI" })
			vim.keymap.set({ "n", "v" }, "<leader>de", dapui.eval, { desc = "󰆤 Eval expression" })
		end,
	},
}
