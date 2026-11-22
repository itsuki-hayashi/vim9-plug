# Migrating to the Vim9 module

Replace the installed `autoload/plug.vim` and migrate the declaration block
before restarting Vim. Your plugin directories and configuration globals
such as `g:plug_home` and `g:plug_threads` can be reused.

New Git checkouts use Vim's native package layout under the same plugin
home at `pack/vim9-plug/opt/<name>`. Existing checkouts directly under the
plugin home and declarations with `dir` and `rtp` continue to work in place.

## Rewrite the declaration block

Before:

```vim
call plug#begin('~/.vim/plugged')
Plug 'tpope/vim-sensible'
Plug 'owner/plugin', 'v1.0'
Plug 'owner/other-plugin', {'on': 'OtherCommand', 'do': {info -> WriteLog(info)}}
call plug#end()
```

After:

```vim
vim9script

import autoload 'plug.vim' as plug

if plug.Begin('~/.vim/plugged')
  plug.Add('tpope/vim-sensible')
  plug.Add('owner/plugin', {tag: 'v1.0'})
  plug.Add('owner/other-plugin', {on: 'OtherCommand', do: (info) => WriteLog(info)})
  plug.End()
endif
```

`WriteLog` represents your own hook. Define it before the declaration
block or import it from your own module. Its input dictionary still
contains `name`, `status`, and `force`.

You can keep the rest of a legacy vimrc by putting the new declaration
block in a separate file. Make `vim9script` the first command in that file
and source it from the vimrc, for example `source ~/.vim/plugins.vim`.

## Update other calls and hooks

| Previous entry point | Vim9 module call |
| --- | --- |
| `call plug#begin(directory)` | `plug.Begin(directory)` |
| `:Plug` or `plug#(repo, opts)` | `plug.Add(repo, opts)` |
| `plug#end()` | `plug.End()` |
| `plug#load('one', 'two')` | `plug.Load(['one', 'two'])` |
| `plug#helptags()` | `plug.Helptags()` |
| `plug#shellescape(text, {'shell': 'cmd.exe', 'script': 0})` | `plug.ShellEscape(text, 'cmd.exe', false)` |

- `Begin()`, `Load()`, and `Helptags()` return booleans. Use `Add()` and
  `End()` as statements. Invalid `Add()` declarations throw an exception.
- Convert colon-prefixed hooks to Vim9 Ex syntax. For example,
  `{do: ':let g:ready = 1'}` becomes `{do: ':g:ready = 1'}`. Shell hooks
  still accept strings.
- Prefix ranges in custom window commands with a colon. For example,
  `g:plug_window = ':-tabnew'`.

Commands such as `:PlugInstall`, `:PlugUpdate`, and `:PlugSnapshot` still run
from the command line. Source a generated snapshot after loading your
plugin declarations. If a compiled function both initializes vim9-plug
and launches an install, use `execute 'PlugInstall --sync'` so Vim resolves
the command after `Begin()` registers it.
