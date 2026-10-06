-- lualine — statusline.
--
-- Was nine lines of defaults. Now surfaces the state that matters while you
-- work: which LSP clients are attached, whether a debug session is live,
-- whether format-on-save is off, and whether plugin updates are pending.

return {
	"nvim-lualine/lualine.nvim",
	event = "VeryLazy",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	opts = function()
		-- Which LSP clients are attached to this buffer? Answers "why is
		-- completion not working here" at a glance.
		local function lsp_clients()
			local clients = vim.lsp.get_clients({ bufnr = 0 })
			if #clients == 0 then
				return ""
			end
			local names = {}
			for _, client in ipairs(clients) do
				table.insert(names, client.name)
			end
			return "󰒋 " .. table.concat(names, ",")
		end

		-- Visible warning that format-on-save is suppressed, so a buffer that
		-- silently stops formatting is never a mystery.
		local function format_disabled()
			if vim.b.disable_autoformat or vim.g.disable_autoformat then
				return "󰉶 off"
			end
			return ""
		end

		local function dap_status()
			local ok, dap = pcall(require, "dap")
			if not ok or not dap.session() then
				return ""
			end
			return "󰃤 " .. dap.status()
		end

		return {
			options = {
				-- NOT "catppuccin" — catppuccin ships no theme by that name, only
				-- catppuccin-{nvim,mocha,latte,macchiato,frappe}. lualine only
				-- *warns* on an unknown theme and silently falls back to "auto",
				-- so a wrong name here is invisible unless you read the message.
				-- "catppuccin-nvim" resolves the active flavour at runtime, so it
				-- follows whatever colorscheme is set in plugins/catppuccin.lua
				-- rather than hard-coding mocha in a second place.
				theme = "catppuccin-nvim",
				globalstatus = true,
				component_separators = { left = "", right = "" },
				section_separators = { left = "", right = "" },
				disabled_filetypes = {
					statusline = { "neo-tree", "dbui", "dapui_scopes", "dapui_watches" },
				},
			},
			sections = {
				lualine_a = { "mode" },
				lualine_b = { "branch" },
				lualine_c = {
					{
						"diff",
						symbols = { added = "󰐕 ", modified = "󰏫 ", removed = "󰍴 " },
					},
					{
						"diagnostics",
						symbols = { error = "󰅚 ", warn = "󰀪 ", info = "󰋽 ", hint = "󰌶 " },
					},
					{ "filename", path = 1, symbols = { modified = "󰏫", readonly = "󰌾" } },
				},
				lualine_x = {
					{ dap_status, color = { fg = "#f38ba8" } },
					{ format_disabled, color = { fg = "#f9e2af" } },
					{
						-- Pending plugin updates. Visible rather than automatic:
						-- lazy's update checker is disabled (see init.lua) so
						-- nothing changes under you, but you still get told.
						require("lazy.status").updates,
						cond = require("lazy.status").has_updates,
						color = { fg = "#cba6f7" },
					},
					{ lsp_clients, color = { fg = "#89dceb" } },
					"encoding",
					{ "fileformat", symbols = { unix = "", dos = "", mac = "" } },
					"filetype",
				},
				lualine_y = { "progress" },
				lualine_z = { "location" },
			},
			extensions = { "neo-tree", "lazy", "mason", "trouble", "quickfix", "fugitive", "nvim-dap-ui" },
		}
	end,
}
