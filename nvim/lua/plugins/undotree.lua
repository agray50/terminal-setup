-- Built-in undotree (Neovim 0.12+) — no external plugin needed
local loaded = false
vim.keymap.set("n", "<leader>u", function()
	if not loaded then
		vim.cmd("packadd nvim.undotree")
		loaded = true
	end
	vim.cmd("Undotree")
end, { desc = "Toggle undotree" })
return {}
