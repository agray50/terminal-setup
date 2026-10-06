-- Visual helpers and navigation aids.
--
-- Each of these is small and earns its place by making state visible that was
-- previously invisible: where you are in a file, what changed, which errors
-- exist, what a colour value actually looks like.

return {
	-----------------------------------------------------------------------
	-- Breadcrumbs — "where am I in this file / repo"
	-----------------------------------------------------------------------
	{
		"Bekaboo/dropbar.nvim",
		event = "BufReadPost",
		dependencies = { "nvim-tree/nvim-web-devicons" },
		keys = {
			{
				"<leader>cb",
				function()
					require("dropbar.api").pick()
				end,
				desc = "󰁥 Pick from breadcrumbs",
			},
		},
		opts = {
			bar = {
				-- Only show the winbar for real files; a breadcrumb trail on a
				-- picker or terminal is noise.
				enable = function(buf, win, _)
					return vim.fn.win_gettype(win) == ""
						and vim.wo[win].winbar == ""
						and vim.bo[buf].buftype == ""
						and vim.api.nvim_buf_get_name(buf) ~= ""
						and not vim.wo[win].diff
				end,
			},
			icons = { ui = { bar = { separator = " 󰅂 " } } },
		},
	},

	-----------------------------------------------------------------------
	-- Indent guides
	-----------------------------------------------------------------------
	{
		"lukas-reineke/indent-blankline.nvim",
		main = "ibl",
		event = { "BufReadPost", "BufNewFile" },
		keys = {
			{ "<leader>ug", "<cmd>IBLToggle<cr>", desc = "Toggle indent guides" },
		},
		opts = {
			indent = { char = "│", tab_char = "│" },
			scope = {
				-- Highlight the enclosing block, which is the actually useful
				-- part — it answers "which if am I inside".
				enabled = true,
				show_start = false,
				show_end = false,
			},
			exclude = {
				filetypes = {
					"help",
					"lazy",
					"mason",
					"notify",
					"trouble",
					"neo-tree",
					"dashboard",
					"checkhealth",
					"man",
					"dbui",
					"dbout",
					"neotest-summary",
					"dapui_scopes",
					"dapui_watches",
					"dapui_stacks",
					"dapui_breakpoints",
					"dap-repl",
					"fzf",
				},
			},
		},
	},

	-----------------------------------------------------------------------
	-- Colour swatches — CSS values and Tailwind class colours, inline
	-----------------------------------------------------------------------
	{
		"brenoprata10/nvim-highlight-colors",
		event = { "BufReadPost", "BufNewFile" },
		keys = {
			{ "<leader>uC", "<cmd>HighlightColorsToggle<cr>", desc = "Toggle colour swatches" },
		},
		opts = {
			render = "virtual",
			virtual_symbol = "󰝤",
			virtual_symbol_position = "inline",
			-- Resolve Tailwind class names (bg-blue-500) to their real colour,
			-- not just raw hex values. This is the bit that matters when
			-- working in a Tailwind codebase.
			enable_tailwind = true,
			enable_named_colors = true,
			exclude_filetypes = { "lazy", "mason", "neo-tree", "trouble" },
		},
	},

	-----------------------------------------------------------------------
	-- TODO / FIXME highlighting and indexing
	-----------------------------------------------------------------------
	{
		"folke/todo-comments.nvim",
		event = { "BufReadPost", "BufNewFile" },
		dependencies = { "nvim-lua/plenary.nvim" },
		cmd = { "TodoTrouble", "TodoFzfLua" },
		keys = {
			{ "<leader>ft", "<cmd>TodoFzfLua<cr>", desc = "󰄬 Find TODOs" },
			{ "<leader>xt", "<cmd>TodoTrouble<cr>", desc = "󰄬 TODOs (trouble)" },
			{ "<leader>xT", "<cmd>TodoTrouble keywords=TODO,FIX,FIXME<cr>", desc = "󰄬 TODO/FIX only (trouble)" },
			{
				"]y",
				function()
					require("todo-comments").jump_next()
				end,
				desc = "Next TODO comment",
			},
			{
				"[y",
				function()
					require("todo-comments").jump_prev()
				end,
				desc = "Previous TODO comment",
			},
		},
		opts = { signs = true },
	},

	-----------------------------------------------------------------------
	-- Motion — jump anywhere visible in two keystrokes
	-----------------------------------------------------------------------
	{
		"folke/flash.nvim",
		event = "VeryLazy",
		-- Deliberately does NOT take over `s` / `S` / visual `R`.
		--
		-- flash's own defaults bind those, but in stock vim they are
		-- substitute-char, substitute-line and visual-substitute — real
		-- operators with no equally short replacement (`cl` / `cc` are the
		-- usual suggestion, but they are not the same keystroke count and `s`
		-- in particular is muscle memory). Jumping lives on <leader>j instead.
		--
		-- The two bindings kept on their flash defaults are operator-pending
		-- only (`dr`, `yR`, …), where vim has no default meaning to shadow.
		keys = {
			{
				"<leader>j",
				mode = { "n", "x", "o" },
				function()
					require("flash").jump()
				end,
				desc = "󱐋 Flash jump",
			},
			{
				"<leader>J",
				mode = { "n", "x", "o" },
				function()
					require("flash").treesitter()
				end,
				desc = "󱐋 Flash treesitter select",
			},
			{
				"r",
				mode = "o",
				function()
					require("flash").remote()
				end,
				desc = "Remote flash (operate elsewhere)",
			},
			{
				-- Operator-pending only. The `x` (visual) mode binding flash
				-- ships here is dropped: visual `R` is change-whole-lines.
				"R",
				mode = "o",
				function()
					require("flash").treesitter_search()
				end,
				desc = "Flash treesitter search",
			},
			{
				"<C-s>",
				mode = "c",
				function()
					require("flash").toggle()
				end,
				desc = "Toggle flash while searching",
			},
		},
		opts = {
			modes = {
				-- Don't hijack plain / and ? search; that gets disorienting.
				search = { enabled = false },
				char = { enabled = true, jump_labels = true },
			},
		},
	},

	-----------------------------------------------------------------------
	-- mini.nvim pieces — notifications and pairs
	-----------------------------------------------------------------------
	{
		"echasnovski/mini.nvim",
		version = false,
		event = "VeryLazy",
		config = function()
			-- Notifications. Previously vim.notify messages flashed past in the
			-- command area and were gone, which is a large part of why breakage
			-- felt "random" — the error was there, you just never saw it.
			require("mini.notify").setup({
				content = {
					format = function(notif)
						return notif.msg
					end,
				},
				window = {
					config = { border = "rounded" },
					winblend = 0,
				},
				lsp_progress = { enable = true, duration_last = 500 },
			})
			vim.notify = require("mini.notify").make_notify({
				ERROR = { duration = 10000 },
				WARN = { duration = 6000 },
				INFO = { duration = 3000 },
			})

			vim.keymap.set("n", "<leader>un", function()
				require("mini.notify").show_history()
			end, { desc = "󰂞 Show notification history" })

			-- Replaces nvim-autopairs. Treesitter-aware, part of the mini
			-- family already loaded here, so one less plugin to pin. (The
			-- README previously claimed blink.pairs while the config actually
			-- had nvim-autopairs — this resolves that drift.)
			require("mini.pairs").setup({
				modes = { insert = true, command = false, terminal = false },
				-- Don't auto-pair before a word character: typing `(` before
				-- existing text should not insert `()`.
				skip_next = [=[[%w%%%'%[%"%.%`%$]]=],
				skip_ts = { "string" },
				skip_unbalanced = true,
				markdown = true,
			})

			-- Surround: csw" to quote a word, ds" to unquote. Fills the one
			-- real gap left by treesitter text objects.
			require("mini.surround").setup({
				mappings = {
					add = "gsa",
					delete = "gsd",
					replace = "gsr",
					find = "gsf",
					find_left = "gsF",
					highlight = "gsh",
					update_n_lines = "gsn",
				},
			})
		end,
	},

	-----------------------------------------------------------------------
	-- Undo history
	-----------------------------------------------------------------------
	-- Neovim 0.12 ships an undotree; no plugin needed. Moved from <leader>u
	-- (now the UI toggle group) to <leader>uu.
	{
		"folke/which-key.nvim",
		optional = true,
		keys = {
			{
				"<leader>uu",
				function()
					-- packadd is idempotent, so no need to track loaded state.
					pcall(vim.cmd, "packadd nvim.undotree")
					vim.cmd("Undotree")
				end,
				desc = "󰕌 Toggle undo tree",
			},
		},
	},
}
