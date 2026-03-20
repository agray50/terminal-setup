# terminal-setup

Automated developer environment setup for macOS and Linux. Covers zsh, Neovim, tmux, and supporting CLI tools.

## Quick Start

```bash
git clone <repo-url> ~/git/terminal-setup
cd ~/git/terminal-setup
./setup.sh
```

The script is idempotent — safe to run multiple times. It installs everything, symlinks configs, and runs headless plugin installs for Neovim and tmux.

### Post-install (manual)

1. Install a [Nerd Font](https://github.com/ryanoasis/nerd-fonts) — JetBrainsMono or FiraCode recommended
2. Set the Nerd Font in your terminal emulator
3. Install [Catppuccin](https://github.com/catppuccin) theme for your terminal ([iTerm2](https://github.com/catppuccin/iterm) / [GNOME](https://github.com/catppuccin/gnome-terminal) / [Alacritty](https://github.com/catppuccin/alacritty))
4. Run `source ~/.zshrc`
5. If no `p10k.zsh` is present in the repo root, run `p10k configure` to set up your prompt

---

## What Gets Installed

| Tool | Purpose |
|---|---|
| zsh + oh-my-zsh + powerlevel10k | Shell and prompt |
| zsh-syntax-highlighting | Command syntax highlighting |
| zsh-autosuggestions | History-based suggestions |
| fzf | Fuzzy finder |
| neovim | Editor |
| tmux + tpm | Terminal multiplexer + plugin manager |
| Rust (rustup) | Required for blink.cmp fuzzy matching |
| ripgrep | Fast grep (used by Telescope) |
| fd | Fast find (used by Telescope) |
| bat | Syntax-highlighted cat (used by `nf` alias) |
| nvm | Node version manager |
| pyenv | Python version manager |
| tfenv | Terraform version manager |

---

## zsh

### Keybindings

| Key | Action |
|---|---|
| `^Y` | Clear screen |
| `^F` | Kill to end of line |
| `^B` | Kill to start of line |
| `^O` | Forward word |
| `^P` | Backward word |

### Aliases

| Alias | Action |
|---|---|
| `nf` | Open file picked with fzf in Neovim (bat preview) |
| `gg` | Open Neovim with fugitive git status |

### tmux auto-attach

New terminal sessions automatically attach to (or create) a tmux session named `main`.

---

## tmux

**Prefix:** `Ctrl-s`

| Key | Action |
|---|---|
| `prefix + r` | Reload config |
| `prefix + h/j/k/l` | Navigate panes |
| `prefix + I` | Install plugins (tpm) |

**Plugins:** [tpm](https://github.com/tmux-plugins/tpm) · [vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator) · [catppuccin/tmux](https://github.com/catppuccin/tmux)

---

## Neovim

**Plugin manager:** [lazy.nvim](https://github.com/folke/lazy.nvim) — specs in `nvim/lua/plugins/`
**Leader key:** `Space`
**Colorscheme:** Catppuccin Mocha

### Plugins

| Plugin | Purpose |
|---|---|
| [catppuccin/nvim](https://github.com/catppuccin/nvim) | Colorscheme |
| [lualine.nvim](https://github.com/nvim-lualine/lualine.nvim) | Statusline |
| [neo-tree.nvim](https://github.com/nvim-neo-tree/neo-tree.nvim) | File explorer |
| [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | Syntax/parsing |
| [blink.cmp](https://github.com/Saghen/blink.cmp) | Completion |
| [friendly-snippets](https://github.com/rafamadriz/friendly-snippets) | Snippet library |
| [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) | Fuzzy finder |
| [which-key.nvim](https://github.com/folke/which-key.nvim) | Keybind popup |
| [mason.nvim](https://github.com/mason-org/mason.nvim) | LSP/tool installer |
| [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) | LSP client config |
| [conform.nvim](https://github.com/stevearc/conform.nvim) | Formatting |
| [nvim-lint](https://github.com/mfussenegger/nvim-lint) | Linting |
| [vim-fugitive](https://github.com/tpope/vim-fugitive) | Git client |
| [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) | Git hunk signs and actions |
| [diffview.nvim](https://github.com/sindrets/diffview.nvim) | Diff viewer |
| [vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator) | Seamless tmux/nvim pane navigation |
| [markview.nvim](https://github.com/OXY2DEV/markview.nvim) | Markdown rendering |

### LSP Servers (auto-installed via Mason)

`ts_ls` · `html` · `cssls` · `tailwindcss` · `lua_ls` · `pyright` · `eslint` · `yamlls` · `helm_ls` · `terraformls` · `jdtls`

### Formatters & Linters

| Tool | Languages |
|---|---|
| prettier | JS, TS, JSX, TSX, CSS, HTML, JSON, YAML, Markdown |
| stylua | Lua |
| isort + black | Python |
| eslint_d | JS, TS, JSX, TSX |
| pylint | Python |
| yamllint | YAML |
| checkstyle | Java |

---

### Keybindings

> Press `<leader>?` to show buffer-local keymaps via which-key.

#### File Explorer

| Key | Action |
|---|---|
| `<C-n>` | Toggle neo-tree |

#### Find (`<leader>f`)

| Key | Action |
|---|---|
| `<leader>fp` | Find files |
| `<leader>ff` | Find in current buffer |
| `<leader>fg` | Live grep |
| `<leader>fw` | Grep word under cursor |
| `<leader>fb` | Open buffers |
| `<leader>fr` | Recent files |
| `<leader>fh` | Help tags |
| `<leader>fk` | Keymaps |
| `<leader>fc` | Commands |
| `<leader>fs` | Document symbols |

#### Git — fugitive (`<leader>g`)

| Key | Action |
|---|---|
| `<leader>gg` | Git status |
| `<leader>gp` | Git push |
| `<leader>gl` | Git pull |
| `<leader>gb` | Git blame |
| `<leader>gw` | Stage current file |
| `<leader>gr` | Revert current file to HEAD |
| `<leader>gc` | Browse git commits (Telescope) |
| `<leader>gs` | Browse git status (Telescope) |

> Inside the fugitive status window: `s` stage · `u` unstage · `cc` commit · `ca` amend · `dd` diff · `=` toggle inline diff · `g?` all keymaps

#### Git — hunks/gitsigns (`<leader>h`)

| Key | Action |
|---|---|
| `]c` / `[c` | Next / prev change |
| `<leader>hs` | Stage hunk |
| `<leader>hr` | Reset hunk |
| `<leader>hS` | Stage buffer |
| `<leader>hR` | Reset buffer |
| `<leader>hp` | Preview hunk |
| `<leader>hi` | Preview hunk inline |
| `<leader>hb` | Blame line |
| `<leader>hd` | Diff this |
| `<leader>hD` | Diff this against HEAD~ |
| `<leader>hq` | Send changes to quickfix |
| `<leader>hQ` | Send all changes to quickfix |
| `ih` | Text object: inner hunk (visual/operator) |

#### Git — toggles (`<leader>t`)

| Key | Action |
|---|---|
| `<leader>tb` | Toggle line blame |
| `<leader>tw` | Toggle word diff |

#### Diffview

| Command | Action |
|---|---|
| `:DiffviewOpen` | Open diff view |
| `:DiffviewClose` | Close diff view |
| `:DiffviewToggleFiles` | Toggle file panel |

#### LSP — custom (`gr*`)

Uses Neovim 0.11 native LSP. Built-in defaults require no config.

| Key | Action | Type |
|---|---|---|
| `grn` | Rename | built-in |
| `gra` | Code action | built-in |
| `grr` | References | built-in |
| `gri` | Implementations | built-in |
| `grt` | Type definition | built-in |
| `gO` | Document symbols | built-in |
| `K` | Hover | built-in |
| `<C-W>d` | Diagnostics float | built-in |
| `[d` / `]d` | Prev / next diagnostic | built-in |
| `grd` | Go to definition (Telescope) | custom |
| `grD` | Go to declaration | custom |
| `grq` | Buffer diagnostics (Telescope) | custom |
| `grs` | Restart LSP | custom |

#### LSP (`<leader>l`)

| Key | Action |
|---|---|
| `<leader>ld` | Go to definition (Telescope) |
| `<leader>lD` | Go to declaration |
| `<leader>ll` | Trigger linting |

#### Format

| Key | Action |
|---|---|
| `<leader>mp` | Format file or selection |

#### Completion (blink.cmp)

| Key | Action |
|---|---|
| `<C-space>` | Show menu / toggle docs |
| `<Tab>` | Next item / next snippet placeholder |
| `<S-Tab>` | Prev item / prev snippet placeholder |
| `<CR>` | Accept |
| `<C-e>` | Dismiss |
| `<C-k>` / `<C-j>` | Scroll docs up / down |

#### General

| Key | Action |
|---|---|
| `<C-h/j/k/l>` | Navigate windows / tmux panes |
| `<leader>p` | Paste without yanking replaced text |
| `<leader>y` / `<leader>Y` | Yank to system clipboard |
| `<leader>d` | Delete without yanking |
| `<leader>s` | Search and replace word under cursor |
| `<leader>x` | Make current file executable |
| `<leader>?` | Show buffer keymaps (which-key) |

---

## Split Keyboard

Corne layout config and layer images: [split-keyboard/](split-keyboard/README.md)
