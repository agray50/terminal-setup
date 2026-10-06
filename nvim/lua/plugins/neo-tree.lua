-- neo-tree — file explorer.
--
-- <C-n> toggles it (unchanged); <leader>ue reveals the current file in the
-- tree, which is the operation that was previously missing and sent you back to
-- a graphical editor to get your bearings.

return {
	"nvim-neo-tree/neo-tree.nvim",
	branch = "v3.x",
	dependencies = {
		"nvim-lua/plenary.nvim",
		"MunifTanjim/nui.nvim",
		"nvim-tree/nvim-web-devicons",
	},
	cmd = "Neotree",
	keys = {
		{ "<C-n>", "<cmd>Neotree toggle<cr>", desc = "󰙅 Toggle file explorer" },
		{ "<leader>ue", "<cmd>Neotree toggle<cr>", desc = "󰙅 Toggle file explorer" },
		{ "<leader>uE", "<cmd>Neotree reveal<cr>", desc = "󰈞 Reveal current file in tree" },
		{ "<leader>ub", "<cmd>Neotree toggle show buffers right<cr>", desc = "󰓩 Buffer tree" },
		{ "<leader>uG", "<cmd>Neotree float git_status<cr>", desc = "󰊢 Git status tree" },
	},
	opts = {
		close_if_last_window = true,
		popup_border_style = "rounded",
		enable_git_status = true,
		enable_diagnostics = true,
		-- Hide the directories that make a JS/Java tree unusable, but keep them
		-- one keystroke away (H toggles hidden).
		filesystem = {
			filtered_items = {
				visible = false,
				hide_dotfiles = false,
				hide_gitignored = true,
				hide_by_name = { "node_modules", "__pycache__", ".git", "target", ".terraform" },
				never_show = { ".DS_Store", "thumbs.db" },
			},
			follow_current_file = { enabled = true, leave_dirs_open = true },
			use_libuv_file_watcher = true,
			group_empty_dirs = true,
		},
		window = {
			width = 34,
			mappings = {
				-- q closes, matching every other panel in this config.
				["q"] = "close_window",
				["<C-n>"] = "close_window",
				["h"] = "close_node",
				["l"] = "open",
				["H"] = "toggle_hidden",
				["o"] = "open",
				["O"] = "expand_all_nodes",
				["Y"] = function(state)
					-- Copy the relative path of the node under the cursor —
					-- the thing you usually want a file tree for.
					local node = state.tree:get_node()
					local path = vim.fn.fnamemodify(node.path, ":.")
					vim.fn.setreg("+", path)
					vim.notify("Copied: " .. path)
				end,
			},
		},
		default_component_configs = {
			git_status = {
				symbols = {
					added = "󰐕",
					modified = "󰏫",
					deleted = "󰍴",
					renamed = "󰁕",
					untracked = "󰋗",
					ignored = "󰛑",
					unstaged = "󰄱",
					staged = "󰱒",
					conflict = "󰞇",
				},
			},
		},
	},
}
