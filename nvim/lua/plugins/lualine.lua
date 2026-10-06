-- lualine — statusline.
--
-- Shows the state that matters while you work: git branch and diff counts,
-- diagnostics, which LSP clients are attached, whether a debug session is live,
-- whether format-on-save is suppressed, and whether plugin updates are pending.
--
-- NOTE ON GLYPHS: the separators below are powerline codepoints (U+E0B0-E0B3)
-- and the component icons are Nerd Font ones. They need a Nerd Font set in the
-- terminal (JetBrainsMono Nerd Font — see the README's post-install steps); in a
-- plain font they render as boxes. `./scripts/verify.sh statusline` renders the
-- statusline and asserts the separators are actually present, because an empty
-- separator string is silently accepted and just looks flat.

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
			return "\u{f048b} " .. table.concat(names, " ")
		end

		-- Visible warning that format-on-save is suppressed, so a buffer that
		-- silently stops formatting is never a mystery.
		local function format_disabled()
			if vim.b.disable_autoformat or vim.g.disable_autoformat then
				return "\u{f0276} no format"
			end
			return ""
		end

		local function dap_status()
			local ok, dap = pcall(require, "dap")
			if not ok or not dap.session() then
				return ""
			end
			return "\u{f00e4} " .. dap.status()
		end

		return {
			options = {
				theme = "catppuccin-nvim",
				globalstatus = true,
				-- Powerline separators. Written as \u{...} escapes rather than
				-- literal glyphs: this file has already been mangled once by a
				-- tool that dropped 3-byte PUA codepoints, which turned these
				-- into empty strings and made the statusline render flat with no
				-- divisions at all. Escapes are mangle-proof.
				section_separators = { left = "\u{e0b0}", right = "\u{e0b2}" },
				component_separators = { left = "\u{e0b1}", right = "\u{e0b3}" },
				disabled_filetypes = {
					statusline = { "neo-tree", "dbui", "dapui_scopes", "dapui_watches" },
				},
			},
			sections = {
				lualine_a = { "mode" },
				lualine_b = {
					{ "branch", icon = "\u{f062c}" },
					{
						"diff",
						symbols = { added = "\u{f0415} ", modified = "\u{f03eb} ", removed = "\u{f0374} " },
					},
				},
				lualine_c = {
					{
						"filename",
						path = 1,
						symbols = { modified = "\u{f03eb}", readonly = "\u{f033e}", unnamed = "[No Name]" },
					},
					{
						"diagnostics",
						symbols = {
							error = "\u{f015a} ",
							warn = "\u{f002a} ",
							info = "\u{f02fd} ",
							hint = "\u{f0336} ",
						},
					},
				},
				-- Deliberately short: encoding and fileformat are dropped. They are
				-- utf-8/unix in essentially every buffer, so they cost width without
				-- ever telling you anything.
				lualine_x = {
					{ dap_status, color = { fg = "#f38ba8" } },
					{ format_disabled, color = { fg = "#f9e2af" } },
					{
						-- Pending plugin updates. Visible rather than automatic:
						-- lazy's update checker is disabled (see init.lua) so nothing
						-- changes under you, but you still get told.
						require("lazy.status").updates,
						cond = require("lazy.status").has_updates,
						color = { fg = "#cba6f7" },
					},
					{ lsp_clients, color = { fg = "#89dceb" } },
				},
				lualine_y = { { "filetype", icon_only = false } },
				lualine_z = { { "location", padding = { left = 1, right = 1 } } },
			},
			extensions = { "neo-tree", "lazy", "mason", "trouble", "quickfix", "fugitive", "nvim-dap-ui" },
		}
	end,
}
