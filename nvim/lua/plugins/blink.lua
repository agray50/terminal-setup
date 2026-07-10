return {
	{
		"saghen/blink.cmp",
		dependencies = { "rafamadriz/friendly-snippets" },
		version = "1.*",
		---@module 'blink.cmp'
		---@type blink.cmp.Config
		opts = {
			keymap = {
				preset = "none",
				["<C-b>"] = { "show", "show_documentation", "hide_documentation" },
				["<C-e>"] = { "hide" },
				["<Tab>"] = { "select_next", "snippet_forward", "fallback" },
				["<S-Tab>"] = { "select_prev", "snippet_backward", "fallback" },
				["<CR>"] = { "accept", "fallback" },
				["<C-k>"] = { "scroll_documentation_up", "fallback" },
				["<C-j>"] = { "scroll_documentation_down", "fallback" },
			},

			appearance = {
				nerd_font_variant = "mono",
			},

			signature = { enabled = true },

			completion = {
				documentation = { auto_show = true },
				accept = { auto_brackets = { enabled = true } },
				keyword = { range = "full" },
			},

			sources = {
				default = { "lsp", "path", "snippets", "buffer" },
				providers = {
					lsp = {
						transform_items = function(ctx, items)
							if vim.bo[ctx.bufnr].filetype ~= "java" then
								return items
							end
							-- jdtls only ever proposes the corrupt "*" on-demand-import
							-- artifact (see eclipse-jdtls/eclipse.jdt.ls#353, #591) inside
							-- import/package statements. Legitimate Module-kind completions
							-- (package segments, module-info.java requires/exports) must
							-- keep working everywhere else -- including other Module-kind
							-- items in these same statements -- so gate on both the
							-- statement context and the item's own text, not kind alone.
							if not (ctx.line:match("^%s*import%s") or ctx.line:match("^%s*package%s")) then
								return items
							end
							local Module = require("blink.cmp.types").CompletionItemKind.Module
							return vim.tbl_filter(function(item)
								if item.kind ~= Module then
									return true
								end
								local text = item.insertText or item.label or ""
								return text ~= "*" and not text:match("%.%*$")
							end, items)
						end,
					},
					snippets = {
						opts = {
							-- Load custom snippets from nvim/snippets/ alongside friendly-snippets
							search_paths = { vim.fn.stdpath("config") .. "/snippets" },
						},
					},
				},
			},

			fuzzy = { implementation = "prefer_rust_with_warning" },
		},
		opts_extend = { "sources.default" },
	},
}
