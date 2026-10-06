#!/usr/bin/env python3
"""Check that every keybinding documented in README.md exists in the live config.

Reads:
  KEYS_FILE    newline-separated list of lhs strings dumped from a live nvim
  README_FILE  the README to check

Exits 1 and prints the offenders if the README documents a key that is not
mapped. This is the check that previously did not exist, which is how the README
came to document plugins and keys the config had already moved away from.
"""
import os
import re
import sys
import pathlib

keys_file = os.environ.get("KEYS_FILE")
readme_file = os.environ.get("README_FILE")
if not keys_file or not readme_file:
    sys.exit("KEYS_FILE and README_FILE must be set")


def normalise(k: str) -> str:
    """Put a key into one comparable form.

    nvim reports some keys differently from how a human writes them:
      - leader is a literal space, so '<leader>ff' arrives as ' ff'
      - '<C-\\>' arrives as '<C-Bslash>'
      - '<' arrives as '<lt>'
      - '<S-h>' is normalised by nvim to 'H'
    """
    k = k.replace("<C-Bslash>", "<C-\\>").replace("<lt>", "<")
    # The README spells a literal space as <space>; nvim reports the character.
    k = k.replace("<space>", " ").replace("<Space>", " ")
    if k.startswith(" "):
        k = "<leader>" + k[1:]
    # Shift-letter is reported as the capital letter.
    m = re.fullmatch(r"<[Ss]-([a-zA-Z])>", k)
    if m:
        k = m.group(1).upper()
    return k.lower()


live = set()
for line in pathlib.Path(keys_file).read_text().splitlines():
    if line:
        live.add(normalise(line))

readme = pathlib.Path(readme_file).read_text()

# Only look at table rows, and only at the first cell (the key column).
documented = set()
for row in re.findall(r"^\|(.+?)\|", readme, re.MULTILINE):
    # Match double-backtick spans first so a key containing a literal backtick
    # (e.g. <leader>b`, "last used buffer") survives intact.
    for key in re.findall(r"``\s*(.+?)\s*``", row):
        documented.add(key.replace("\\`", "`"))
    for key in re.findall(r"(?<!`)`([^`]+)`(?!`)", row):
        documented.add(key)

# Things that legitimately appear in a key column but are not nvim mappings.
SKIP_EXACT = {
    # Group prefixes, documented as groups rather than mappings.
    "<leader>", "<leader>f", "<leader>g", "<leader>gh", "<leader>c", "<leader>x",
    "<leader>d", "<leader>t", "<leader>b", "<leader>w", "<leader>u", "<leader>q",
    "<leader>s", "<leader>D",
    # blink.cmp has its own keymap table; these never reach nvim_get_keymap.
    "<C-b>", "<Tab>", "<S-Tab>", "<CR>", "<C-e>", "<C-k>", "<C-j>",
    # Conflict-resolution keys, mapped only inside a diffview buffer.
    "<leader>co", "ct", "cb", "ca", "cn", "s", "X", "R", "<tab>", "<s-tab>",
}
SKIP_PREFIX = ("prefix + ", "^", "./setup.sh", "git ", ":", "nvim/", "versions.lock")
# Cells that name a tool rather than a key. `rg` is "ripgrep (`rg`)" in the
# tool table, which happens to sit in a first column.
SKIP_EXACT |= {"rg", "fd", "bat", "eza", "jq", "yq", "k9s", "psql", "zsh", "tmux",
               "neovim", "lazygit", "fzf", "rustup", "nvm", "pyenv", "goenv",
               "SDKMAN", "tfenv", "prettierd", "stylua"}
# Multi-key shorthand like <C-h/j/k/l>, and non-key cells (tool names, settings).
SKIP_PATTERN = re.compile(
    r"^(<C-[a-z]/|<C-Up/|.*=.*|[a-z_]+\.[a-z]+.*|[a-z-]+ \[.*\]|"
    r"vtsls|eslint|tailwindcss|emmet|basedpyright|ruff|jdtls|gopls|terraformls|"
    r"tflint|bashls|jsonls|yamlls|helm_ls|cssls|docker_language_server|sqls|"
    r"taplo|marksman|lua_ls|rust_analyzer|graphql|delta|"
    r"ls|ll|la|lt|l2|cat|json|yaml|v|vi|lg|gs|gd|gds|gl|gco|gcb|gri|grc|gra|"
    r"ta|tl|tn|tk|tf|tfi|tfp|tfa|tfd|fh|fcd|fgb|fkill|frg|fshow|nf)$"
)

def expand(key: str) -> list[str]:
    """Expand README shorthand that names several keys in one cell.

    '<C-h/j/k/l>' means four mappings; '<C-Up/Down/Left/Right>' means four more.
    Returns the individual keys so each is checked on its own.
    """
    m = re.fullmatch(r"<([CSMA])-([A-Za-z]+(?:/[A-Za-z]+)+)>", key)
    if m:
        mod, parts = m.group(1), m.group(2).split("/")
        return [f"<{mod}-{p}>" for p in parts]
    return [key]


missing = []
for key in sorted(documented):
    if key in SKIP_EXACT or key.startswith(SKIP_PREFIX) or SKIP_PATTERN.match(key):
        continue
    if not all(normalise(k) in live for k in expand(key)):
        missing.append(key)

if missing:
    print(f"      {len(missing)} documented key(s) not found in the live config:")
    for key in missing:
        print(f"        {key}")
    sys.exit(1)
sys.exit(0)
