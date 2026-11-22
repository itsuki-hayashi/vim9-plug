# Modules and behavior-preserving ports

Keep registration small. This example has two files on the plugin's runtimepath. The command takes the entire argument as one string, including spaces.

`plugin/lineaudit.vim`

```vim
vim9script

import autoload 'lineaudit.vim' as audit
command -nargs=1 AuditCount echo audit.Count(getline(1, '$'), <q-args>)
```

`autoload/lineaudit.vim`

```vim
vim9script

export def Count(lines: list<string>, needle: string): number
  var matches = 0
  for line in lines
    if stridx(line, needle) >= 0
      matches += 1
    endif
  endfor
  return matches
enddef
```

A Vim9 caller uses the imported namespace. A legacy caller can use `lineaudit#Count(lines, needle)` because the autoload name derives from the filename and the exported name. Case matters. If an existing API is spelled differently, preserve its exact spelling with a compatible wrapper. Keep globals explicit with `g:`. Top-level unprefixed definitions belong to the script.

Use ordinary `import './sibling.vim' as sibling` for an eager dependency relative to the importing file. A bare ordinary import searches runtimepath's `import/` directories. A bare autoload import searches `autoload/` and delays execution until use. A deferred function's signature can be checked late. Test both the first invocation in a fresh process and subsequent calls. Use `<ScriptCmd>` in a mapping that needs the defining script's namespace, for example `nnoremap <silent> <Plug>(lineaudit-count) <ScriptCmd>echo audit.Count(getline(1, '$'), 'TODO')<CR>`.

## Port in reviewable units

1. Inventory the legacy surface. Include autoload functions, commands and their flags, mapping modes and return values, autocommands, option callbacks, configuration globals, and any documented dictionary shape. Capture behavior from each significant entry point before changing its implementation.
2. Move one coherent operation at a time. A legacy script can contain a compiled `def` alongside existing `function!` definitions. Its body uses Vim9 rules. Check script-local references in that mixed context. Use a small legacy adapter for argument normalization, a `dict` method's `self`, or a public `range` function. Pass the receiver or first and last lines explicitly to typed internals. Add `vim9script` to a whole file once its top-level commands and callback expressions are ready.
3. For a tracked upstream, record the baseline revision in the project's existing tracking mechanism. At each update, inspect the upstream change in terms of affected behavior, carry across its fixes and regression cases, and rerun the public scenarios. Keep intentional divergences identifiable in review.

| Legacy construct | Porting decision |
| --- | --- |
| `let`, `a:name`, `l:name`, `s:name` | Declare with `var`, `final`, or `const`, then assign directly. Use bare parameters, locals, and module names in a Vim9 module. Retain meaningful `b:`, `w:`, `t:`, `g:`, `v:`, option, and register scopes. |
| `a:0`, `a:000`, positional optional arguments | Choose typed defaults or a typed varargs list. Preserve the difference between omission and an explicitly supplied empty value when callers observe it. |
| String concatenation with `.`, double-quote comments, `call F()` | Use `..`, `#`, and direct calls. Keep quotes that delimit actual strings. Inspect continuation lines and command-specific comment rules before mechanical replacement. |
| Computed dictionary keys or variable names | In a literal, `{name: value}` uses the literal key `name`. Use `{[name]: value}` for an expression key. Index a dictionary explicitly for dynamic lookup. |
| Truthiness, mixed comparisons, `&ignorecase` | Write the intended predicate, such as `!empty(text)`, `index(xs, x) >= 0`, or `status == 0`. Vim9 string comparisons default to case-sensitive. Use `==?` or `=~?` for case-insensitive matching. Check callers passing numeric flags, string numerals, missing keys, or nulls. |
| `map(xs, '...v:val...')` and dictionary methods | Convert expressions to callbacks with the API's actual parameters. Preserve whether the caller sees in-place mutation. Keep dictionary receivers at the boundary if callers inspect, extend, or replace members. |
| Ex ranges, command placeholders, generated commands | Prefix a literal command range with a colon, e.g. `:%s/foo/bar/g`. Preserve `<line1>`, `<line2>`, `<bang>0`, `<q-args>` versus `<f-args>`, and completion semantics. Use `fnameescape()` when inserting a path into an Ex filename argument. |
| Missing values, errors, and cleanup | Preserve sentinels and thrown/reported errors where public. Use `try` / `finally` for temporary options, views, or directories. Exercise early returns and failures after partial setup. |
| Save, reset, and restore `'cpoptions'` around a sourced plugin | An ordinary sourced `vim9script` plugin gets Vim's default parsing flags while sourcing. Drop legacy boilerplate that existed solely to obtain those defaults. Preserve deliberate option changes and check the separate startup-vimrc rules before porting a configuration file. |

### Compilation changes control flow

An ordinary runtime guard can leave both branches subject to compilation. For an optional built-in in a compiled function, a literal test such as `if exists_compiled('*luaeval')` lets Vim omit the unavailable branch. Its answer is fixed when that function compiles. For an optional plugin that can load later, resolve its callable at invocation time. A port that retains an `exists()` test on a compiled local or argument will get zero. Represent “supplied” with a parameter default, a deliberate sentinel, or a dictionary key as the original contract requires.

Vim9 locals have block scope. Declare the result in the enclosing scope if several branches assign it and later code reads it. For optional parameters with defaults, passing `v:none` selects the default. If the old caller used `v:none` as data, account for that before adopting a defaulted signature. In a `def`, errors already abort the call. Reassess any legacy path that depended on executing the next line after an error.

## Editor lifetime

On ordinary re-source, Vim9 clears the script's local definitions and variables. Commands, mappings, registered autocommands, timers, and running jobs have their own lifetimes. Make registrations repeatable where reload is supported. Scope `autocmd!` to the plugin's own augroup and preserve buffer-local teardown. Stop or transfer work before discarding its owner. Use `vim9script noclear` only when intentionally retaining definitions and state, with explicit handling for repeated initialization.

For differential tests, use fresh buffers and the same options, fixtures, and arguments on both sides. Depending on the public feature, compare returned values and types, text, cursor/view, quickfix entries, emitted messages, and caller-owned data after the call. Include spaces in paths or arguments, empty input, repeated sourcing, and errors when they affect the original behavior. See the [Vim9 differences and interoperability reference](https://vimhelp.org/vim9.txt.html).
