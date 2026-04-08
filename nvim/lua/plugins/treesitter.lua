return {
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		lazy = false,
		build = ":TSUpdate",
		config = function()
			require("nvim-treesitter").setup({})

			-- Only attempt parser installation if tree-sitter CLI is available
			if vim.fn.executable("tree-sitter") == 1 then
				require("nvim-treesitter").install({
					"bash", "c", "diff", "go", "html", "javascript", "jsdoc",
					"json", "jsonc", "lua", "luadoc", "luap", "markdown",
					"markdown_inline", "printf", "python", "query", "regex",
					"toml", "tsx", "typescript", "vim", "vimdoc", "xml", "yaml",
				})
			else
				vim.notify("nvim-treesitter: tree-sitter CLI not found — run 'brew install tree-sitter' (macOS) or 'cargo install tree-sitter-cli' (Linux)", vim.log.levels.WARN)
			end

			-- Enable treesitter highlighting, indentation, and folding per-buffer
			vim.api.nvim_create_autocmd("FileType", {
				callback = function(ev)
					pcall(vim.treesitter.start)
					vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
					vim.wo[0][0].foldmethod = "expr"
					vim.wo[0][0].foldexpr = "v:lua.vim.treesitter.foldexpr()"
				end,
			})
		end,
	},
}
