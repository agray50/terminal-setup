return {
	{
		"NeogitOrg/neogit",
		dependencies = {
			"nvim-lua/plenary.nvim",
			"sindrets/diffview.nvim",
			"nvim-telescope/telescope.nvim",
		},
		cmd = "Neogit",
		opts = {
			integrations = {
				diffview = true,
				telescope = true,
			},
		},
		keys = {
			{ "<leader>gg", "<cmd>Neogit<cr>", desc = "Open Neogit" },
		},
	},
	{
		"sindrets/diffview.nvim",
		cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewToggleFiles", "DiffviewFocusFiles" },
	},
	{
		"lewis6991/gitsigns.nvim",
		opts = {
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
				end, { desc = "Next change" })
				map("n", "[c", function()
					if vim.wo.diff then
						vim.cmd.normal({ "[c", bang = true })
					else
						gitsigns.nav_hunk("prev")
					end
				end, { desc = "Prev change" })

				-- Actions
				map("n", "<leader>hs", gitsigns.stage_hunk, { desc = "Stage hunk" })
				map("n", "<leader>hr", gitsigns.reset_hunk, { desc = "Reset hunk" })
				map("v", "<leader>hs", function()
					gitsigns.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
				end, { desc = "Stage selected hunks" })
				map("v", "<leader>hr", function()
					gitsigns.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
				end, { desc = "Reset selected hunks" })
				map("n", "<leader>hS", gitsigns.stage_buffer, { desc = "Stage buffer" })
				map("n", "<leader>hR", gitsigns.reset_buffer, { desc = "Reset buffer" })
				map("n", "<leader>hp", gitsigns.preview_hunk, { desc = "Preview hunk" })
				map("n", "<leader>hi", gitsigns.preview_hunk_inline, { desc = "Preview hunk inline" })
				map("n", "<leader>hb", function()
					gitsigns.blame_line({ full = true })
				end, { desc = "Blame line" })
				map("n", "<leader>hd", gitsigns.diffthis, { desc = "Diff this" })
				map("n", "<leader>hD", function()
					gitsigns.diffthis("~")
				end, { desc = "Diff this (HEAD~)" })
				map("n", "<leader>hq", gitsigns.setqflist, { desc = "Quickfix changes" })
				map("n", "<leader>hQ", function()
					gitsigns.setqflist("all")
				end, { desc = "Quickfix all changes" })

				-- Toggles
				map("n", "<leader>tb", gitsigns.toggle_current_line_blame, { desc = "Toggle line blame" })
				map("n", "<leader>tw", gitsigns.toggle_word_diff, { desc = "Toggle word diff" })

				-- Text object
				map({ "o", "x" }, "ih", gitsigns.select_hunk, { desc = "Inner hunk" })
			end,
		},
	},
}
