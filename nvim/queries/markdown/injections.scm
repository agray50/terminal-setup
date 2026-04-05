; Neovim 0.12 compatible markdown injection query.
; Replaces nvim-treesitter's version which uses #gsub! — a custom directive
; that breaks under Neovim 0.12's all=true match API (match[id] returns a
; table of nodes instead of a single TSNode, so node:range() fails).

((fenced_code_block
  (info_string
    (language) @injection.language)
  (code_fence_content) @injection.content)
 (#set! injection.include-children))

((html_block) @injection.content
 (#set! injection.language "html"))
