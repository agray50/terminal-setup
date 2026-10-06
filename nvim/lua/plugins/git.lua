-- Git — four tools, four clearly separated jobs, all under <leader>g.
--
--   lazygit   <leader>gg       interactive rebase, conflicts, stash, amend
--   fzf-lua   <leader>gc/gb/.. history, branches, status, stashes (delta previews)
--   diffview  <leader>gd/gD/gm structured multi-file diff + 3-way merge review
--   gitsigns  <leader>gh*      inline hunk staging and navigation
--   fugitive  <leader>gv/gy    3-way conflict splits and open-in-browser
--
-- Everything that opens has a matching close: <leader>gx closes diffview,
-- <leader>gg toggles lazygit, and <leader>qz closes every tool panel at once.

local function fzf(fn, opts)
	return function()
		require("fzf-lua")[fn](opts)
	end
end

return {
	-----------------------------------------------------------------------
	-- lazygit — primary git UI, in a floating terminal
	-----------------------------------------------------------------------
	-- Not a plugin: lazygit is a binary (pinned in versions.lock) launched
	-- through util/float.lua. kdheepak/lazygit.nvim would add a dependency to
	-- do what three lines of vim.api already do, and the float helper is shared
	-- with the <C-\> terminal and k9s so all three behave identically.
	{
		"folke/which-key.nvim", -- anchor spec; no plugin needed for these keys
		optional = true,
		keys = {
			{
				"<leader>gg",
				function()
					if vim.fn.executable("lazygit") == 0 then
						vim.notify("lazygit not found in PATH — run ./setup.sh to install it", vim.log.levels.ERROR)
						return
					end
					require("util.float").toggle({
						name = "lazygit",
						cmd = "lazygit",
						title = "lazygit",
						scale = 0.95,
					})
				end,
				desc = "󰊢 Lazygit (rebase, stash, amend)",
			},
			{
				"<leader>gG",
				function()
					require("util.float").toggle({
						name = "lazygit-file",
						cmd = { "lazygit", "--filter", vim.api.nvim_buf_get_name(0) },
						title = "lazygit: " .. vim.fn.expand("%:t"),
						scale = 0.95,
					})
				end,
				desc = "󰊢 Lazygit (this file's history)",
			},
		},
	},

	-----------------------------------------------------------------------
	-- fzf-lua git pickers
	-----------------------------------------------------------------------
	-- Declared here rather than in fzf-lua.lua so every git key is in one
	-- file. lazy.nvim hooks `require`, so calling require("fzf-lua") from these
	-- handlers loads the plugin on first use.
	{
		"ibhagwan/fzf-lua",
		keys = {
			{ "<leader>gc", fzf("git_commits"), desc = "󰜘 Commits (repo)" },
			{ "<leader>gC", fzf("git_bcommits"), desc = "󰜘 Commits (this file)" },
			{ "<leader>gb", fzf("git_branches"), desc = "󰘬 Branches" },
			{ "<leader>gs", fzf("git_status"), desc = "󰋽 Status" },
			{ "<leader>gS", fzf("git_stash"), desc = "󰆓 Stashes" },
			{ "<leader>gt", fzf("git_tags"), desc = "󰓹 Tags" },
		},
	},

	-----------------------------------------------------------------------
	-- diffview — structured review and 3-way merge
	-----------------------------------------------------------------------
	-- Upstream is quiet, which is acceptable precisely because every version
	-- here is frozen: a pinned plugin on a pinned Neovim does not rot. It earns
	-- its place for multi-file side-by-side review and the merge tool, which
	-- lazygit does less well. Previously this plugin had NO keymaps at all and
	-- could only be reached by typing :DiffviewOpen.
	{
		"sindrets/diffview.nvim",
		dependencies = { "nvim-lua/plenary.nvim" },
		cmd = { "DiffviewOpen", "DiffviewClose", "DiffviewFileHistory", "DiffviewToggleFiles", "DiffviewFocusFiles" },
		keys = {
			{ "<leader>gd", "<cmd>DiffviewOpen<cr>", desc = "󰦓 Diff working tree" },
			{ "<leader>gD", "<cmd>DiffviewFileHistory %<cr>", desc = "󰋚 File history (this file)" },
			{ "<leader>gH", "<cmd>DiffviewFileHistory<cr>", desc = "󰋚 File history (repo)" },
			{ "<leader>gM", "<cmd>DiffviewOpen origin/HEAD...HEAD<cr>", desc = "󰦓 Diff vs origin/HEAD" },
			-- During a merge or rebase with conflicts, this opens the 3-way
			-- view over just the conflicted files.
			{ "<leader>gm", "<cmd>DiffviewOpen<cr>", desc = "󰘬 Resolve conflicts (3-way)" },
			-- Paired close, so opening a panel never leaves you guessing.
			{ "<leader>gx", "<cmd>DiffviewClose<cr>", desc = "󰅖 Close diff view" },
		},
		opts = function()
			local actions = require("diffview.actions")
			return {
				enhanced_diff_hl = true,
				view = {
					merge_tool = {
						-- 3-way with the common ancestor visible: you can see
						-- what each side actually changed. Matches the
						-- merge.conflictstyle=zdiff3 set in git/gitconfig.
						layout = "diff3_mixed",
						disable_diagnostics = true,
					},
				},
				file_panel = {
					listing_style = "tree",
					win_config = { width = 32 },
				},
				keymaps = {
					view = {
						{ "n", "<leader>gx", actions.close, { desc = "Close diff view" } },
						{ "n", "<tab>", actions.select_next_entry, { desc = "Next file" } },
						{ "n", "<s-tab>", actions.select_prev_entry, { desc = "Previous file" } },
						{ "n", "gf", actions.goto_file_edit, { desc = "Open file in previous tab" } },
						-- Conflict resolution, mirroring git's own vocabulary.
						{ "n", "<leader>co", actions.conflict_choose("ours"), { desc = "Conflict: take ours" } },
						{ "n", "<leader>ct", actions.conflict_choose("theirs"), { desc = "Conflict: take theirs" } },
						{ "n", "<leader>cb", actions.conflict_choose("base"), { desc = "Conflict: take base" } },
						{ "n", "<leader>ca", actions.conflict_choose("all"), { desc = "Conflict: take all" } },
						{ "n", "<leader>cn", actions.conflict_choose("none"), { desc = "Conflict: take none" } },
						{ "n", "]x", actions.next_conflict, { desc = "Next conflict" } },
						{ "n", "[x", actions.prev_conflict, { desc = "Previous conflict" } },
					},
					file_panel = {
						{ "n", "<leader>gx", actions.close, { desc = "Close diff view" } },
						{ "n", "<tab>", actions.select_next_entry, { desc = "Next file" } },
						{ "n", "<s-tab>", actions.select_prev_entry, { desc = "Previous file" } },
						{ "n", "s", actions.toggle_stage_entry, { desc = "Stage / unstage" } },
						{ "n", "X", actions.restore_entry, { desc = "Discard changes" } },
						{ "n", "R", actions.refresh_files, { desc = "Refresh" } },
					},
					file_history_panel = {
						{ "n", "<leader>gx", actions.close, { desc = "Close diff view" } },
						{ "n", "<tab>", actions.select_next_entry, { desc = "Next commit" } },
						{ "n", "<s-tab>", actions.select_prev_entry, { desc = "Previous commit" } },
						{ "n", "y", actions.copy_hash, { desc = "Copy commit SHA" } },
					},
				},
			}
		end,
	},

	-----------------------------------------------------------------------
	-- gitsigns — inline hunks, under <leader>gh
	-----------------------------------------------------------------------
	-- Moved from the old top-level <leader>h prefix so all git lives under
	-- <leader>g. ]c / [c hunk navigation is unchanged.
	{
		"lewis6991/gitsigns.nvim",
		event = { "BufReadPre", "BufNewFile" },
		opts = {
			signs = {
				add = { text = "▎" },
				change = { text = "▎" },
				delete = { text = "󰍵" },
				topdelete = { text = "󰍵" },
				changedelete = { text = "▎" },
				untracked = { text = "▎" },
			},
			signs_staged_enable = true,
			current_line_blame_opts = {
				delay = 300,
				virt_text_pos = "eol",
			},
			on_attach = function(bufnr)
				local gs = require("gitsigns")

				local function map(mode, l, r, desc)
					vim.keymap.set(mode, l, r, { buffer = bufnr, desc = desc })
				end

				-- Navigation. In diff mode fall through to vim's own ]c/[c so
				-- the keys keep working inside diffview and :Gvdiffsplit.
				map("n", "]c", function()
					if vim.wo.diff then
						vim.cmd.normal({ "]c", bang = true })
					else
						gs.nav_hunk("next")
					end
				end, "Next change")
				map("n", "[c", function()
					if vim.wo.diff then
						vim.cmd.normal({ "[c", bang = true })
					else
						gs.nav_hunk("prev")
					end
				end, "Previous change")

				-- Staging
				map("n", "<leader>ghs", gs.stage_hunk, "󰐕 Stage hunk")
				map("n", "<leader>ghr", gs.reset_hunk, "󰕌 Reset hunk")
				map("v", "<leader>ghs", function()
					gs.stage_hunk({ vim.fn.line("."), vim.fn.line("v") })
				end, "󰐕 Stage selected lines")
				map("v", "<leader>ghr", function()
					gs.reset_hunk({ vim.fn.line("."), vim.fn.line("v") })
				end, "󰕌 Reset selected lines")
				map("n", "<leader>ghS", gs.stage_buffer, "󰐕 Stage whole buffer")
				map("n", "<leader>ghR", gs.reset_buffer, "󰕌 Reset whole buffer")
				-- Was missing entirely: unstage the hunk you just staged.
				map("n", "<leader>ghu", gs.undo_stage_hunk, "󰕌 Undo stage hunk")

				-- Inspection
				map("n", "<leader>ghp", gs.preview_hunk, "󰈈 Preview hunk")
				map("n", "<leader>ghi", gs.preview_hunk_inline, "󰈈 Preview hunk inline")
				map("n", "<leader>ghb", function()
					gs.blame_line({ full = true })
				end, "󰋽 Blame line (full)")
				map("n", "<leader>ghB", gs.blame, "󰋽 Blame whole file")
				map("n", "<leader>ghd", gs.diffthis, "󰦓 Diff this")
				map("n", "<leader>ghD", function()
					gs.diffthis("~")
				end, "󰦓 Diff this (against HEAD~)")

				-- Bulk
				map("n", "<leader>ghq", gs.setqflist, "󰌧 Hunks → quickfix")
				map("n", "<leader>ghQ", function()
					gs.setqflist("all")
				end, "󰌧 All repo hunks → quickfix")

				-- Text object: operate on a hunk like any other motion (dih, yih)
				map({ "o", "x" }, "ih", gs.select_hunk, "Inner hunk")
			end,
		},
	},

	-----------------------------------------------------------------------
	-- fugitive — reduced to what nothing else does well
	-----------------------------------------------------------------------
	-- The old push/pull/stage-file/revert-file keymaps are gone: lazygit and
	-- gitsigns do those better. What remains is :Gvdiffsplit (the best 3-way
	-- conflict editor in nvim) and :GBrowse (open the current line on GitHub).
	{
		"tpope/vim-fugitive",
		cmd = { "Git", "Gvdiffsplit", "Gdiffsplit", "GBrowse", "Gread", "Gwrite" },
		dependencies = { "tpope/vim-rhubarb" }, -- :GBrowse support for GitHub
		keys = {
			{ "<leader>gv", "<cmd>Gvdiffsplit!<cr>", desc = "󰘬 3-way conflict split (fugitive)" },
			{ "<leader>gy", "<cmd>GBrowse<cr>", desc = "󰌹 Open in browser", mode = { "n", "v" } },
			{ "<leader>gB", "<cmd>Git blame<cr>", desc = "󰋽 Blame (fugitive)" },
		},
	},
}
