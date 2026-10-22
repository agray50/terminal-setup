-- Seamless <C-h/j/k/l> movement between nvim splits and tmux panes.
--
-- The plugin's own plugin/tmux_navigator.vim maps <C-h/j/k/l> *and* <C-\> the
-- moment it loads, which is after lazy has registered its key stubs and long
-- after core/keymaps.lua has run. That made <C-\> navigate to the previous
-- tmux pane rather than toggle the floating terminal, so the terminal could be
-- closed but never opened — while the README documented it as working.
--
-- Suppressing the built-in mappings and declaring them here is what keeps
-- <C-\> free, and it gives the four pane keys a `desc` so which-key will show
-- them (which-key.lua filters out mappings with no description).
return {
	"christoomey/vim-tmux-navigator",
	cmd = {
		"TmuxNavigateLeft",
		"TmuxNavigateDown",
		"TmuxNavigateUp",
		"TmuxNavigateRight",
		"TmuxNavigatorProcessList",
	},
	init = function()
		vim.g.tmux_navigator_no_mappings = 1

		-- The plugin also declines to map terminal mode once no_mappings is
		-- set, so reproduce that half here. Only meaningful inside tmux, and
		-- fzf needs these keys for its own UI.
		if vim.env.TMUX and vim.env.TMUX ~= "" then
			for key, dir in pairs({ h = "Left", j = "Down", k = "Up", l = "Right" }) do
				vim.keymap.set("t", "<C-" .. key .. ">", function()
					if vim.bo.filetype == "fzf" then
						return "<C-" .. key .. ">"
					end
					return "<C-w>:<C-U>TmuxNavigate" .. dir .. "<cr>"
				end, { expr = true, silent = true, desc = "Pane " .. dir:lower() .. " (tmux-aware)" })
			end
		end
	end,
	keys = {
		{ "<C-h>", "<cmd>TmuxNavigateLeft<cr>", desc = "󰁍 Pane left (tmux-aware)" },
		{ "<C-j>", "<cmd>TmuxNavigateDown<cr>", desc = "󰁅 Pane below (tmux-aware)" },
		{ "<C-k>", "<cmd>TmuxNavigateUp<cr>", desc = "󰁝 Pane above (tmux-aware)" },
		{ "<C-l>", "<cmd>TmuxNavigateRight<cr>", desc = "󰁔 Pane right (tmux-aware)" },
	},
}
