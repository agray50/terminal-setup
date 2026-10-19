-- On/off switches that report their new state, so you're never left guessing
-- which way a toggle just went. Shared by the <leader>u keys in core/keymaps.lua
-- and the format-on-save toggles in plugins/conform.lua.

local M = {}

---Build a keymap callback that flips a boolean and notifies the result.
---@param desc string shown as "<desc>: on|off"
---@param get fun(): boolean
---@param set fun(value: boolean)
function M.new(desc, get, set)
	return function()
		local new = not get()
		set(new)
		vim.notify((new and "󰔡 " or "󰔢 ") .. desc .. ": " .. (new and "on" or "off"))
	end
end

return M
