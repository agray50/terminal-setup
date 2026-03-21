# Custom Snippets

Snippets are loaded by blink.cmp alongside `friendly-snippets` and appear in the completion menu when you type a prefix.

## Adding a new snippet

Open the relevant `<filetype>.json` and add an entry:

```json
{
  "Snippet name": {
    "prefix": "trigger",
    "body": ["line one", "line two"],
    "description": "shown in completion docs"
  }
}
```

| Field         | Description                                      |
|---------------|--------------------------------------------------|
| `prefix`      | The text you type to trigger the snippet         |
| `body`        | Array of lines. Use `\t` for indentation         |
| `description` | Optional. Shown in the blink.cmp docs popup      |

## Body and new lines

The `body` is an array of strings — **each element is one line**. Neovim joins them with newlines when the snippet is inserted.

```json
"body": [
  "line one",
  "line two",
  "line three"
]
```

To insert a **blank line**, include an empty string in the array:

```json
"body": [
  "import foo",
  "",
  "foo.bar()"
]
```

Do not embed `\n` inside a string — use a new array element instead.

## Indentation

Use `\t` for a literal tab. Neovim will expand it according to the buffer's `expandtab`/`shiftwidth` settings:

```json
"body": [
  "if condition:",
  "\tdo_something()",
  "\t\tnested()"
]
```

Avoid hardcoding spaces for indentation — `\t` adapts to the file's settings.

## Tab stops

| Syntax            | Behaviour                                        |
|-------------------|--------------------------------------------------|
| `$1`, `$2`, ...   | Tab stops — `<Tab>` jumps between them in order  |
| `$0`              | Final cursor position after all tab stops        |
| `${1:placeholder}`| Tab stop with a default value (selected on jump) |
| `${1\|a,b,c\|}`  | Tab stop with a choice list                      |

- Numbering determines jump order, not position in the body
- Multiple occurrences of the same number (e.g. two `$1`) are **mirrors** — editing one updates all
- Always include `$0` to set where the cursor ends up

Example with tab stops:

```json
{
  "Function": {
    "prefix": "fn",
    "body": [
      "function ${1:name}(${2:args})",
      "\t${0:-- body}",
      "end"
    ]
  }
}
```

## Variables

VSCode snippet variables are supported and resolve at insertion time:

| Variable          | Value                                      |
|-------------------|--------------------------------------------|
| `$TM_FILENAME`    | Current filename (e.g. `main.go`)          |
| `$TM_FILENAME_BASE` | Filename without extension (`main`)      |
| `$TM_DIRECTORY`   | Directory of the current file              |
| `$TM_LINE_INDEX`  | Zero-based line number of the cursor       |
| `$CURRENT_YEAR`   | Four-digit year (e.g. `2026`)              |
| `$CURRENT_MONTH`  | Two-digit month (e.g. `03`)                |
| `$CURRENT_DATE`   | Two-digit day (e.g. `21`)                  |
| `$CLIPBOARD`      | Current clipboard contents                 |

Example — file header with date:

```json
{
  "File header": {
    "prefix": "header",
    "body": [
      "# $TM_FILENAME_BASE",
      "# Created: $CURRENT_YEAR-$CURRENT_MONTH-$CURRENT_DATE",
      ""
    ]
  }
}
```

## Multiple prefixes

A snippet can be triggered by more than one prefix using an array:

```json
{
  "Error check": {
    "prefix": ["iferr", "errc"],
    "body": ["if err != nil {", "\t${0:return err}", "}"]
  }
}
```

## Adding a new filetype

1. Create `<language>.json` with your snippets
2. Register it in `package.json`:

```json
{ "language": "rust", "path": "./rust.json" }
```

The `language` value must match Neovim's filetype name (`:set ft?` to check).

## Filetype names reference

| Language   | Neovim filetype |
|------------|-----------------|
| Bash/sh    | `sh`            |
| JavaScript | `javascript`    |
| TypeScript | `typescript`    |
| Go         | `go`            |
| Python     | `python`        |
| Lua        | `lua`           |
| YAML       | `yaml`          |
| Terraform  | `terraform`     |
| Markdown   | `markdown`      |
