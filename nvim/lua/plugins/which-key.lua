-- which-key — the discoverability layer.
--
-- Previously only eight bare group labels were registered, so most of the
-- config was undiscoverable and you had to remember it or read the README.
-- With every group described and iconed, pressing <leader> alone is a complete
-- menu — which covers most of what a command palette is actually for.

return {
	"folke/which-key.nvim",
	event = "VeryLazy",
	keys = {
		{
			"<leader>?",
			function()
				require("which-key").show({ global = false })
			end,
			desc = "󰌌 Buffer-local keymaps",
		},
		{
			"<leader>fK",
			function()
				require("which-key").show({ global = true })
			end,
			desc = "󰌌 All keymaps (which-key)",
		},
	},
	opts = {
		preset = "modern",
		-- Short enough to feel instant when you've paused, long enough not to
		-- flash on every leader sequence you type at speed.
		delay = function(ctx)
			return ctx.plugin and 0 or 300
		end,
		win = { border = "rounded" },
		spec = {
			-- Groups, in the order they read in the README.
			{ "<leader>b", group = "buffer", icon = { icon = "󰓩 ", color = "cyan" } },
			{ "<leader>c", group = "code / LSP", icon = { icon = "󰅯 ", color = "green" } },
			{ "<leader>d", group = "debug", icon = { icon = "󰃤 ", color = "red" } },
			{ "<leader>D", group = "database", icon = { icon = "󰆼 ", color = "blue" } },
			{ "<leader>f", group = "find", icon = { icon = "󰍉 ", color = "yellow" } },
			{ "<leader>g", group = "git", icon = { icon = "󰊢 ", color = "orange" } },
			{ "<leader>gh", group = "git hunk", icon = { icon = "󰊢 ", color = "orange" } },
			{ "<leader>q", group = "quit / close", icon = { icon = "󰅖 ", color = "red" } },
			{ "<leader>s", group = "search / replace", icon = { icon = "󰛔 ", color = "yellow" } },
			{ "<leader>t", group = "test", icon = { icon = "󰙨 ", color = "green" } },
			{ "<leader>u", group = "UI toggles", icon = { icon = "󰔡 ", color = "purple" } },
			{ "<leader>w", group = "window", icon = { icon = "󰖮 ", color = "cyan" } },
			{ "<leader>x", group = "diagnostics / lists", icon = { icon = "󰅚 ", color = "red" } },

			-- Standalone leader keys, so the top-level menu has no bare entries.
			{ "<leader><space>", desc = "󰈞 Find files" },
			{ "<leader>/", desc = "󰱼 Grep project" },
			{ "<leader>,", desc = "󰓩 Buffers" },
			{ "<leader>?", desc = "󰌌 Buffer-local keymaps" },
			{ "<leader>y", desc = "Yank to system clipboard" },
			{ "<leader>Y", desc = "Yank line to system clipboard" },
			{ "<leader>p", desc = "Paste without yanking replaced" },
			{ "<leader>P", desc = "Paste from system clipboard" },
			{ "<leader>X", desc = "Delete without yanking" },

			-- Document the non-leader keys that aren't self-evident. These
			-- appear when you press the prefix, so ] and [ become discoverable
			-- instead of needing to be memorised.
			{ "g", group = "goto / LSP" },
			{ "gs", group = "surround" },
			{ "]", group = "next" },
			{ "[", group = "previous" },
			{ "z", group = "fold" },
			{ "<C-w>", group = "window" },
		},
		-- Keys that would otherwise clutter the popup with vim internals.
		filter = function(mapping)
			return mapping.desc ~= nil and mapping.desc ~= ""
		end,
		icons = {
			rules = false, -- icons come from the specs above, not auto-guessed
			separator = "󰅂",
		},
	},
}
