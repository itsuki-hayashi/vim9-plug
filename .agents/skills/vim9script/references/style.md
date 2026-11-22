# Writing idiomatic Vim9 script

Use these defaults for new code when the project has no convention. In a maintained port, match the surrounding file and keep style-only changes out of upstream fixes. For grammar and supported features, use the target Vim's help. The two community guides provide style advice from different generations of the language. [Vim9 language reference](https://vimhelp.org/vim9.txt.html) · [Google's legacy Vimscript guide](https://google.github.io/styleguide/vimscriptguide.html) · [Dan Bradbury's Vim9 style guide](https://raw.githubusercontent.com/DanBradbury/vim9script-style-guide/refs/heads/main/README.md)

## A typed formatter

```vim
vim9script

export def WarningLocations(
    source_name: string,
    lines: list<string>,
): list<string>
  final locations: list<string> = []
  var line_number = 0
  for line in lines
    line_number += 1
    if line =~ '^\s*WARN:'
      locations->add($'{source_name}:{line_number}')
    endif
  endfor
  return locations
enddef

assert_equal(['build.log:2'], WarningLocations('build.log', [
  'warn: quoted output',
  '  WARN: missing header',
]))
```

The formatter accepts lines from any source, leaves the input list intact, and reports one-based line numbers. Its pattern recognizes a case-sensitive protocol marker. Keep example assertions like this in the test driver when shipping a plugin.

## Names and layout

- Choose domain names that reveal units or ownership where it matters, such as `timeout_ms`, `window_id`, or `pending_jobs`. Use snake_case for ordinary locals, parameters, fields, and new module filenames. Use an initial capital and word boundaries for named functions, methods, types, and commands, such as `ReadHTTPHeader()` or `LineAudit`. Give named Funcref bindings a capital too, as in `Accept: func(string): bool`. Constructors use `new()`, and a leading underscore has access semantics for class members. Existing command names, autoload paths, and configuration keys are caller contracts.
- Use two spaces per block in a new file. Keep line endings consistent with the repository (LF for a new portable script), omit trailing blanks, and use a blank line between definitions. Aim for roughly 80 columns when practical. Break at a parameter, a dictionary entry, or a logical operation. Give a multiline signature room for one parameter per line. Align by nesting depth so renaming one variable does not reformat its neighbors.
- Spacing can determine whether Vim parses an expression. Write `var total: number = 0`, `{count: total}`, `lines[1 : -1]`, and `Read(path)`. Keep spaces around binary operators and `=>`. Attach unary operators and member access to their operands. Keep Ex flags intact, as in `command -nargs=1`.
- Inside an unfinished expression, continue naturally across lines. A receiver and successive `->` calls can occupy separate lines. Some Ex commands parse the rest of the line as another command, especially `:command`, `:autocmd`, and `:windo`. Extract a named handler for a long body. Where the Ex parser still needs a leading backslash, retain it. Spell out Ex commands and options in maintained scripts, such as `setlocal shiftwidth=2`. [Vim9 continuation rules](https://vimhelp.org/vim9.txt.html#vim9-line-continuation)

## Expressions and control flow

- Use guard clauses for empty input, unsupported capabilities, or stale callback targets. Keep the main operation together. Use one statement per line, especially in conditionals and command handlers. A short ternary works for a single value choice. Use `if` / `elseif` for branches that have side effects or distinct failure handling.
- Let the direction of the data guide the call syntax. A short `->` chain reads well when each step transforms the preceding result. A direct call such as `setbufline(buf, 1, lines)` keeps an editor target visible. Split chains at mutations or type changes if a reader must trace who owns a collection. A loop suits early exits and accumulators. Give callbacks names when their signatures or branching deserve explanation.
- Use single quotes for literal text and regex patterns. In a single-quoted string, double an apostrophe to include it, as in `'can''t'`. Use double quotes for actual escapes such as `"\t"` or a keycode like `"\<Esc>"`. The pattern `'\s\+'` passes backslashes through to Vim's regex engine. Use `$'{path}:{line_number}'` when expressions are embedded in text. Doubled braces in an interpolated string produce literal braces. Simple joins such as `stem .. '.vim'` read well without interpolation.
- Use `==` for string contents and `is` to test identity where appropriate, such as checking whether two names refer to the same list. In Vim9 expressions, `==` and `=~` are case-sensitive by default, even under `'ignorecase'`. Use `==?` or `=~?` for deliberate case folding. For a literal substring, `stridx(text, needle) >= 0` also handles user input containing regex metacharacters.
- Choose a pattern for its consumer. Vim9 expression matches use magic syntax by default. A string transform such as `substitute('WARN', '\Cwarn', 'note', 'g')` explicitly fixes case for a built-in that otherwise honors `'ignorecase'`. Use `\v` when very-magic syntax makes a complex pattern clearer. For a user-facing search, decide whether the user's search settings are part of the feature. Test that choice with settings toggled. [Vim expressions](https://vimhelp.org/eval.txt.html) · [Built-in function reference](https://vimhelp.org/builtin.txt.html)

## Code that shares an editor

- Choose the narrowest operation. Use `substitute()` to transform a string, `search(pattern, 'nW')` to locate a match without moving the cursor or wrapping, and a buffer API for a targeted edit. When replaying built-in keystrokes is the intended operation, use `normal!` to bypass user mappings. Preserve any view, registers, search state, or options the command promises to leave intact.
- Give configuration an owner. Read a user setting with a default, such as `get(g:, 'lineaudit_limit', 50)`, and validate its type at that boundary. Filetype behavior belongs in buffer-local mappings and commands. Set local options via `&l:` or `setlocal`, and extend `b:undo_ftplugin` for changes that a filetype switch must undo.
- For plugin mappings, expose a named `<Plug>` action and respect existing user bindings when choosing defaults. Group autocommands by plugin ownership. Define a new user command with `command`. Re-sourcing its defining script can replace that definition. Reserve `command!` for intentional replacement of an existing command. [User commands and mappings](https://vimhelp.org/map.txt.html)
- Keep successful background events quiet. Report a failure at the boundary that can tell the user which operation failed. If a built-in failure is recoverable, catch its specific Vim error code, including the terminating colon (for example, E484 for a file open failure). Human-readable error text varies by locale. Use `finally` to restore temporary state. Let unexpected errors propagate with their original context.
- Write `# ` comments above the code they explain. Record an invariant, a compatibility reason, or why an event must be handled in this order. A useful FIXME names the failing condition. Keep public behavior discoverable in tagged Vim help under `doc/`, especially command arguments, configuration, mappings, and observable side effects. [Writing plugin help](https://vimhelp.org/usr_51.txt.html#write-local-help)

During review, follow one public operation from registration through its typed implementation. Check which settings can affect its result, which caller-owned values can change, and what happens if the defining script loads twice. Use the [porting guide](porting.md) for legacy entry points and the [language guide](language.md) for types and object design.
