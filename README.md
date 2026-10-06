# terminal-setup

Developer environment for macOS and Linux: zsh, Neovim, tmux, and a pinned set of CLI tools.

**Every version is pinned.** A normal `./setup.sh` run reads only `versions.lock` and resolves
nothing from the network, so the same commit of this repo always produces the same environment.
Upgrades are a deliberate, reviewable step — see [Updating](#updating).

---

## Contents

- [Quick start](#quick-start) · [Updating](#updating) · [Troubleshooting](#troubleshooting)
- [What's installed](#whats-installed)
- [Neovim](#neovim) — [keybindings](#keybindings), [languages](#language-support), [database](#database)
- [zsh](#zsh) · [tmux](#tmux) · [git](#git)

---

## Quick start

### Prerequisites

Needs `git`, `curl` and `perl`. `make` is optional (only for building Python via pyenv).

**macOS** — Homebrew is installed automatically if missing:
```bash
xcode-select --install
```

**Linux (Debian/Ubuntu)**:
```bash
sudo apt-get install -y git curl perl build-essential
```

**Linux (Fedora/RHEL)**:
```bash
sudo dnf install -y git curl perl make gcc
```

### Install

```bash
git clone <repo-url> ~/git/terminal-setup
cd ~/git/terminal-setup
./setup.sh
```

Idempotent — safe to run repeatedly. It installs pinned binaries, symlinks the Neovim and tmux
configs, includes the shared git config, and restores Neovim plugins from `lazy-lock.json`.

```bash
./setup.sh --dry-run   # show what would change, change nothing
./setup.sh --check     # installed vs. pinned
./setup.sh --update    # re-resolve latest versions into versions.lock, install nothing
```

### After installing

1. **Reload your shell**: `source ~/.zshrc`
2. **Install a Nerd Font** and set it in your terminal — required for all icons.
   [JetBrainsMono Nerd Font](https://github.com/ryanoasis/nerd-fonts) recommended.
3. **Install the Catppuccin theme** for your terminal:
   [iTerm2](https://github.com/catppuccin/iterm) ·
   [GNOME](https://github.com/catppuccin/gnome-terminal) ·
   [Alacritty](https://github.com/catppuccin/alacritty)
4. **Install tmux plugins**: open tmux, press `Ctrl-s` then `I`
5. **Install language runtimes** (per-project, so deliberately not pinned globally):
   ```bash
   nvm install --lts && nvm use --lts
   pyenv install 3.13.1 && pyenv global 3.13.1
   goenv install 1.24.0 && goenv global 1.24.0
   sdk install java
   tfenv install latest && tfenv use latest
   ```
6. **Set your git identity** (kept out of this repo):
   ```bash
   git config --global user.name "Your Name"
   git config --global user.email you@example.com
   ```

---

## Updating

Nothing updates on its own. Neovim's update checker is off, SDKMAN's self-update is off, and
every tool is pinned. To move forward:

```bash
./setup.sh --update       # rewrites versions.lock; installs NOTHING
git diff versions.lock    # review exactly what moved
./setup.sh                # apply
```

If something breaks, roll back:

```bash
git checkout versions.lock && ./setup.sh
```

A `<KEY>_CONSTRAINT` entry in `versions.lock` pins a tool to a version *series*, so `--update`
can never cross a breaking major. goenv uses this: 3.x is a Go rewrite that dropped the
`bin/goenv` shell implementation this setup integrates with, so `GOENV_VERSION_CONSTRAINT=2.`
keeps it on the 2.x line. Without it, an update silently replaced goenv with something that had
no `goenv` executable at all.

Three things are pinned separately, by design:

| What | Pinned in | Update with |
|---|---|---|
| CLI tools, Neovim, zsh/tmux plugins, version managers | `versions.lock` | `./setup.sh --update` |
| Neovim plugins | `nvim/lazy-lock.json` | `:Lazy update` in nvim, then commit the diff |
| LSP servers, formatters, linters, DAP adapters | Mason registry snapshot in `versions.lock` → generated into `nvim/lua/mason-pin.lua` | `./setup.sh --update` |

The Mason registry pin is the important one: that registry publishes many times a day, and
without the pin every language server, formatter and linter silently upgrades underneath you.

---

## Troubleshooting

| Symptom | Fix |
|---|---|
| A language server misbehaves | `<leader>cR` restarts it for the buffer. `<leader>cI` shows LSP status. |
| No completion / diagnostics in a file | Check a server actually attached — the statusline shows attached clients, or run `:checkhealth vim.lsp`. |
| Formatting didn't run on save | `<leader>cC` (`:ConformInfo`) lists the formatters for the buffer and whether their binaries exist. `<leader>uf` toggles format-on-save per buffer. |
| A linter produces nothing | `<leader>cL` lists the linters for the filetype, whether each binary exists, and whether it was skipped for want of a project config. |
| Treesitter errors on startup | Parser state is corrupt. `:TSInstall! <lang>` reinstalls one; `:checkhealth nvim-treesitter` lists broken queries. |
| A Mason package is broken | `:MasonUninstall <pkg>` then `:MasonInstall <pkg>`. `<leader>cm` opens the Mason UI. |
| A panel is stuck open | `<leader>qz` closes every tool panel, float and DAP UI at once. |
| Statusline looks wrong / wrong colours | `:LualineNotices` — lualine reports config problems there and silently falls back, rather than raising an error. `./scripts/verify.sh theme statusline` checks the theme resolves and the separators actually render. |
| Icons show as boxes (tofu) | Your terminal font is not a Nerd Font. See post-install step 2. Every codepoint used here is in JetBrainsMono and Hack Nerd Font. |
| Plugin versions drifted | `git checkout nvim/lazy-lock.json` then `:Lazy restore`. |
| Everything drifted | `./setup.sh --check` shows what differs from the lockfile. |
| `command not found: goenv` (or pyenv) on shell start | A legacy un-delimited block from an older version of this script. `./setup.sh` migrates it; it backs `~/.zshrc` up first. |
| `unknown style 'zdiff3' given for 'merge.conflictstyle'` | Your git predates 2.35. `./setup.sh` regenerates `git/gitconfig.local` for the local git version — run it on that machine. |

### Verifying a change

After editing anything under `nvim/`, run:

```bash
./scripts/verify.sh            # all checks
./scripts/verify.sh keymaps    # just README/config keymap consistency
```

It checks that every Lua file parses and is stylua-clean, that `setup.sh` parses under bash 3.2
(macOS's `/bin/bash`, which the script has to bootstrap under) and is shellcheck-clean, that
`versions.lock` and the generated `nvim/lua/mason-pin.lua` agree, that the install path never
resolves a version from the network, that a clean start produces **no warnings, lualine notices
or errors**, that lualine's configured theme actually resolves, and that **every keybinding
documented in this README actually exists in the config**.

The last two exist because of real bugs that passed every other check. lualine reports a bad
theme name through its own notices buffer and then falls back to `auto` — no Lua error, nothing a
`pcall` can see — so the statusline was quietly using the wrong theme. The README check is what
had been missing when it drifted to documenting plugins and keys the config no longer had.

---

## What's installed

### Shell

| Tool | Purpose |
|---|---|
| zsh + oh-my-zsh | Shell and plugin framework |
| powerlevel10k | Prompt (with instant prompt configured) |
| zsh-syntax-highlighting, zsh-autosuggestions | Highlighting and history suggestions |
| fzf | Fuzzy finder, used by the shell functions and Neovim's picker |

### CLI tools

| Tool | Purpose |
|---|---|
| neovim | Editor |
| tmux + tpm | Multiplexer and plugin manager |
| **lazygit** | Primary git UI — interactive rebase, conflicts, stashes |
| **delta** | Syntax-highlighted git diffs; git's pager and the picker's diff previewer |
| ripgrep (`rg`) | Fast grep, powers project search |
| fd | Fast find, powers file search |
| bat | Syntax-highlighted `cat`, powers fzf previews |
| eza | Modern `ls` with git status |
| jq / yq | JSON / YAML processors |
| k9s | Kubernetes TUI (`<leader>uk` in nvim, `prefix+k` in tmux) |
| **psql** | Postgres client, required by the Neovim database UI |

### Version managers

| Tool | Manages |
|---|---|
| rustup | Rust (and `tree-sitter` CLI, which compiles Neovim's parsers) |
| nvm | Node.js — lazy-loaded on first use |
| pyenv | Python — lazy-loaded on first use |
| goenv | Go — lazy-loaded on first use (pinned to 2.x; see `versions.lock`) |
| SDKMAN | Java / JVM — eagerly loaded, because `./mvnw` and `./gradlew` need `JAVA_HOME` |
| tfenv | Terraform |

---

## Neovim

**Plugin manager:** [lazy.nvim](https://github.com/folke/lazy.nvim) · **Leader:** `Space` ·
**Colorscheme:** Catppuccin Mocha · **Requires:** Neovim 0.12+

```
nvim/
├── init.lua              bootstrap + lazy.nvim setup
├── lua/core/             options, keymaps, autocmds (no plugin dependencies)
├── lua/plugins/          one file per concern, each a lazy.nvim spec
├── lua/util/             float terminals, tool-panel registry
├── lua/mason-pin.lua     GENERATED from versions.lock — do not edit
└── lazy-lock.json        plugin version lock
```

Startup is ~58ms with 51 plugins; everything non-essential is lazy-loaded behind a key, command,
filetype or event.

### Keybindings

Press `<leader>` alone for a complete menu (which-key), or `<leader>fk` to fuzzy-search every
mapping. Each prefix is a noun and has exactly one meaning:

| Prefix | Group |
|---|---|
| `<leader>f` | find (picker) |
| `<leader>g` | git · `<leader>gh` git hunks |
| `<leader>c` | code / LSP |
| `<leader>x` | diagnostics & lists |
| `<leader>d` | debug |
| `<leader>t` | test |
| `<leader>b` | buffer |
| `<leader>w` | window |
| `<leader>u` | UI toggles |
| `<leader>q` | quit / close |
| `<leader>s` | search & replace |
| `<leader>D` | database |

LSP **navigation** uses Neovim's own `g`-prefix defaults, rerouted through the picker so you get
previews.

#### Navigation and motions

| Key | Action |
|---|---|
| `gd` / `gD` | Definition / declaration |
| `grr` | References |
| `gri` | Implementations |
| `grt` | Type definition |
| `gO` | Document symbols |
| `gh` | Symbol finder — definitions, references and implementations in one picker |
| `K` / `gK` | Hover / signature help (`<C-s>` for signature help in insert mode) |
| `grn` / `gra` | Rename / code action (Neovim defaults) |
| `<leader>j` / `<leader>J` | Flash jump / flash treesitter select |
| `gsa` `gsd` `gsr` | Surround: add / delete / replace |
| `]d` `[d` | Next / previous diagnostic |
| `]e` `[e` | Next / previous **error** only |
| `]c` `[c` | Next / previous git hunk (falls back to vim's `]c` in diff mode) |
| `]x` `[x` | Next / previous merge conflict (in diffview) · trouble item |
| `]f` `[f` | Next / previous function |
| `]a` `[a` | Next / previous parameter |
| `]t` `[t` | Next / previous **failed** test |
| `]y` `[y` | Next / previous TODO comment |
| `]q` `[q` · `]l` `[l` | Quickfix · location list |

#### Text objects (treesitter)

`a` = around (includes signature and braces), `i` = inner (body only).

| Object | Selects |
|---|---|
| `af` / `if` | Function |
| `ac` / `ic` | Class |
| `aa` / `ia` | Parameter |
| `ao` / `io` | Conditional |
| `al` / `il` | Loop |
| `ab` / `ib` | Block |
| `a=` / `i=` | Assignment |
| `ih` | Git hunk |

So `vaf` selects a function, `cif` rewrites its body, `dih` discards a hunk.

#### Find — `<leader>f`

| Key | Action |
|---|---|
| `<leader><space>` | Files (fast alias) |
| `<leader>/` | Grep project (fast alias) |
| `<leader>,` | Buffers (fast alias) |
| `<leader>ff` | Files |
| `<leader>fg` | Grep project |
| `<leader>fG` | Grep word under cursor (or selection, in visual) |
| `<leader>fb` | Buffers |
| `<leader>fr` | Recent files |
| `<leader>fl` / `<leader>fL` | Lines in this buffer / all buffers |
| `<leader>fs` / `<leader>fS` | Document / workspace symbols |
| `<leader>fm` / `<leader>fj` | Marks / jumplist |
| `<leader>fq` | Quickfix list |
| `<leader>ft` | TODO comments |
| `<leader>fh` / `<leader>fk` / `<leader>fc` | Help tags / keymaps / commands |
| `<leader>fC` | Colorschemes |
| `<leader>f:` / `<leader>f?` | Command / search history |
| **`<leader>fR`** | **Resume last picker** — reopens exactly where you left off |

Inside a picker: `<C-v>` / `<C-s>` / `<C-t>` open in a vsplit / split / tab, `<C-q>` sends every
result to the quickfix list, `<C-e>` toggles the preview, `<C-j>` / `<C-k>` scroll it. In a grep,
anything after `--` is passed to ripgrep, so `useState --glob=*.tsx` scopes the search.

#### Git — `<leader>g`

| Key | Action |
|---|---|
| **`<leader>gg`** | **lazygit** — rebase, squash, reword, cherry-pick, stash, amend, conflicts |
| `<leader>gG` | lazygit scoped to the current file's history |
| `<leader>gc` / `<leader>gC` | Commits: repo / current file (delta previews) |
| `<leader>gb` | Branches |
| `<leader>gs` / `<leader>gS` | Status / stashes |
| `<leader>gt` | Tags |
| `<leader>gd` | Diffview: working tree |
| `<leader>gD` / `<leader>gH` | Diffview: file history — current file / whole repo |
| `<leader>gM` | Diffview: diff against `origin/HEAD` (what a PR would show) |
| `<leader>gm` | Diffview: resolve conflicts (3-way, `diff3_mixed`) |
| **`<leader>gx`** | **Close diffview** |
| `<leader>gv` | `:Gvdiffsplit` — fugitive's 3-way conflict editor |
| `<leader>gy` | Open current line on GitHub (`:GBrowse`) |
| `<leader>gB` | Blame (fugitive) |

In diffview: `<tab>` / `<s-tab>` next/previous file, `s` stage or unstage, `X` discard,
`]x` / `[x` jump between conflicts, and `<leader>co` / `ct` / `cb` / `ca` / `cn` take
ours / theirs / base / all / none.

#### Git hunks — `<leader>gh`

| Key | Action |
|---|---|
| `<leader>ghs` / `<leader>ghr` | Stage / reset hunk (works on a selection in visual mode) |
| `<leader>ghS` / `<leader>ghR` | Stage / reset whole buffer |
| `<leader>ghu` | Undo stage hunk |
| `<leader>ghp` / `<leader>ghi` | Preview hunk in a float / inline |
| `<leader>ghb` / `<leader>ghB` | Blame line (full) / whole file |
| `<leader>ghd` / `<leader>ghD` | Diff this / against `HEAD~` |
| `<leader>ghq` / `<leader>ghQ` | Hunks → quickfix: buffer / whole repo |

#### Code — `<leader>c`

| Key | Action |
|---|---|
| `<leader>ca` | Code action |
| `<leader>cr` | Rename symbol |
| `<leader>cf` | Format file or selection |
| `<leader>co` | Organize imports |
| `<leader>cF` | Fix all auto-fixable (eslint, ruff) |
| `<leader>cl` / `<leader>cL` | Lint now / show which linters apply |
| `<leader>cd` | Line diagnostics float |
| `<leader>cs` / `<leader>cS` | Swap parameter with next / previous |
| `<leader>cb` | Pick from breadcrumbs (dropbar) |
| `<leader>cR` / `<leader>cI` | Restart LSP client / LSP status |
| `<leader>cC` / `<leader>cm` | `:ConformInfo` / Mason UI |
| `<leader>cp` / `<leader>cx` | Copy file path / `chmod +x` this file |

Java adds `<leader>cv` extract variable, `<leader>cn` extract constant, `<leader>cm` extract
method (visual), `<leader>cu` update project config. Rust adds `<leader>cA` grouped code actions,
`<leader>cE` expand macro, `<leader>cD` open docs.rs.

#### Diagnostics and lists — `<leader>x`

| Key | Action |
|---|---|
| `<leader>xx` / `<leader>xX` | Diagnostics: buffer / workspace |
| `<leader>xs` | Symbol outline (docked right) |
| `<leader>xr` | LSP references and definitions |
| `<leader>xq` / `<leader>xl` | Quickfix / location list |
| `<leader>xt` / `<leader>xT` | TODO comments / TODO+FIXME only |
| `<leader>xc` | Close trouble |

#### Debug — `<leader>d`

| Key | Action |
|---|---|
| `<leader>db` / `<leader>dB` / `<leader>dL` | Breakpoint / conditional / log point |
| `<leader>dC` / `<leader>dl` | Clear all breakpoints / list them in quickfix |
| `<leader>dc` | Continue or start |
| `<leader>di` / `<leader>do` / `<leader>dO` | Step into / over / out |
| `<leader>dj` / `<leader>dk` | Down / up a stack frame |
| `<leader>dg` | Run to cursor |
| `<leader>dr` / `<leader>dq` / `<leader>dp` | Restart / terminate / pause |
| `<leader>du` | Toggle DAP UI |
| `<leader>de` | Evaluate expression (works on a visual selection) |
| `<leader>dw` / `<leader>dR` | Add watch / toggle REPL |
| **`<leader>dt` / `<leader>dT`** | **Debug nearest test / test class** |

A project's existing `.vscode/launch.json` is loaded automatically, so VSCode debug
configurations work unchanged.

#### Test — `<leader>t`

| Key | Action |
|---|---|
| `<leader>tt` / `<leader>tf` / `<leader>ta` | Run nearest / file / all |
| `<leader>tl` / `<leader>td` | Re-run last / debug nearest |
| `<leader>ts` | Toggle summary panel |
| `<leader>to` / `<leader>tO` | Show output / toggle output panel |
| `<leader>tw` | Toggle watch mode |
| `<leader>tq` | Stop running test |

#### Buffers, windows, quit

| Key | Action |
|---|---|
| `<S-h>` / `<S-l>` | Previous / next buffer |
| `<leader>bd` / `<leader>bD` | Delete buffer **keeping the window layout** / force |
| `<leader>bo` | Delete all other buffers |
| `<leader>bs` / `<leader>bS` | Save / save all |
| ``<leader>b` `` | Last used buffer |
| `<leader>wv` / `<leader>ws` | Split vertical / horizontal |
| `<leader>wc` / `<leader>wo` | Close this / close others |
| `<leader>wm` / `<leader>w=` | Maximise toggle / equalise |
| `<C-h/j/k/l>` | Move between windows (and tmux panes) |
| `<C-Up/Down/Left/Right>` | Resize window |
| `<leader>qq` / `<leader>qQ` / `<leader>qw` | Quit all / discard / save and quit |
| **`<leader>qz`** | **Close every tool panel, float and DAP UI** |

#### UI toggles — `<leader>u`

| Key | Action |
|---|---|
| `<C-n>` / `<leader>ue` | Toggle file explorer |
| `<leader>uE` | Reveal current file in the explorer |
| `<leader>ub` / `<leader>uG` | Buffer tree / git status tree |
| `<leader>uu` | Undo tree |
| `<leader>uk` | k9s (Kubernetes) |
| `<leader>uv` | **Switch diagnostics between expanded lines and compact inline text** |
| `<leader>ud` / `<leader>uh` | Toggle diagnostics / inlay hints |
| `<leader>uf` / `<leader>uF` | Toggle format-on-save: buffer / global |
| `<leader>ug` / `<leader>uC` | Toggle indent guides / colour swatches |
| `<leader>uw` / `<leader>ul` / `<leader>un` | Toggle wrap / relative numbers / line numbers |
| `<leader>us` / `<leader>uc` | Toggle spell check / conceal |
| `<leader>ui` / `<leader>uI` | Inspect treesitter tree / highlight under cursor |

#### Other

| Key | Action |
|---|---|
| `jk` | Exit insert mode |
| `<Esc>` | Clear search highlight |
| `<C-\>` | Toggle floating terminal |
| `<leader>sr` | Replace word under cursor in buffer |
| `<leader>y` / `<leader>Y` / `<leader>P` | Yank / yank line / paste — system clipboard |
| `<leader>p` | Paste over selection without clobbering the register |
| `<leader>X` | Delete without yanking |
| `<leader>?` | Buffer-local keymaps |
| `<leader>j` / `<leader>J` | Flash jump / flash treesitter select |

> `s`, `S` and visual `R` keep their stock vim meanings (substitute char, line
> and visual lines). flash.nvim binds those by default; here jumping is on
> `<leader>j` instead. flash's operator-pending `r` and `R` (`dr`, `yR`) are
> kept, since vim has no default meaning there to shadow.

> The system clipboard is deliberately **not** wired to every yank (`clipboard=unnamedplus` is
> off), so `d` and `x` never clobber what you copied from the browser. Use `<leader>y` to cross
> over on purpose.

#### Completion — blink.cmp

| Key | Action |
|---|---|
| `<C-b>` | Show menu / toggle docs |
| `<Tab>` / `<S-Tab>` | Next / previous item, or jump snippet placeholder |
| `<CR>` | Accept |
| `<C-e>` | Dismiss |
| `<C-k>` / `<C-j>` | Scroll docs |

### Language support

Verified end to end: LSP attaches, completion works, format-on-save runs the listed formatter,
and lint produces diagnostics.

| Language | LSP | Formatter | Linter | Debug |
|---|---|---|---|---|
| TypeScript / JS / React | `vtsls`, `eslint`, `tailwindcss`, `emmet` | prettierd | eslint (LSP) | js-debug |
| Python | `basedpyright` + `ruff` | ruff (format + organize imports) | ruff (LSP) | debugpy |
| Java | `jdtls` (via nvim-jdtls) | Spotless → google-java-format | checkstyle¹ | java-debug + java-test |
| Go | `gopls` | goimports + gofumpt | golangci-lint | delve |
| Terraform / HCL | `terraformls`, `tflint` | terraform fmt | tflint | — |
| Bash / sh | `bashls` | shfmt | shellcheck | bash-debug |
| JSON | `jsonls` + SchemaStore | prettierd | (schema validation) | — |
| YAML / Kubernetes | `yamlls` + SchemaStore | prettierd | yamllint | — |
| Helm | `helm_ls` | (whitespace only²) | — | — |
| CSS / SCSS / Tailwind | `cssls`, `tailwindcss`, `emmet` | prettierd | (LSP) | — |
| Dockerfile | `docker_language_server` | — | hadolint | — |
| SQL | `sqls` | sql-formatter | — | — |
| TOML | `taplo` | taplo | — | — |
| Markdown | `marksman` | prettierd | markdownlint-cli2 | — |
| Lua | `lua_ls` + lazydev | stylua | — | — |
| Rust | `rust_analyzer` (rustaceanvim, clippy) | rustfmt | clippy | codelldb |
| GraphQL | `graphql` | prettierd | — | — |

¹ checkstyle only runs when the project actually has a `checkstyle.xml` — ungated it errors out
and the errors surface as mystery diagnostics.
² prettier would mangle Go template syntax, so Helm templates get whitespace trimming only.

Tailwind classes are resolved inside `cva()`, `cn()`, `clsx()` and `cx()` helpers, and rendered
as inline colour swatches.

### Database

Browse schemas, run queries, and get completion from the live schema — `<leader>D`.

| Key | Action |
|---|---|
| `<leader>DD` | Toggle the database UI |
| `<leader>Df` | Find a DB buffer |
| `<leader>Da` | Add a connection |
| `<leader>Dr` / `<leader>Dq` | Rename buffer / last query info |
| `<leader>DS` | Execute the query (in a `.sql` buffer; works on a selection) |
| `<leader>DW` | Save the query |

Connections live **outside this repo** so credentials are never committed. Create
`~/.config/nvim-dbs.lua`:

```lua
return {
  dev      = "postgres://user:pass@localhost:5432/myapp_dev",
  local_pg = "postgres://postgres@localhost:5432/postgres",
}
```

Prefer a `~/.pgpass` entry or `PG*` environment variables over an inline password — dadbod
expands `$VARS` in the URL. In a `.sql` buffer, completion is sourced from the connected
database's real schema, so table and column names are checked rather than guessed.

### Plugins

| Plugin | Purpose |
|---|---|
| [lazy.nvim](https://github.com/folke/lazy.nvim) | Plugin manager |
| [catppuccin](https://github.com/catppuccin/nvim) | Colorscheme |
| [lualine](https://github.com/nvim-lualine/lualine.nvim) | Statusline (LSP clients, DAP status, pending updates) |
| [dropbar.nvim](https://github.com/Bekaboo/dropbar.nvim) | Winbar breadcrumbs |
| [fzf-lua](https://github.com/ibhagwan/fzf-lua) | Picker (files, grep, git, LSP, `vim.ui.select`) |
| [neo-tree](https://github.com/nvim-neo-tree/neo-tree.nvim) | File explorer |
| [trouble.nvim](https://github.com/folke/trouble.nvim) | Diagnostics, references, symbol outline |
| [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) + textobjects | Parsing, indent, folds, text objects |
| [blink.cmp](https://github.com/Saghen/blink.cmp) + friendly-snippets | Completion |
| [mini.nvim](https://github.com/echasnovski/mini.nvim) | pairs, surround, notify |
| [mason](https://github.com/mason-org/mason.nvim) + lspconfig + tool-installer | Tool installation, **registry-pinned** |
| [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) | LSP client config |
| [schemastore.nvim](https://github.com/b0o/schemastore.nvim) | JSON/YAML schemas (k8s, Actions, package.json) |
| [nvim-jdtls](https://github.com/mfussenegger/nvim-jdtls) | Java: refactorings, test runner, DAP |
| [rustaceanvim](https://github.com/mrcjkb/rustaceanvim) | Rust |
| [lazydev.nvim](https://github.com/folke/lazydev.nvim) | Lua: `vim.*` API types |
| [conform.nvim](https://github.com/stevearc/conform.nvim) | Formatting |
| [nvim-lint](https://github.com/mfussenegger/nvim-lint) | Linting |
| [nvim-dap](https://github.com/mfussenegger/nvim-dap) + ui, virtual-text, python, go | Debugging |
| [neotest](https://github.com/nvim-neotest/neotest) + python, jest, golang | Test runner |
| [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) | Inline hunks |
| [diffview.nvim](https://github.com/sindrets/diffview.nvim) | Multi-file diff, 3-way merge |
| [vim-fugitive](https://github.com/tpope/vim-fugitive) + rhubarb | `:Gvdiffsplit`, `:GBrowse` |
| [vim-dadbod](https://github.com/tpope/vim-dadbod) + ui, completion | Database UI |
| [which-key.nvim](https://github.com/folke/which-key.nvim) | Keybinding menu |
| [flash.nvim](https://github.com/folke/flash.nvim) | Jump motions |
| [todo-comments.nvim](https://github.com/folke/todo-comments.nvim) | TODO highlighting and index |
| [indent-blankline](https://github.com/lukas-reineke/indent-blankline.nvim) | Indent guides |
| [nvim-highlight-colors](https://github.com/brenoprata10/nvim-highlight-colors) | Colour swatches (incl. Tailwind) |
| [vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator) | Shared nvim/tmux pane navigation |
| [render-markdown.nvim](https://github.com/MeanderingProgrammer/render-markdown.nvim) | Markdown rendering |
| nvim.undotree | Undo history — ships with Neovim 0.12, no plugin |

Floating terminals (lazygit, `<C-\>`, k9s) use a ~145-line helper in `lua/util/float.lua` rather
than a plugin; `<leader>qz` closes everything via a registry in `lua/util/panels.lua`.

---

## git

`git/gitconfig` is **included** from `~/.gitconfig` (not copied), so edits take effect
immediately and your identity stays out of this repo.

### Cross-version compatibility

This repo is used on machines with very different git versions — macOS ships 2.50, Ubuntu 20.04
ships 2.24. Git *validates* some config values rather than ignoring ones it doesn't know, so a
single unsupported value breaks **every** git command on the older machine:

```
error: unknown style 'zdiff3' given for 'merge.conflictstyle'
```

So the committed `git/gitconfig` holds only settings that work on git **2.24+**, and anything
newer is written per machine by `setup.sh` into `git/gitconfig.local` (generated, gitignored,
included last). You get the best configuration each machine's git actually supports:

| Setting | Needs git | On git 2.24 |
|---|---|---|
| `merge.conflictstyle = zdiff3` | 2.35 | falls back to `diff3` (still shows the common ancestor) |
| `help.autocorrect = prompt` | 2.37 | omitted |
| `push.autoSetupRemote` | 2.37 | omitted |
| `rebase.updateRefs` | 2.38 | omitted |
| `fetch.all` | 2.41 | omitted |
| `init.defaultBranch` | 2.28 | omitted |

`./scripts/verify.sh gitcompat` fails if a version-gated value is ever committed to the shared
file, and confirms git can read the result.

The settings that matter most for rebasing:

| Setting | Why |
|---|---|
| `rerere.enabled` | Records how you resolved each conflict and **replays it automatically** next time the same conflict appears. Abort and retry a rebase without redoing the work. |
| `rebase.autostash` | A dirty working tree no longer blocks a rebase |
| `rebase.autosquash` | `git fix <sha>` commits reorder themselves |
| `rebase.updateRefs` | Stacked branches follow along |
| `merge.conflictstyle=zdiff3` | Shows the **common ancestor** alongside both sides, so you can see what each side actually changed |
| `diff.algorithm=histogram` | Noticeably better hunks on reordered or reindented code |
| `delta` as pager | Syntax-highlighted diffs with line numbers |

Aliases: `git lg` (graph log), `git ri` / `rc` / `ra` (rebase interactive / continue / abort),
`git cleanup [base]` (interactive rebase from the merge-base — "tidy my branch before review"),
`git fix <sha>` / `git squash <sha>`, `git amend`, `git conflicts`, `git ours` / `theirs`,
`git undo`, `git pushf` (force-with-lease).

---

## zsh

### Keybindings

| Key | Action |
|---|---|
| `^Y` | Clear screen |
| `^F` / `^B` | Kill to end / start of line |
| `^P` / `^O` | Forward / backward word |

### Aliases

| Alias | Purpose |
|---|---|
| `ls` `ll` `la` `lt` `l2` | eza listings (long, hidden, tree, 2-level tree) |
| `cat` | bat, no pager |
| `json` / `yaml` | `jq .` / `yq .` |
| `v` / `vi` | nvim |
| `lg` | lazygit — the same UI as `<leader>gg` |
| `gs` `gd` `gds` `gl` | git status / diff / diff --staged / graph log |
| `gco` `gcb` | git checkout / checkout -b |
| `gri` `grc` `gra` | git rebase interactive / continue / abort |
| `ta` `tl` `tn` `tk` | tmux attach / list / new / kill-session |
| `tf` `tfi` `tfp` `tfa` `tfd` | terraform shorthands |

### Functions

| Function | Purpose |
|---|---|
| `fh` | Fuzzy history search — loads the command into the prompt to edit |
| `nf [dir]` | Fuzzy find a file (bat preview) and open it in nvim |
| `fcd [dir]` | Fuzzy `cd` with a tree preview |
| `fgb` | Fuzzy branch checkout, newest first, with a commit-log preview |
| `fkill` | Fuzzy process kill (multi-select) |
| `frg [pattern]` | ripgrep → fzf → open in nvim at the matching line |
| `fshow` | Browse commits with a delta diff preview |

New terminals auto-attach to a tmux session named `main`. nvm, pyenv and goenv are lazy-loaded
on first use so they cost nothing at shell startup.

### Managed `.zshrc` regions

Everything this script writes to `~/.zshrc` lives between explicit delimiters:

```sh
# >>> terminal-setup: aliases >>>
...
# <<< terminal-setup: aliases <<<
```

The whole region is **regenerated** on every run, so changes to `setup.sh` always reach every
machine and a damaged region repairs itself. Anything outside the delimiters is yours and is
never touched. Earlier versions appended un-delimited blocks and only checked whether a header
line existed, which meant a stale block blocked its own replacement forever — that is how a
legacy eager `eval "$(goenv init -)"` survived and produced `command not found: goenv` on every
terminal start. `setup.sh` migrates those legacy blocks once, backing `~/.zshrc` up first.

---

## tmux

**Prefix:** `Ctrl-s`. Config is symlinked, so edits apply on the next `prefix + r`.

| Key | Action |
|---|---|
| `prefix + r` | Reload config |
| `prefix + \|` / `prefix + -` | Split vertical / horizontal (in the current path) |
| `prefix + c` | New window in the current path |
| `prefix + h/j/k/l` | Navigate panes (shared with Neovim via vim-tmux-navigator) |
| `prefix + H/J/K/L` | Resize pane (repeatable) |
| `prefix + M` | Zoom pane |
| `prefix + S` | Fuzzy session switcher |
| `prefix + n/p` | Next / previous window |
| `prefix + X` | Kill window (with confirmation) |
| **`prefix + g`** | **lazygit in a popup** |
| `prefix + t` | Scratch shell popup |
| `prefix + k` | k9s popup |
| `prefix + Enter` | Copy mode (`v` select, `y` yank, `C-v` block) |
| `prefix + I` | Install plugins (tpm) |

Clipboard is resolved at runtime (pbcopy on macOS; Wayland / X11 / OSC 52 on Linux), so the same
config file works everywhere.

---

## Split keyboard

Corne layout config and layer images: [split-keyboard/](split-keyboard/README.md)
