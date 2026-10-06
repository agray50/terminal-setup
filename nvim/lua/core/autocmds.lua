-- Autocommands.

local function augroup(name)
	return vim.api.nvim_create_augroup("core_" .. name, { clear = true })
end

-- Briefly highlight what was just yanked — confirms the motion did what you meant.
vim.api.nvim_create_autocmd("TextYankPost", {
	group = augroup("highlight_yank"),
	callback = function()
		vim.hl.on_yank({ higroup = "IncSearch", timeout = 150 })
	end,
})

-- Return to the last cursor position when reopening a file, except for commit
-- messages (where you always want to start at the top).
vim.api.nvim_create_autocmd("BufReadPost", {
	group = augroup("last_location"),
	callback = function(ev)
		local exclude = { "gitcommit", "gitrebase", "commit", "rebase" }
		if vim.tbl_contains(exclude, vim.bo[ev.buf].filetype) then
			return
		end
		local mark = vim.api.nvim_buf_get_mark(ev.buf, '"')
		local line_count = vim.api.nvim_buf_line_count(ev.buf)
		if mark[1] > 0 and mark[1] <= line_count then
			pcall(vim.api.nvim_win_set_cursor, 0, mark)
			pcall(vim.cmd, "normal! zz")
		end
	end,
})

-- Close throwaway/tool windows with plain `q`, the way help already works.
-- Panels that need their own teardown are handled by util/panels.lua instead.
vim.api.nvim_create_autocmd("FileType", {
	group = augroup("close_with_q"),
	pattern = {
		"help",
		"man",
		"qf",
		"lspinfo",
		"checkhealth",
		"notify",
		"query",
		"startuptime",
		"neotest-output",
		"neotest-summary",
		"neotest-output-panel",
		"dbout",
		"fugitiveblame",
		"git",
	},
	callback = function(ev)
		vim.bo[ev.buf].buflisted = false
		vim.keymap.set("n", "q", "<cmd>close<cr>", {
			buffer = ev.buf,
			silent = true,
			nowait = true,
			desc = "Close window",
		})
	end,
})

