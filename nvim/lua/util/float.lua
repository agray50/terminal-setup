-- Floating-terminal helper.
--
-- One implementation shared by lazygit (<leader>gg), the scratch shell (<C-\>)
-- and k9s (<leader>uk), so all three behave identically: same border, same size,
-- same close keys, and each reuses its own persistent buffer so scrollback and
-- shell state survive being hidden and reopened.
--
-- This exists instead of a plugin (toggleterm / lazygit.nvim) because the whole
-- requirement is ~80 lines of vim.api, and a plugin here would be one more
-- dependency to pin and one more thing to break on a Neovim upgrade.

local M = {}

-- Terminals are keyed by name so each one is a singleton.
---@type table<string, { buf: integer?, win: integer?, job: integer? }>
local terms = {}

local function dims(scale)
	local width = math.floor(vim.o.columns * scale)
	local height = math.floor(vim.o.lines * scale)
	return {
		width = width,
		height = height,
		row = math.floor((vim.o.lines - height) / 2),
		col = math.floor((vim.o.columns - width) / 2),
	}
end

---Is this terminal's window currently visible?
local function is_open(t)
	return t.win ~= nil and vim.api.nvim_win_is_valid(t.win)
end

---Hide (but do not kill) the terminal window.
local function hide(t)
	if is_open(t) then
		vim.api.nvim_win_close(t.win, false)
	end
	t.win = nil
end

---Open or focus a named floating terminal.
---@param opts { name: string, cmd: string|string[], scale: number?, title: string?, on_exit: fun()? }
function M.toggle(opts)
	local name = opts.name
	local scale = opts.scale or 0.9
	local t = terms[name]

	if t and is_open(t) then
		hide(t)
		return
	end

	t = t or {}
	terms[name] = t

	local d = dims(scale)

	-- Reuse the existing terminal buffer if its job is still alive, so toggling
	-- lazygit off and on again returns to the same state rather than restarting.
	local reuse = t.buf ~= nil
		and vim.api.nvim_buf_is_valid(t.buf)
		and t.job ~= nil
		and vim.fn.jobwait({ t.job }, 0)[1] == -1

	if not reuse then
		t.buf = vim.api.nvim_create_buf(false, true)
		t.job = nil
	end

	t.win = vim.api.nvim_open_win(t.buf, true, {
		relative = "editor",
		width = d.width,
		height = d.height,
		row = d.row,
		col = d.col,
		style = "minimal",
		border = "rounded",
		title = opts.title and (" " .. opts.title .. " ") or nil,
		title_pos = opts.title and "center" or nil,
	})

	vim.wo[t.win].winhighlight = "NormalFloat:NormalFloat,FloatBorder:FloatBorder"

	if not reuse then
		-- vim.fn.jobstart in a terminal buffer requires the buffer be current.
		t.job = vim.fn.jobstart(opts.cmd, {
			term = true,
			on_exit = function()
				-- The tool exited (e.g. you quit lazygit) — tear the float down
				-- rather than leaving a dead shell on screen.
				vim.schedule(function()
					local cur = terms[name]
					if cur then
						hide(cur)
						if cur.buf and vim.api.nvim_buf_is_valid(cur.buf) then
							vim.api.nvim_buf_delete(cur.buf, { force = true })
						end
						terms[name] = nil
					end
					if opts.on_exit then
						opts.on_exit()
					end
				end)
			end,
		})

		-- q closes the float for read-only viewers; interactive TUIs like
		-- lazygit need every key, so only bind it when asked.
		if opts.close_on_q then
			vim.keymap.set("n", "q", function()
				M.toggle({ name = name, cmd = opts.cmd })
			end, { buffer = t.buf, nowait = true, desc = "Close " .. name })
		end
	end

	vim.cmd.startinsert()
end

---Close a named terminal if it is open. Used by the "close all panels" keymap.
function M.close(name)
	local t = terms[name]
	if t then
		hide(t)
	end
end

---Close every open floating terminal.
function M.close_all()
	for name, _ in pairs(terms) do
		M.close(name)
	end
end

---True if any float managed here is currently visible.
function M.any_open()
	for _, t in pairs(terms) do
		if is_open(t) then
			return true
		end
	end
	return false
end

return M
