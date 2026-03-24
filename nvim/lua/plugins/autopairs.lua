return {
	--- @module 'blink.pairs'
	--- @type blink.pairs.Config
	"saghen/blink.pairs",
	version = "*",
	lazy = false,
	dependencies = { "saghen/blink.download" },
	opts = {
		mappings = {
			wrap = {
				["<C-b>"] = nil,
				["<C-S-b>"] = nil,
			},
		},
	},
}