-- Create missing parent directories when writing a new file, instead of
-- failing with E212 after you've already typed the content.
vim.api.nvim_create_autocmd("BufWritePre", {
	group = augroup("auto_mkdir"),
	callback = function(ev)
		if ev.match:match("^%w%w+://") then
			return -- not a real path (oil://, fugitive://, …)
		end
		local dir = vim.fn.fnamemodify(vim.uv.fs_realpath(ev.match) or ev.match, ":p:h")
		if vim.fn.isdirectory(dir) == 0 then
			vim.fn.mkdir(dir, "p")
		end
	end,
})

-- Strip trailing whitespace on save, but only on lines you actually touched is
-- not possible cheaply, so: only for filetypes where it is unambiguously noise.
-- Markdown is excluded because two trailing spaces is a hard line break.
vim.api.nvim_create_autocmd("BufWritePre", {
	group = augroup("trim_whitespace"),
	pattern = {
		"*.lua",
		"*.sh",
		"*.bash",
		"*.zsh",
		"*.py",
		"*.go",
		"*.java",
		"*.ts",
		"*.tsx",
		"*.js",
		"*.jsx",
		"*.tf",
		"*.hcl",
		"*.yaml",
		"*.yml",
		"*.json",
		"*.css",
		"*.scss",
		"*.html",
		"*.sql",
	},
	callback = function()
		-- conform.nvim formats most of these; this catches the filetypes with
		-- no formatter configured and runs before format_on_save either way.
		local view = vim.fn.winsaveview()
		pcall(vim.cmd, [[keeppatterns %s/\s\+$//e]])
		vim.fn.winrestview(view)
	end,
})

-- Resize splits proportionally when the terminal window changes size, so a
-- tmux pane resize doesn't leave a 3-line window behind.
vim.api.nvim_create_autocmd("VimResized", {
	group = augroup("resize_splits"),
	callback = function()
		local current_tab = vim.fn.tabpagenr()
		vim.cmd("tabdo wincmd =")
		vim.cmd("tabnext " .. current_tab)
	end,
})

-- Treat some filetypes as prose: wrap and spell-check them.
vim.api.nvim_create_autocmd("FileType", {
	group = augroup("prose"),
	pattern = { "gitcommit", "markdown", "text" },
	callback = function()
		vim.opt_local.wrap = true
		vim.opt_local.spell = true
		vim.opt_local.linebreak = true
	end,
})

-- Terminal buffers: no line numbers or sign column, and no spell check.
vim.api.nvim_create_autocmd("TermOpen", {
	group = augroup("terminal"),
	callback = function()
		vim.opt_local.number = false
		vim.opt_local.relativenumber = false
		vim.opt_local.signcolumn = "no"
		vim.opt_local.spell = false
		vim.opt_local.scrolloff = 0
	end,
})

-- Very large files: turn off the expensive machinery rather than hanging. A
-- minified bundle or a 50MB log should open instantly and read-only-ish.
vim.api.nvim_create_autocmd("BufReadPre", {
	group = augroup("large_file"),
	callback = function(ev)
		local max_bytes = 1024 * 1024 * 2 -- 2MB
		local ok, stats = pcall(vim.uv.fs_stat, vim.api.nvim_buf_get_name(ev.buf))
		if not ok or not stats or stats.size <= max_bytes then
			return
		end
		vim.b[ev.buf].large_file = true
		vim.opt_local.foldmethod = "manual"
		vim.opt_local.spell = false
		vim.opt_local.swapfile = false
		vim.opt_local.undofile = false
		vim.opt_local.list = false
		vim.schedule(function()
			if vim.api.nvim_buf_is_valid(ev.buf) then
				vim.bo[ev.buf].syntax = ""
				pcall(vim.treesitter.stop, ev.buf)
				vim.diagnostic.enable(false, { bufnr = ev.buf })
			end
		end)
		vim.notify(
			("Large file (%.1fMB): treesitter, diagnostics and undo disabled"):format(stats.size / 1024 / 1024),
			vim.log.levels.WARN
		)
	end,
})

-- Helm chart templates are Go templates, not YAML. Without this they are parsed
-- as YAML and every {{ }} block becomes a syntax error — which is one of the
-- "random errors" this config used to produce on a Helm repo.
-- Filetype registrations.
--
-- Several language servers declare compound filetypes that Neovim has no
-- extension mapping for (yaml.docker-compose, terraform-vars, yaml.helm-values,
-- …). Without these, the right server never attaches to the right file — and
-- :checkhealth reports each one as an "Unknown filetype" warning.
vim.filetype.add({
	extension = {
		-- terraform-ls expects .tfvars to be `terraform-vars`, not `terraform`;
		-- the variable-definition schema is different from the config schema.
		tfvars = "terraform-vars",
		tf = "terraform",
		hcl = "hcl",
		mdx = "markdown.mdx",
		gql = "graphql",
		graphql = "graphql",
	},
	filename = {
		-- docker-compose: the compose language server declares this filetype and
		-- provides schema-aware completion for service definitions.
		["docker-compose.yml"] = "yaml.docker-compose",
		["docker-compose.yaml"] = "yaml.docker-compose",
		["compose.yml"] = "yaml.docker-compose",
		["compose.yaml"] = "yaml.docker-compose",
		["docker-bake.hcl"] = "hcl.docker-bake",
		[".gitlab-ci.yml"] = "yaml.gitlab",
		["Chart.yaml"] = "yaml",
		["Chart.lock"] = "yaml",
	},
	pattern = {
		-- Helm chart templates are Go templates, not YAML. Without this they
		-- are parsed as YAML and every {{ }} block becomes a syntax error —
		-- one of the "random errors" this config used to produce on a Helm repo.
		[".*/templates/.*%.tpl"] = "helm",
		[".*/templates/.*%.ya?ml"] = "helm",
		[".*/helmfile.*%.ya?ml"] = "helm",
		-- values.yaml gets its own filetype so helm-ls can offer completion
		-- against the chart's own values schema.
		[".*/values.*%.ya?ml"] = "yaml.helm-values",
		-- GitHub Actions workflows — schemastore validates these via yamlls.
		[".*/%.github/workflows/.*%.ya?ml"] = "yaml",
		-- Kubernetes manifests commonly live here; plain yaml + schemastore.
		[".*/k8s/.*%.ya?ml"] = "yaml",
	},
})
