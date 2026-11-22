# Migrating to the Vim9 module

Replace the installed `autoload/plug.vim` and migrate the declaration block
before restarting Vim. Keep configuration globals such as `g:plug_home`
and `g:plug_threads`.

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

## Move to the native package layout

vim9-plug loads packages from `<plug-home>/pack/vim9-plug/opt/<name>`.
Remove `dir` overrides and run `:PlugInstall` after restarting Vim to
install Git plugins in the package tree. This leaves old checkouts in
place so you can review them for local changes before removing them.

To preserve a checkout and its local changes, close Vim and move the
entire checkout, including its Git metadata, to the new package path.
Use `git worktree move` for linked worktrees. The final directory name
is the repository name or the value of `as`.

Each package directory must be the plugin's runtime root. If you used
`rtp` to select a repository subdirectory, arrange for the subdirectory
to be installed as its own native package and remove the `rtp` option.

To declare a locally maintained plugin, place it in the package tree
with its native package name, then pass its directory to `plug.Add()`.

```vim
plug.Add(g:plug_home .. '/pack/vim9-plug/opt/my-plugin')
```

Use Vim's native package configuration directly for local packages you
keep in a different package group.

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
