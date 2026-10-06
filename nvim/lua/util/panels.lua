-- Tool-panel registry, backing <leader>qz ("close everything").
--
-- Replaces the previous <leader>Q implementation, which pcall'd five specific
-- plugin close functions and then walked every window against a hardcoded
-- filetype allowlist — so adding a plugin meant editing that logic. Here a
-- plugin is one table entry, and nothing else needs to change.

local M = {}

-- filetype -> how to close a window showing it.
--   true     : close the window directly
--   string   : run this Ex command instead (for plugins that need their own
--              teardown, e.g. releasing a tab page or stopping a session)
M.closers = {
	-- Pickers and lists
	["fzf"] = true,
	["trouble"] = "Trouble close",
	["qf"] = true,
	["help"] = true,
	["man"] = true,
	["checkhealth"] = true,
	["lspinfo"] = true,

	-- Trees and outlines
	["neo-tree"] = "Neotree close",
	["neo-tree-popup"] = true,
	["undotree"] = true,
	["diff"] = true,

	-- Git
	["fugitive"] = true,
	["fugitiveblame"] = true,
	["git"] = true,
	["gitcommit"] = true,
	["DiffviewFiles"] = "DiffviewClose",
	["DiffviewFileHistory"] = "DiffviewClose",

	-- DAP
	["dap-repl"] = true,
	["dapui_watches"] = true,
	["dapui_stacks"] = true,
	["dapui_breakpoints"] = true,
	["dapui_scopes"] = true,
	["dapui_console"] = true,

	-- Test
	["neotest-summary"] = true,
	["neotest-output"] = true,
	["neotest-output-panel"] = true,

	-- Database
	["dbui"] = "DBUIClose",
	["dbout"] = true,

	-- Misc
	["lazy"] = true,
	["mason"] = true,
	["notify"] = true,
	["query"] = true, -- :InspectTree
}

---Register (or override) a closer for a filetype. Lets a plugin spec declare
---its own panel without this file needing to know about it.
---@param ft string
---@param closer boolean|string
function M.register(ft, closer)
	M.closers[ft] = closer
end

---Close every registered tool panel, floating terminal and DAP UI.
---Leaves normal file buffers alone.
function M.close_all()
	-- Plugins with dedicated teardown that must run before windows are closed.
	pcall(function()
		require("dapui").close()
	end)
	pcall(function()
		require("neotest").summary.close()
	end)
	pcall(function()
		require("neotest").output_panel.close()
	end)
	pcall(function()
		require("util.float").close_all()
	end)
	pcall(function()
		require("mini.notify").clear()
	end)

	-- Ex-command closers run once each, not once per matching window, because
	-- commands like DiffviewClose already tear down all of their own windows.
	local ran = {}
	local windows = vim.api.nvim_list_wins()

	for _, win in ipairs(windows) do
		if vim.api.nvim_win_is_valid(win) then
			local buf = vim.api.nvim_win_get_buf(win)
			local ft = vim.bo[buf].filetype
			local closer = M.closers[ft]

			if type(closer) == "string" then
				if not ran[closer] then
					ran[closer] = true
					pcall(vim.cmd, closer)
				end
			elseif closer == true then
				-- Never close the last window — that would quit Neovim.
				if #vim.api.nvim_tabpage_list_wins(0) > 1 then
					pcall(vim.api.nvim_win_close, win, true)
				end
			end
		end
	end

	-- Clear search highlight and any lingering command-line message too, so one
	-- key really does get you back to a clean editor.
	vim.cmd("nohlsearch")
	vim.cmd("echo ''")
end

return M
