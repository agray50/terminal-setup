-- fzf-lua — the picker.
--
-- Replaces telescope.nvim (+ telescope-fzf-native + telescope-ui-select), which
-- had accumulated a large issue backlog and needed a `make`-compiled C extension
-- that broke whenever the toolchain moved. fzf-lua shells out to the `fzf`
-- binary setup.sh already installs, so there is nothing to compile here.
--
-- Keymaps: <leader>f (find). LSP navigation (gd/grr/gri/...) is registered in
-- lsp-config.lua's LspAttach handler and routes through here. Git pickers live
-- in git.lua under <leader>g so all git keys are in one place.

local function fzf(fn, opts)
	return function()
		require("fzf-lua")[fn](opts)
	end
end

return {
	"ibhagwan/fzf-lua",
	dependencies = { "nvim-tree/nvim-web-devicons" },
	cmd = "FzfLua",
	keys = {
		-- Fast aliases for the three pickers used constantly.
		{ "<leader><space>", fzf("files"), desc = "󰈞 Find files" },
		{ "<leader>/", fzf("live_grep"), desc = "󰱼 Grep project" },
		{ "<leader>,", fzf("buffers"), desc = "󰓩 Buffers" },

		-- Files and content
		{ "<leader>ff", fzf("files"), desc = "󰈞 Files" },
		{ "<leader>fg", fzf("live_grep"), desc = "󰱼 Grep (project)" },
		{ "<leader>fG", fzf("grep_cword"), desc = "󰱼 Grep word under cursor" },
		{ "<leader>fG", fzf("grep_visual"), mode = "v", desc = "󰱼 Grep selection" },
		{ "<leader>fb", fzf("buffers"), desc = "󰓩 Buffers" },
		{ "<leader>fr", fzf("oldfiles"), desc = "󰋚 Recent files" },
		{ "<leader>fl", fzf("blines"), desc = "󰦨 Lines (this buffer)" },
		{ "<leader>fL", fzf("lines"), desc = "󰦨 Lines (all buffers)" },

		-- Symbols
		{ "<leader>fs", fzf("lsp_document_symbols"), desc = "󰫧 Document symbols" },
		{ "<leader>fS", fzf("lsp_live_workspace_symbols"), desc = "󰫧 Workspace symbols" },

		-- Navigation history
		{ "<leader>fm", fzf("marks"), desc = "󰸕 Marks" },
		{ "<leader>fj", fzf("jumps"), desc = "󱋿 Jumplist" },
		{ "<leader>fq", fzf("quickfix"), desc = "󰌧 Quickfix list" },

		-- Vim introspection — the closest thing to a command palette
		{ "<leader>fh", fzf("helptags"), desc = "󰋖 Help tags" },
		{ "<leader>fk", fzf("keymaps"), desc = "󰌌 Keymaps" },
		{ "<leader>fc", fzf("commands"), desc = "󰘳 Commands" },
		{ "<leader>fC", fzf("colorschemes"), desc = "󰸌 Colorschemes" },
		{ "<leader>f:", fzf("command_history"), desc = "󰘳 Command history" },
		{ "<leader>f?", fzf("search_history"), desc = "󰍉 Search history" },

		-- Reopen the last picker exactly where you left it. The single biggest
		-- day-to-day win over the previous setup, which had no equivalent.
		{ "<leader>fR", fzf("resume"), desc = "󰑓 Resume last picker" },
	},
	opts = function()
		local actions = require("fzf-lua.actions")
		return {
			-- "border-fused" gives one continuous border around list+preview
			-- rather than two stacked boxes.
			"border-fused",

			defaults = {
				-- Show the filename before its directory. Makes long monorepo
				-- paths readable, where the useful part is otherwise off-screen.
				formatter = "path.filename_first",
			},

			winopts = {
				height = 0.85,
				width = 0.85,
				row = 0.4,
				border = "rounded",
				preview = {
					-- flex switches between vertical and horizontal split based
					-- on window width, so pickers stay usable in a narrow split.
					layout = "flex",
					flip_columns = 140,
					scrollbar = "float",
				},
			},

			-- Inherit the active colorscheme instead of fzf's own palette.
			fzf_colors = true,

			keymap = {
				builtin = {
					["<C-/>"] = "toggle-help",
					["<C-e>"] = "toggle-preview",
					["<C-k>"] = "preview-up",
					["<C-j>"] = "preview-down",
				},
				fzf = {
					["ctrl-z"] = "abort",
					["ctrl-u"] = "unix-line-discard",
					["ctrl-a"] = "beginning-of-line",
					["ctrl-g"] = "end-of-line",
					["ctrl-e"] = "toggle-preview",
					["ctrl-k"] = "preview-up",
					["ctrl-j"] = "preview-down",
					["ctrl-q"] = "select-all+accept",
				},
			},

			actions = {
				files = {
					["enter"] = actions.file_edit_or_qf,
					["ctrl-s"] = actions.file_split,
					["ctrl-v"] = actions.file_vsplit,
					["ctrl-t"] = actions.file_tabedit,
					-- ctrl-q sends the whole result set to the quickfix list,
					-- which pairs with <leader>xq (trouble) for bulk edits.
					["ctrl-q"] = actions.file_sel_to_qf,
				},
			},

			previewers = {
				builtin = {
					-- Treesitter-highlighted previews; skip very large files so
					-- the picker never stalls on a minified bundle or lockfile.
					syntax_limit_b = 1024 * 100,
				},
			},

			files = {
				-- fd is installed by setup.sh and is markedly faster than find.
				fd_opts = "--color=never --type f --hidden --follow --exclude .git --exclude node_modules",
				git_icons = true,
				file_icons = true,
			},

			grep = {
				rg_opts = "--column --line-number --no-heading --color=always "
					.. "--smart-case --max-columns=4096 --hidden "
					.. "--glob=!.git/ --glob=!node_modules/",
				-- Type `foo --glob=*.ts` to scope a search without leaving the
				-- picker; everything after -- is passed through to ripgrep.
				rg_glob = true,
			},

			git = {
				-- delta (installed by setup.sh, and git's pager via
				-- git/gitconfig) renders these previews, so diffs look the same
				-- in the picker, the pager and lazygit.
				commits = {
					preview_pager = "delta --width=$FZF_PREVIEW_COLUMNS",
				},
				bcommits = {
					preview_pager = "delta --width=$FZF_PREVIEW_COLUMNS",
				},
				status = {
					preview_pager = "delta --width=$FZF_PREVIEW_COLUMNS",
					actions = {
						-- Stage/unstage straight from the status picker.
						["right"] = { fn = actions.git_unstage, reload = true },
						["left"] = { fn = actions.git_stage, reload = true },
						["ctrl-x"] = { fn = actions.git_reset, reload = true },
					},
				},
				-- Match the gitsigns glyphs so both surfaces agree.
				icons = {
					["M"] = { icon = "󰏫", color = "yellow" },
					["A"] = { icon = "󰐕", color = "green" },
					["D"] = { icon = "󰍴", color = "red" },
					["R"] = { icon = "󰁕", color = "yellow" },
					["C"] = { icon = "󰆏", color = "yellow" },
					["?"] = { icon = "󰋗", color = "magenta" },
				},
			},

			lsp = {
				-- Jump straight there when a symbol has exactly one result,
				-- instead of showing a one-item picker.
				jump1 = true,
				includeDeclaration = false,
				symbols = {
					symbol_hl = function(s)
						return "TroubleIcon" .. s
					end,
				},
			},

			diagnostics = {
				multiline = false,
			},
		}
	end,
	config = function(_, opts)
		local fzflua = require("fzf-lua")
		fzflua.setup(opts)
		-- Route vim.ui.select (code actions, rename pickers, etc.) through
		-- fzf-lua. Replaces telescope-ui-select, which was a separate plugin.
		fzflua.register_ui_select()
	end,
}
