-- Database UI — vim-dadbod, under <leader>D.
--
-- Browse schemas and tables in a sidebar, write queries in a normal buffer
-- (with completion sourced from the live schema), and see results in a split.
--
-- CONNECTIONS are read from ~/.config/nvim-dbs.lua, which is deliberately
-- OUTSIDE this repo so connection strings with passwords are never committed.
-- Create it like this:
--
--     -- ~/.config/nvim-dbs.lua
--     return {
--       dev   = "postgres://user:pass@localhost:5432/myapp_dev",
--       local_pg = "postgres://postgres@localhost:5432/postgres",
--     }
--
-- Prefer a ~/.pgpass entry or a PG* environment variable over an inline
-- password where you can; dadbod expands $VARS in the URL.
-- Requires psql, which setup.sh installs via libpq / postgresql-client.

return {
	{
		"tpope/vim-dadbod",
		cmd = { "DB", "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" },
	},
	{
		"kristijanhusak/vim-dadbod-ui",
		dependencies = {
			{ "tpope/vim-dadbod", lazy = true },
			{ "kristijanhusak/vim-dadbod-completion", ft = { "sql", "mysql", "plsql" }, lazy = true },
		},
		cmd = { "DBUI", "DBUIToggle", "DBUIAddConnection", "DBUIFindBuffer" },
		keys = {
			{ "<leader>DD", "<cmd>DBUIToggle<cr>", desc = "󰆼 Toggle database UI" },
			{ "<leader>Df", "<cmd>DBUIFindBuffer<cr>", desc = "󰈞 Find DB buffer" },
			{ "<leader>Da", "<cmd>DBUIAddConnection<cr>", desc = "󰐕 Add DB connection" },
			{ "<leader>Dr", "<cmd>DBUIRenameBuffer<cr>", desc = "󰑕 Rename DB buffer" },
			{ "<leader>Dq", "<cmd>DBUILastQueryInfo<cr>", desc = "󰋼 Last query info" },
		},
		init = function()
			-- vim-dadbod-ui is a vimscript plugin configured through globals,
			-- so these must be set before it loads.
			vim.g.db_ui_use_nerd_fonts = 1
			vim.g.db_ui_show_database_icon = 1
			vim.g.db_ui_force_echo_notifications = 1
			vim.g.db_ui_win_position = "left"
			vim.g.db_ui_winwidth = 32
			-- Keep saved queries with the project rather than in the repo.
			vim.g.db_ui_save_location = vim.fn.stdpath("data") .. "/db_ui_queries"
			-- Execute on <leader>DS rather than the default <Leader>S, which
			-- would collide with the search group.
			vim.g.db_ui_execute_on_save = 0

			-- Load connections from outside the repo, if present.
			local conn_file = vim.fn.expand("~/.config/nvim-dbs.lua")
			if vim.fn.filereadable(conn_file) == 1 then
				local ok, dbs = pcall(dofile, conn_file)
				if ok and type(dbs) == "table" then
					vim.g.dbs = dbs
				else
					vim.notify("nvim-dbs.lua exists but did not return a table of connections", vim.log.levels.WARN)
				end
			end
		end,
		config = function()
			-- SQL buffers: run the query under the cursor, and get schema-aware
			-- completion. Buffer-local so these keys don't exist elsewhere.
			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("dadbod_sql", { clear = true }),
				pattern = { "sql", "mysql", "plsql" },
				callback = function(ev)
					vim.keymap.set(
						"n",
						"<leader>DS",
						"<Plug>(DBUI_ExecuteQuery)",
						{ buffer = ev.buf, desc = "󰐊 Execute query" }
					)
					vim.keymap.set(
						"v",
						"<leader>DS",
						"<Plug>(DBUI_ExecuteQuery)",
						{ buffer = ev.buf, desc = "󰐊 Execute selected query" }
					)
					vim.keymap.set(
						"n",
						"<leader>DW",
						"<Plug>(DBUI_SaveQuery)",
						{ buffer = ev.buf, desc = "󰆓 Save query" }
					)
					-- Completion comes from the connected database's real
					-- schema, so table and column names are checked rather
					-- than guessed.
					vim.bo[ev.buf].omnifunc = "vim_dadbod_completion#omni"
				end,
			})
		end,
	},
}
