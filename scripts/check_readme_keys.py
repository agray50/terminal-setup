#!/usr/bin/env python3
"""Check README.md's keybinding tables against the live config, both ways.

Reads:
  KEYS_FILE    "lhs<TAB>desc<TAB>rhs" lines dumped from a live nvim
  README_FILE  the README to check

Fails (exit 1, offenders printed) when:
  1. the README documents a key that is not mapped;
  2. a <leader> key with a description is mapped but not documented;
  3. a documented key is mapped to something else: its description and its
     README row share no meaningful word.

Only (1) existed at first. It passed throughout while <C-\\> was broken,
because the key *was* mapped -- just to vim-tmux-navigator's "previous pane"
rather than the floating terminal the README promised -- and it could not
notice <leader>uN, which was mapped but documented nowhere.
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
    # Case matters for plain keys (<leader>dc and <leader>dC are different
    # mappings) but not inside <...> names (<C-h>, <c-H>, <CR>, <Tab>). This
    # used to lowercase everything, so a key and its shifted twin were one key.
    return re.sub(r"<[^<>]+>", lambda t: t.group(0).lower(), k)


live = {}   # normalised lhs -> (desc, rhs)
for line in pathlib.Path(keys_file).read_text().splitlines():
    if line:
        lhs, desc, rhs = (line.split("\t") + ["", ""])[:3]
        live.setdefault(normalise(lhs), (desc, rhs))

readme = pathlib.Path(readme_file).read_text()

# Only look at tables whose first column is actually "Key", and only at that
# first cell. Other tables in the README (troubleshooting symptoms, tool lists,
# config settings) also put backticked text in column one, and treating those as
# keybindings produced false failures like "command not found: goenv".
documented = {}   # key as written -> the row's description cell
in_key_table = False
for line in readme.split("\n"):
    stripped = line.strip()
    if not stripped.startswith("|"):
        in_key_table = False
        continue
    cells = [c.strip() for c in stripped.strip("|").split("|")]
    if not cells:
        continue
    # Header row: start collecting only if this table's first column is "Key".
    if cells[0] == "Key":
        in_key_table = True
        continue
    if set(cells[0]) <= set("-: "):   # the |---|---| separator row
        continue
    if not in_key_table:
        continue
    first, action = cells[0], " ".join(cells[1:])
    # Match double-backtick spans first so a key containing a literal backtick
    # (e.g. <leader>b`, "last used buffer") survives intact.
    for key in re.findall(r"``\s*(.+?)\s*``", first):
        documented[key.replace("\\`", "`")] = action
    for key in re.findall(r"(?<!`)`([^`]+)`(?!`)", first):
        documented[key] = action

# Things that legitimately appear in a key column but are not nvim mappings.
SKIP_EXACT = {
    # Group prefixes, documented as groups rather than mappings.
    "<leader>", "<leader>f", "<leader>g", "<leader>gh", "<leader>c", "<leader>x",
    "<leader>d", "<leader>t", "<leader>b", "<leader>w", "<leader>u", "<leader>q",
    "<leader>s", "<leader>D",
    # blink.cmp has its own keymap table; these never reach nvim_get_keymap.
    "<C-b>", "<Tab>", "<S-Tab>", "<CR>", "<C-e>", "<C-k>", "<C-j>",
    # Diffview-only keys, described in prose: conflict choices and file panel.
    # (Not <leader>co: the Code table documents it as organize imports, which
    # is what it is outside a diffview merge.)
    "ct", "cb", "ca", "cn", "s", "X", "R", "<tab>", "<s-tab>",
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

# Leader keys deliberately left out of the README.
UNDOCUMENTED_OK = set()

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


def words(text: str) -> set[str]:
    """Meaningful lowercase words, crudely stemmed so "toggles" meets "toggle"."""
    out = set()
    for w in re.findall(r"[a-z]{3,}", text.lower()):
        if w in STOPWORDS:
            continue
        out.add(w.removesuffix("s")[:5])
    return out


STOPWORDS = {"the", "and", "for", "with", "this", "that", "from", "into", "all",
             "any", "one", "its", "via", "not", "but", "under"}

problems = []
# Every documented key counts for the reverse check, including ones skipped
# below (`<leader>w=` is skipped as a "setting" by the `=` pattern).
documented_live = {normalise(k) for key in documented for k in expand(key)}
for key, action in sorted(documented.items()):
    if key in SKIP_EXACT or key.startswith(SKIP_PREFIX) or SKIP_PATTERN.match(key):
        continue
    keys = [normalise(k) for k in expand(key)]
    if not all(k in live for k in keys):
        problems.append(f"documented but not mapped: {key}")
        continue
    for k in keys:
        desc, rhs = live[k]
        what = desc or rhs   # a Lua-callback mapping with no desc has neither
        if what and not (words(what) & words(action)):
            problems.append(f"{key}: mapped to \"{what}\", README says \"{action}\"")

# Every leader key the config describes should be findable in the README.
for k, (desc, _) in sorted(live.items()):
    if k.startswith("<leader>") and desc and k not in documented_live and k not in UNDOCUMENTED_OK:
        problems.append(f"mapped but not documented: {k} ({desc})")

if problems:
    print(f"      {len(problems)} README/keymap mismatch(es):")
    for p in problems:
        print(f"        {p}")
    sys.exit(1)
sys.exit(0)
