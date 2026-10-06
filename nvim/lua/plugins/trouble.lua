-- trouble.nvim — the <leader>x group.
--
-- A fuzzy picker is the wrong tool for working through a list of errors: you
-- want the whole list visible, grouped by file, navigable without reopening it.
-- That's what this is for. fzf-lua stays for "find me the one thing I'm
-- thinking of"; trouble is for "show me everything that's wrong".

return {
	"folke/trouble.nvim",
	cmd = { "Trouble", "TroubleToggle" },
	keys = {
		{ "<leader>xx", "<cmd>Trouble diagnostics toggle filter.buf=0<cr>", desc = "󰅚 Diagnostics (this buffer)" },
		{ "<leader>xX", "<cmd>Trouble diagnostics toggle<cr>", desc = "󰅚 Diagnostics (workspace)" },
		{ "<leader>xs", "<cmd>Trouble symbols toggle<cr>", desc = "󰫧 Symbol outline" },
		{ "<leader>xr", "<cmd>Trouble lsp toggle<cr>", desc = "󰈇 LSP references / defs" },
		{ "<leader>xq", "<cmd>Trouble qflist toggle<cr>", desc = "󰌧 Quickfix list" },
		{ "<leader>xl", "<cmd>Trouble loclist toggle<cr>", desc = "󰌧 Location list" },
		-- Paired close, consistent with <leader>gx for diffview.
		{ "<leader>xc", "<cmd>Trouble close<cr>", desc = "󰅖 Close trouble" },
		-- Jump between items without the list focused.
		{
			"]x",
			function()
				require("trouble").next({ skip_groups = true, jump = true })
			end,
			desc = "Next trouble item",
		},
		{
			"[x",
			function()
				require("trouble").prev({ skip_groups = true, jump = true })
			end,
			desc = "Previous trouble item",
		},
	},
	opts = {
		focus = true,
		-- Don't auto-open on diagnostics: that fights you while typing.
		auto_close = true,
		auto_preview = true,
		modes = {
			-- A symbol outline docked to the right, which is the "where am I in
			-- this file" view. Replaces needing a separate outline plugin.
			symbols = {
				desc = "Symbol outline",
				win = { position = "right", size = 0.25 },
				filter = {
					-- Hide the noise kinds that make a Java or TS outline
					-- unreadable.
					["not"] = { ft = "lua", kind = "Package" },
					any = {
						ft = { "help", "markdown" },
						kind = {
							"Class",
							"Constructor",
							"Enum",
							"Field",
							"Function",
							"Interface",
							"Method",
							"Module",
							"Namespace",
							"Package",
							"Property",
							"Struct",
							"Trait",
						},
					},
				},
			},
			lsp = {
				win = { position = "right", size = 0.3 },
			},
		},
		icons = {
			indent = {
				middle = " ",
				last = " ",
				top = " ",
				ws = "│  ",
			},
		},
	},
}
