return {
	{
		"nvim-telescope/telescope.nvim",
		dependencies = {
			"nvim-lua/plenary.nvim",
			{ "nvim-telescope/telescope-fzf-native.nvim", build = "make" },
			"nvim-telescope/telescope-ui-select.nvim",
		},
		cmd = "Telescope",
		keys = {
			{ "<leader>fp", function() require("telescope.builtin").find_files() end, desc = "Find files" },
			{ "<leader>ff", function() require("telescope.builtin").current_buffer_fuzzy_find() end, desc = "Find in buffer" },
			{ "<leader>fg", function() require("telescope.builtin").live_grep() end, desc = "Live grep" },
			{ "<leader>fw", function() require("telescope.builtin").grep_string() end, desc = "Grep word under cursor" },
			{ "<leader>fb", function() require("telescope.builtin").buffers() end, desc = "Buffers" },
			{ "<leader>fr", function() require("telescope.builtin").oldfiles() end, desc = "Recent files" },
			{ "<leader>fh", function() require("telescope.builtin").help_tags() end, desc = "Help tags" },
			{ "<leader>fk", function() require("telescope.builtin").keymaps() end, desc = "Keymaps" },
			{ "<leader>fc", function() require("telescope.builtin").commands() end, desc = "Commands" },
			{ "<leader>gc", function() require("telescope.builtin").git_commits() end, desc = "Git commits" },
			{ "<leader>gs", function() require("telescope.builtin").git_status() end, desc = "Git status" },
		},
		config = function()
			local telescope = require("telescope")
			telescope.setup({
				extensions = {
					fzf = {},
					["ui-select"] = {
						require("telescope.themes").get_dropdown({}),
					},
				},
			})
			telescope.load_extension("fzf")
			telescope.load_extension("ui-select")
		end,
	},
}
