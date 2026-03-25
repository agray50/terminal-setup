# terminal-setup

Automated developer environment setup for macOS and Linux. Covers zsh, Neovim, tmux, and a full suite of CLI tools.

---

## Prerequisites

The script requires `git`, `curl`, and `perl` to be present before running.

**macOS** — install Xcode Command Line Tools if not already present:
```bash
xcode-select --install
```
Homebrew is installed automatically by the script if missing.

**Linux (Debian/Ubuntu)**:
```bash
sudo apt-get install -y git curl perl
```

**Linux (Fedora/RHEL)**:
```bash
sudo dnf install -y git curl perl
```

---

## Quick Start

```bash
git clone <repo-url> ~/git/terminal-setup
cd ~/git/terminal-setup
./setup.sh
```

The script is idempotent — safe to run multiple times. It installs all tools via binaries or installer scripts (minimal package manager use), symlinks Neovim and tmux configs, and runs headless plugin sync for both.

---

## Post-Install Steps

Complete these steps in order after the script finishes.

### 1. Reload your shell
```bash
source ~/.zshrc
```

### 2. Install a Nerd Font

Download from [nerd-fonts](https://github.com/ryanoasis/nerd-fonts). **JetBrainsMono Nerd Font** is recommended.

Set it in your terminal:
- **iTerm2**: Preferences → Profiles → Text → Font
- **GNOME Terminal**: Preferences → Profile → Text → Custom font

### 3. Install Catppuccin for your terminal

- **iTerm2**: https://github.com/catppuccin/iterm
- **GNOME Terminal**: https://github.com/catppuccin/gnome-terminal
- **Alacritty**: https://github.com/catppuccin/alacritty

### 4. Configure your prompt (if no `p10k.zsh` in repo root)
```bash
p10k configure
```

### 5. Install Node.js (via nvm)
```bash
nvm install --lts
nvm use --lts
```

### 6. Install Python (via pyenv)
```bash
pyenv install 3.13.0    # or latest stable
pyenv global 3.13.0
```

### 7. Install Go (via goenv)
```bash
goenv install 1.23.0    # or latest stable
goenv global 1.23.0
```

### 8. Install Java (via SDKMAN)
```bash
sdk install java
```

### 9. Install Terraform (via tfenv)
```bash
tfenv install latest
tfenv use latest
```

### 10. Install tmux plugins
Open tmux and press `prefix + I` (Ctrl-s + I) to install plugins via tpm.

---

## What Gets Installed

### Shell

| Tool | Purpose |
|---|---|
| zsh | Shell |
| oh-my-zsh | Plugin/theme framework |
| powerlevel10k | Prompt theme |
| zsh-syntax-highlighting | Command syntax highlighting |
| zsh-autosuggestions | History-based suggestions |
| fzf | Fuzzy finder |

### CLI Tools

| Tool | Purpose |
|---|---|
| neovim | Editor |
| tmux + tpm | Terminal multiplexer + plugin manager |
| ripgrep (`rg`) | Fast grep, used by Telescope |
| fd | Fast find, used by Telescope |
| bat | Syntax-highlighted cat |
| eza | Modern `ls` with git integration and icons |
| jq | JSON processor |
| yq | YAML processor |
| k9s | Kubernetes terminal UI |

### Version Managers

| Tool | Manages | Install command |
|---|---|---|
| rustup | Rust toolchain | auto (required for blink.cmp) |
| nvm | Node.js | `nvm install --lts` |
| pyenv | Python | `pyenv install <version>` |
| goenv | Go | `goenv install <version>` |
| SDKMAN | Java / JVM | `sdk install java` |
| tfenv | Terraform | `tfenv install latest` |

---

## zsh

### Keybindings

| Key | Action |
|---|---|
| `^Y` | Clear screen |
| `^F` | Kill to end of line |
| `^B` | Kill to start of line |
| `^P` | Forward word |
| `^O` | Backward word |

### Aliases

| Alias | Command | Purpose |
|---|---|---|
| `ls` | `eza --icons` | Directory listing |
| `ll` | `eza -lh --git --icons` | Long listing with git status |
| `la` | `eza -lah --git --icons` | Long listing including hidden files |
| `lt` | `eza --tree --icons` | Tree view |
| `l2` | `eza --tree --level=2 --icons` | 2-level tree view |
| `cat` | `bat --paging=never` | Syntax-highlighted output |
| `json` | `jq .` | Pretty-print JSON |
| `yaml` | `yq .` | Pretty-print YAML |
| `nf` | nvim + fzf + bat | Pick file with fzf preview, open in Neovim |
| `gg` | `nvim -c "Git"` | Open Neovim with fugitive git status |
| `ta` | `tmux attach -t` | Attach to tmux session |
| `tl` | `tmux ls` | List tmux sessions |
| `tn` | `tmux new -s` | New named tmux session |
| `tk` | `tmux kill-session -t` | Kill tmux session |
| `tf` | `terraform` | Terraform shorthand |
| `tfi` | `terraform init` | |
| `tfp` | `terraform plan` | |
| `tfa` | `terraform apply` | |
| `tfd` | `terraform destroy` | |

### Shell Functions

| Function | Purpose |
|---|---|
| `fh` | Fuzzy search shell history — loads selected command into prompt for editing |
| `fcd` | Fuzzy cd into any subdirectory (fd + fzf + eza tree preview) |
| `fgb` | Fuzzy git branch checkout |
| `fkill` | Fuzzy process kill (multi-select supported) |
| `frg [pattern]` | Search file contents (ripgrep → fzf with bat preview) → open in Neovim at matched line |

### tmux Auto-attach

New terminal sessions automatically attach to (or create) a tmux session named `main`.

---

## tmux

**Prefix:** `Ctrl-s`

| Key | Action |
|---|---|
| `prefix + r` | Reload config |
| `prefix + \|` | Split pane horizontal |
| `prefix + -` | Split pane vertical |
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
| [nvim-treesitter](https://github.com/nvim-treesitter/nvim-treesitter) | Syntax / parsing |
| [blink.cmp](https://github.com/Saghen/blink.cmp) | Completion |
| [blink.pairs](https://github.com/saghen/blink.pairs) | Auto-pairs |
| [friendly-snippets](https://github.com/rafamadriz/friendly-snippets) | Snippet library |
| [telescope.nvim](https://github.com/nvim-telescope/telescope.nvim) | Fuzzy finder |
| [which-key.nvim](https://github.com/folke/which-key.nvim) | Keybind popup |
| [mason.nvim](https://github.com/mason-org/mason.nvim) | LSP / tool installer |
| [nvim-lspconfig](https://github.com/neovim/nvim-lspconfig) | LSP client config |
| [lazydev.nvim](https://github.com/folke/lazydev.nvim) | Lua LSP globals (`vim.*`) |
| [conform.nvim](https://github.com/stevearc/conform.nvim) | Formatting |
| [nvim-lint](https://github.com/mfussenegger/nvim-lint) | Linting |
| [nvim-dap](https://github.com/mfussenegger/nvim-dap) | Debug adapter protocol |
| [nvim-dap-ui](https://github.com/rcarriga/nvim-dap-ui) | DAP UI |
| [nvim-dap-virtual-text](https://github.com/theHamsta/nvim-dap-virtual-text) | Inline debug values |
| [mason-nvim-dap](https://github.com/jay-babu/mason-nvim-dap.nvim) | Auto-configure DAP adapters |
| [vim-fugitive](https://github.com/tpope/vim-fugitive) | Git client |
| [gitsigns.nvim](https://github.com/lewis6991/gitsigns.nvim) | Git hunk signs and actions |
| [diffview.nvim](https://github.com/sindrets/diffview.nvim) | Diff viewer |
| [undotree](https://github.com/mbbill/undotree) | Undo history visualiser |
| [vim-tmux-navigator](https://github.com/christoomey/vim-tmux-navigator) | Seamless tmux/nvim pane navigation |
| [markview.nvim](https://github.com/OXY2DEV/markview.nvim) | Markdown rendering |

### LSP Servers (auto-installed via Mason)

| Server | Language(s) |
|---|---|
| `ts_ls` | TypeScript / JavaScript |
| `eslint` | TypeScript / JavaScript (linting + fix code actions) |
| `html` | HTML |
| `cssls` | CSS |
| `tailwindcss` | Tailwind CSS |
| `jsonls` | JSON |
| `yamlls` | YAML (schema store enabled — Kubernetes, GitHub Actions, etc.) |
| `lua_ls` | Lua |
| `pyright` | Python |
| `gopls` | Go |
| `rust_analyzer` | Rust (clippy enabled for check-on-save) |
| `bashls` | Bash / Shell |
| `terraformls` | Terraform / HCL |
| `helm_ls` | Helm charts |
| `jdtls` | Java |

### Formatters (conform.nvim, runs on save)

| Tool | Languages |
|---|---|
| prettier | JS, TS, JSX, TSX, CSS, HTML, JSON, YAML, Markdown |
| stylua | Lua |
| isort + black | Python |
| goimports | Go |
| rustfmt | Rust |
| terraform_fmt | Terraform, HCL |
| shfmt | Bash / Shell |

### Linters (nvim-lint)

| Tool | Languages |
|---|---|
| pylint | Python |
| yamllint | YAML |
| golangci-lint | Go |
| shellcheck | Bash / Shell |

> JS/TS linting is handled by the `eslint` LSP server, which also provides `eslint --fix` code actions.

### DAP Adapters (auto-installed via Mason)

| Adapter | Languages |
|---|---|
| codelldb | Rust, C, C++ |
| debugpy | Python |
| delve | Go |
| js-debug-adapter | JavaScript / TypeScript |
| bash-debug-adapter | Bash |

---

### Keybindings

> Press `<leader>?` to show all buffer-local keymaps via which-key.

#### General

| Key | Action |
|---|---|
| `jk` | Exit insert mode |
| `<C-h/j/k/l>` | Navigate windows / tmux panes |
| `J` / `K` (visual) | Move selection down / up |
| `<C-d>` / `<C-u>` | Scroll half page, keep cursor centred |
| `<leader>p` | Paste without yanking replaced text |
| `<leader>y` / `<leader>Y` | Yank to system clipboard |
| `<leader>X` | Delete without yanking |
| `<leader>s` | Search and replace word under cursor |
| `<leader>x` | Make current file executable |
| `<leader>Q` | Close all tool panels (DAP UI, diffview, neo-tree, undotree, fugitive) |
| `<leader>?` | Show buffer keymaps (which-key) |

#### File Explorer

| Key | Action |
|---|---|
| `<C-n>` | Toggle neo-tree |

#### Find — Telescope (`<leader>f`)

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

#### LSP (`<leader>k`)

| Key | Action |
|---|---|
| `<leader>kd` | Go to definition (Telescope) |
| `<leader>kD` | Go to declaration |
| `<leader>kr` | References (Telescope) |
| `<leader>ki` | Implementations (Telescope) |
| `<leader>kt` | Type definition (Telescope) |
| `<leader>ks` | Document symbols (Telescope) |
| `<leader>kS` | Workspace symbols (Telescope) |
| `<leader>ka` | Code action |
| `<leader>kn` | Rename symbol |
| `<leader>ke` | Buffer diagnostics (Telescope) |
| `<leader>kE` | Workspace diagnostics (Telescope) |
| `<leader>kl` | Line diagnostic float |
| `<leader>kk` | Hover |
| `<leader>kh` | Signature help |
| `<leader>kI` | LSP info |
| `<leader>kR` | Restart LSP |

#### Debug — DAP (`<leader>d`)

| Key | Action |
|---|---|
| `<leader>db` | Toggle breakpoint |
| `<leader>dB` | Conditional breakpoint |
| `<leader>dl` | Log point |
| `<leader>dc` | Continue / start session |
| `<leader>di` | Step into |
| `<leader>do` | Step over |
| `<leader>dO` | Step out |
| `<leader>dr` | Restart session |
| `<leader>dq` | Terminate session |
| `<leader>du` | Toggle DAP UI |
| `<leader>de` | Evaluate expression |

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

> Inside fugitive: `s` stage · `u` unstage · `cc` commit · `ca` amend · `dd` diff · `=` toggle inline diff · `g?` all keymaps

#### Git — hunks / gitsigns (`<leader>h`)

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
| `ih` | Text object: inner hunk (visual / operator) |

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

#### Undotree (`<leader>u`)

| Key | Action |
|---|---|
| `<leader>u` | Toggle undotree |

#### Format (`<leader>m`)

| Key | Action |
|---|---|
| `<leader>mp` | Format file or selection |

#### Linting

| Key | Action |
|---|---|
| `<leader>ll` | Trigger linting for current file |

#### Completion — blink.cmp

| Key | Action |
|---|---|
| `<C-space>` | Show menu / toggle docs |
| `<Tab>` | Next item / next snippet placeholder |
| `<S-Tab>` | Prev item / prev snippet placeholder |
| `<CR>` | Accept |
| `<C-e>` | Dismiss |
| `<C-k>` / `<C-j>` | Scroll docs up / down |

---

## Split Keyboard

Corne layout config and layer images: [split-keyboard/](split-keyboard/README.md)
