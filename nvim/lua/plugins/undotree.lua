-- Built-in undotree (Neovim 0.12+) — no external plugin needed
vim.cmd("packadd nvim.undotree")
vim.keymap.set("n", "<leader>u", "<cmd>Undotree<cr>", { desc = "Toggle undotree" })
return {}
