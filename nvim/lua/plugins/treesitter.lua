-- Treesitter (main branch) — highlighting, indentation, folding, text objects.

return {
	{
		"nvim-treesitter/nvim-treesitter",
		branch = "main",
		lazy = false,
		build = ":TSUpdate",
		config = function()
			require("nvim-treesitter").setup({})

			-- Parsers for every language in active use. The previous list was
			-- missing java, terraform/hcl, css, dockerfile and sql despite all
			-- of them being core, and the git family — which is what makes an
			-- interactive rebase todo-list readable.
			local wanted = {
				-- Core / editor
				"bash",
				"c",
				"diff",
				"lua",
				"luadoc",
				"luap",
				"printf",
				"query",
				"regex",
				"vim",
				"vimdoc",
				"xml",
				-- Git — gitcommit and git_rebase matter when fixing a rebase
				"git_config",
				"git_rebase",
				"gitattributes",
				"gitcommit",
				"gitignore",
				-- JS / TS / React
				"javascript",
				"jsdoc",
				"typescript",
				"tsx",
				-- Web / styling
				"html",
				"css",
				"scss",
				-- Data / config
				"json",
				"json5",
				-- NB: no "jsonc" — it has no parser of its own and
				-- nvim-treesitter warns on every startup if you ask for it.
				-- jsonc buffers use the json parser.
				"yaml",
				"toml",
				-- Python / Go / Java / Rust
				"python",
				"go",
				"gomod",
				"gosum",
				"gowork",
				"java",
				"rust",
				-- Infrastructure
				"terraform",
				"hcl",
				"dockerfile",
				"helm",
				"gotmpl",
				"make",
				-- Other
				"sql",
				"graphql",
				"markdown",
				"markdown_inline",
			}

			-- Only attempt installation if the tree-sitter CLI is available;
			-- the main branch compiles parsers with it.
			if vim.fn.executable("tree-sitter") == 1 then
				-- Everything here is wrapped in pcall. nvim-treesitter's main
				-- branch uses assert() when reading a parser's revision
				-- metadata, so a single parser left half-installed (an
				-- interrupted install, a killed nvim) turns into a hard Lua
				-- traceback on EVERY startup — which is exactly the class of
				-- "it randomly broke" this config used to produce. Degrading to
				-- a warning keeps the editor usable and says how to repair it.
				local ok, installed_list = pcall(function()
					return require("nvim-treesitter").get_installed("parsers")
				end)

				if not ok then
					vim.notify(
						"nvim-treesitter: could not read installed parsers — parser state may be "
							.. "corrupt. Repair with :TSInstall! <lang>, or see the README's "
							.. "troubleshooting section.",
						vim.log.levels.WARN
					)
					installed_list = {}
				end

				local installed = {}
				for _, parser in ipairs(installed_list) do
					installed[parser] = true
				end

				local missing = {}
				for _, parser in ipairs(wanted) do
					if not installed[parser] then
						table.insert(missing, parser)
					end
				end

				-- Skip the installer entirely when everything is already present
				if #missing > 0 then
					local installed_ok, err = pcall(function()
						require("nvim-treesitter").install(missing)
					end)
					if not installed_ok then
						vim.notify(
							"nvim-treesitter: failed to install parsers (" .. tostring(err) .. ")",
							vim.log.levels.WARN
						)
					end
				end
			else
				vim.notify(
					"nvim-treesitter: tree-sitter CLI not found in PATH — re-run ./setup.sh",
					vim.log.levels.WARN
				)
			end

			-- Enable highlighting, indentation and folding per buffer.
			--
			-- Previously this ran unconditionally for EVERY filetype, which set
			-- indentexpr and foldexpr even where no parser exists — breaking
			-- indentation in those buffers (the treesitter indentexpr returns
			-- -1 with no parser, so `==` and `o` stopped working). Now each
			-- buffer is checked first.
			vim.api.nvim_create_autocmd("FileType", {
				group = vim.api.nvim_create_augroup("treesitter_attach", { clear = true }),
				callback = function(ev)
					-- Large files opt out entirely (see core/autocmds.lua).
					if vim.b[ev.buf].large_file then
						return
					end

					local lang = vim.treesitter.language.get_lang(vim.bo[ev.buf].filetype)
					if not lang then
						return
					end

					-- language.add() returns false when the parser is not
					-- installed, rather than throwing.
					local ok = pcall(vim.treesitter.language.add, lang)
					if not ok then
						return
					end

					if not pcall(vim.treesitter.start, ev.buf, lang) then
						return
					end

					-- Only now that a parser is confirmed attached is it safe to
					-- delegate indent and fold expressions to treesitter.
					vim.bo[ev.buf].indentexpr = "v:lua.require'nvim-treesitter'.indentexpr()"
					vim.wo[0][0].foldmethod = "expr"
					vim.wo[0][0].foldexpr = "v:lua.vim.treesitter.foldexpr()"
				end,
			})

			-- Inspect the tree under the cursor — the fastest way to work out
			-- why a highlight or indent rule is behaving oddly.
			vim.keymap.set("n", "<leader>ui", "<cmd>InspectTree<cr>", { desc = "󰙅 Inspect treesitter tree" })
			vim.keymap.set("n", "<leader>uI", "<cmd>Inspect<cr>", { desc = "󰈈 Inspect highlight under cursor" })
		end,
	},

	-- Text objects: operate on syntax nodes rather than lines.
	-- `vaf` selects a whole function, `cif` changes its body, `]f` jumps to the
	-- next one. This is most of what makes treesitter worth having day to day.
	{
		"nvim-treesitter/nvim-treesitter-textobjects",
		branch = "main",
		event = { "BufReadPost", "BufNewFile" },
		dependencies = { "nvim-treesitter/nvim-treesitter" },
		config = function()
			require("nvim-treesitter-textobjects").setup({
				select = { lookahead = true },
				move = { set_jumps = true },
			})

			local select = require("nvim-treesitter-textobjects.select")
			local move = require("nvim-treesitter-textobjects.move")

			-- Selections: a = "around" (includes signature/braces), i = "inner".
			local objects = {
				f = { "@function.outer", "@function.inner", "function" },
				c = { "@class.outer", "@class.inner", "class" },
				a = { "@parameter.outer", "@parameter.inner", "parameter" },
				o = { "@conditional.outer", "@conditional.inner", "conditional" },
				l = { "@loop.outer", "@loop.inner", "loop" },
				b = { "@block.outer", "@block.inner", "block" },
				["="] = { "@assignment.outer", "@assignment.inner", "assignment" },
			}

			for key, spec in pairs(objects) do
				local outer, inner, name = spec[1], spec[2], spec[3]
				vim.keymap.set({ "x", "o" }, "a" .. key, function()
					select.select_textobject(outer, "textobjects")
				end, { desc = "Around " .. name })
				vim.keymap.set({ "x", "o" }, "i" .. key, function()
					select.select_textobject(inner, "textobjects")
				end, { desc = "Inner " .. name })
			end

			-- Motions. ]f / [f are the ones used constantly: jump function to
			-- function without reading the file.
			local motions = {
				{ "]f", "@function.outer", "next_start", "Next function" },
				{ "[f", "@function.outer", "previous_start", "Previous function" },
				{ "]F", "@function.outer", "next_end", "Next function end" },
				{ "[F", "@function.outer", "previous_end", "Previous function end" },
				{ "]c", "@class.outer", "next_start", "Next class" },
				{ "[c", "@class.outer", "previous_start", "Previous class" },
				{ "]a", "@parameter.inner", "next_start", "Next parameter" },
				{ "[a", "@parameter.inner", "previous_start", "Previous parameter" },
			}

			for _, m in ipairs(motions) do
				local key, query, direction, desc = m[1], m[2], m[3], m[4]
				-- ]c / [c are gitsigns hunk navigation in a buffer with git
				-- changes; gitsigns registers those per-buffer, so it wins
				-- there and these apply elsewhere. Classes are rarer than
				-- hunks, so that precedence is the right way round.
				if key ~= "]c" and key ~= "[c" then
					vim.keymap.set({ "n", "x", "o" }, key, function()
						move["goto_" .. direction](query, "textobjects")
					end, { desc = desc })
				end
			end

			-- Swap a parameter left or right — reordering arguments without
			-- retyping them.
			local swap = require("nvim-treesitter-textobjects.swap")
			vim.keymap.set("n", "<leader>cs", function()
				swap.swap_next("@parameter.inner")
			end, { desc = "󰓡 Swap parameter with next" })
			vim.keymap.set("n", "<leader>cS", function()
				swap.swap_previous("@parameter.inner")
			end, { desc = "󰓡 Swap parameter with previous" })
		end,
	},
}
