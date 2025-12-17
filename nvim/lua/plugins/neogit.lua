return {
	{
		"NeogitOrg/neogit",
		lazy = true,
		dependencies = {
			"nvim-lua/plenary.nvim",
			"sindrets/diffview.nvim",
			"nvim-telescope/telescope.nvim",
		},
		cmd = "Neogit",
		integrations = {
			diffview = true,
		},
		keys = {
			{ "<leader>gg", "<cmd>Neogit<cr>", desc = "Show Neogit UI" },
		},
	},
	{
		"sindrets/diffview.nvim",
		cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFocusFiles" },
	},
	{
		"lewis6991/gitsigns.nvim",
		config = function()
			require("gitsigns").setup({
				on_attach = function(bufnr)
					local gitsigns = require("gitsigns")

					local function map(mode, l, r, opts)
						opts = opts or {}
						opts.buffer = bufnr
						vim.keymap.set(mode, l, r, opts)
					end

					-- Navigation
					map("n", "]c", function()
						if vim.wo.diff then
							vim.cmd.normal({ "]c", bang = true })
						else
							gitsigns.nav_hunk("next")
						end
					end, { desc = "Next Change" })
					map("n", "[c", function()
						if vim.wo.diff then
							vim.cmd.normal({ "[c", bang = true })
						else
							gitsigns.nav_hunk("prev")
						end
					end, { desc = "Previous Change" })

					-- Actions
					map("n", "<leader>hs", gitsigns.stage_hunk, { desc = "Stage Hunk" })
					map("n", "<leader>hr", gitsigns.reset_hunk, { desc = "Reset Hunk" })
					map("v", "<leader>hs", function()
						gitsigns.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
					end, { desc = "Stage Selected Hunks" })
					map("v", "<leader>hr", function()
						gitsigns.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
					end, { desc = "Reset Selected Hunks" })
					map("n", "<leader>hS", gitsigns.stage_buffer, { desc = "Stage Buffer" })
					map("n", "<leader>hR", gitsigns.reset_buffer, { desc = "Reset Buffer" })
					map("n", "<leader>hp", gitsigns.preview_hunk, { desc = "Preview Hunk" })
					map("n", "<leader>hi", gitsigns.preview_hunk_inline, { desc = "Preview Hunk Inline" })
					map("n", "<leader>hb", function()
						gitsigns.blame_line({ full = true })
					end, { desc = "Blame Line" })
					map("n", "<leader>hd", gitsigns.diffthis, { desc = "Diff This" })
					map("n", "<leader>hD", function()
						gitsigns.diffthis("~")
					end, { desc = "Diff This (HEAD~)" })
					map("n", "<leader>hQ", function()
						gitsigns.setqflist("all")
					end, { desc = "Quickfix All Changes" })
					map("n", "<leader>hq", gitsigns.setqflist, { desc = "Quickfix Changes" })

					-- Toggles
					map("n", "<leader>tb", gitsigns.toggle_current_line_blame, { desc = "Toggle Line Blame" })
					map("n", "<leader>tw", gitsigns.toggle_word_diff, { desc = "Toggle Word Diff" })

					-- Text object
					map({ "o", "x" }, "ih", gitsigns.select_hunk, { desc = "Select Inner Hunk" })
				end,
			})
		end,
	},
}
