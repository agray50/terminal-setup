-- Mason — installs and PINS every LSP server, formatter, linter and DAP adapter.
--
-- The registry pin is the single most important stability setting in this
-- config. mason-registry publishes many times a day; unpinned, every tool
-- Mason manages silently jumps to its newest version, which is the usual cause
-- of "it worked yesterday". The pin lives in versions.lock and is written to
-- lua/mason-pin.lua by setup.sh, so there is exactly one source of truth.
--
-- To move the pin:  ./setup.sh --update  (then review `git diff versions.lock`)

local pin = require("mason-pin")

return {
	{
		"mason-org/mason.nvim",
		-- Lazy: nothing needs the Mason UI at startup. mason-lspconfig below
		-- depends on it, so it still loads in time to enable servers.
		cmd = { "Mason", "MasonInstall", "MasonUninstall", "MasonUpdate", "MasonLog" },
		keys = {
			{ "<leader>cm", "<cmd>Mason<cr>", desc = "󰏖 Mason (manage LSP/tools)" },
		},
		opts = {
			registries = { pin.registry },
			ui = {
				border = "rounded",
				icons = {
					package_installed = "✓",
					package_pending = "➜",
					package_uninstalled = "✗",
				},
			},
			-- Install serially. Parallel installs of heavy packages (jdtls,
			-- rust-analyzer) on a cold machine can exhaust file handles.
			max_concurrent_installers = 4,
		},
	},

	{
		"mason-org/mason-lspconfig.nvim",
		dependencies = {
			{ "mason-org/mason.nvim" },
			"neovim/nvim-lspconfig",
		},
		opts = {
			-- mason-lspconfig v2 calls vim.lsp.enable() for each of these, so
			-- servers with no custom config need no entry in lsp-config.lua.
			ensure_installed = {
				-- JavaScript / TypeScript / React
				"vtsls", -- replaces ts_ls: inlay hints, better monorepo
				-- resolution, move-file-and-update-imports
				"eslint", -- diagnostics + `eslint --fix` code actions
				-- Web / styling
				"html",
				"cssls",
				"tailwindcss",
				"emmet_language_server",
				-- Data / config
				"jsonls",
				"yamlls",
				"taplo", -- TOML
				"graphql",
				-- Infrastructure
				"terraformls",
				"helm_ls",
				"dockerls",
				"docker_compose_language_service",
				-- Languages
				"basedpyright", -- replaces pyright: maintained fork, better inference
				"ruff", -- Python lint + fix, replaces pylint entirely
				"gopls",
				"jdtls", -- driven by nvim-jdtls (see plugins/jdtls.lua)
				"rust_analyzer", -- configured by rustaceanvim
				"lua_ls",
				"bashls",
				"marksman", -- Markdown
				"sqls", -- SQL, pairs with the dadbod UI
			},
			-- mason-lspconfig enables an LSP client for every installed Mason
			-- package it can map to an lspconfig name, which needs three
			-- exclusions:
			--   jdtls / rust_analyzer — started and configured by nvim-jdtls
			--     and rustaceanvim; a second unconfigured client attaching to
			--     the same buffer breaks both.
			--   stylua — mason-lspconfig maps the stylua *formatter* to an
			--     "lspconfig name", so it was starting a pointless LSP client
			--     on every Lua buffer. conform runs stylua as a formatter.
			automatic_enable = {
				exclude = { "jdtls", "rust_analyzer", "stylua" },
			},
		},
	},

	{
		"WhoIsSethDaniel/mason-tool-installer.nvim",
		dependencies = { "mason-org/mason.nvim" },
		-- VeryLazy, not startup: tool installation has no bearing on the first
		-- frame, and this keeps it off the startup path entirely.
		event = "VeryLazy",
		opts = {
			run_on_start = true,
			start_delay = 2000,
			debounce_hours = 24,
			-- Disable the built-in mason-nvim-dap cross-reference: DAP adapters
			-- are installed via mason-nvim-dap's own ensure_installed (see
			-- dap.lua), so this integration would only serve to force the whole
			-- nvim-dap stack to load just to resolve adapter names.
			integrations = {
				["mason-nvim-dap"] = false,
			},
			ensure_installed = {
				-- Formatters
				"prettierd", -- daemon; markedly faster than prettier on save
				"prettier", -- fallback when prettierd's daemon is unavailable
				"stylua",
				"goimports",
				"gofumpt",
				"shfmt",
				"google-java-format",
				"sql-formatter",
				-- (Python formatting is ruff_format, via the ruff LSP above;
				--  Rust is rustfmt, shipped with the toolchain; Terraform is
				--  terraform fmt, shipped with the terraform binary.)

				-- Linters
				"yamllint",
				"golangci-lint",
				"shellcheck",
				"tflint", -- Terraform correctness beyond `validate`
				"hadolint", -- Dockerfile
				"markdownlint-cli2",
				"checkstyle", -- gated on a project config; see nvim-lint.lua

				-- Debug adapters for Java, which mason-nvim-dap does not cover.
				-- nvim-jdtls wires these into jdtls's bundles.
				"java-debug-adapter",
				"java-test",
			},
		},
	},
}
