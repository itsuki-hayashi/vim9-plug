# vim9-plug

A Vim9 script port of [vim-plug 0.15.0](https://github.com/junegunn/vim-plug/tree/0.15.0).
It requires Vim 9.1 or later with Vim9 script support, and Git. Vim builds
with jobs and channels install and update in parallel. Other supported
Vim builds run those operations serially.

## Install or migrate

Download [autoload/plug.vim](https://raw.githubusercontent.com/itsuki-hayashi/vim9-plug/master/autoload/plug.vim)
and put it in the first user directory on your runtimepath, under
`autoload/plug.vim`. Common locations are `~/.vim/autoload/plug.vim`
on Unix and `$HOME/vimfiles/autoload/plug.vim` on Windows. If you already
use vim-plug or an earlier vim9-plug, see the [migration guide](doc/migration.md).

In a Vim9 configuration:

```vim
vim9script

import autoload 'plug.vim' as plug

if plug.Begin()
  plug.Add('tpope/vim-sensible')
  plug.End()
endif
```

Use `:PlugInstall` to install plugins and `:PlugUpdate` to update them. See
[Vim help](doc/plug.txt) for the exported API, commands, options, and hooks.
To install the help alongside the script, copy `doc/plug.txt` into the same runtime
directory under `doc/`, then run `:helptags ALL` and `:help plug`.

`:PlugUpgrade` updates the installed script from this repository and
keeps the previous file as `plug.vim.old`. For a Git-managed checkout,
use your usual Git update workflow. Neovim and the old Python and Ruby
installation backends are outside the support scope.

## Plugin layout

Git checkouts go under `<plug-home>/pack/vim9-plug/opt/<name>`, and
vim9-plug adds the plugin home to Vim's `packpath`. The default plugin
home is `plugged` under the first `runtimepath` entry. Set `g:plug_home`
or pass a directory to `plug.Begin()` to choose another home.

`plug.End()` registers eager packages with Vim during startup, and
lazy packages are activated on demand. Keeping both under `opt` lets
you remove a declaration or change when it loads without moving the
checkout. Vim determines where the package and its `after/` directory
appear on `runtimepath`.
[Vim's native package documentation](https://vimhelp.org/repeat.txt.html#packages)

To upgrade from a flat installation, update your declarations and run
`:PlugInstall` to populate the package tree. For local plugins or a
checkout you want to keep, follow the [migration guide](doc/migration.md#move-to-the-native-package-layout).

## Development

The reference submodules contain upstream vim-plug, Vim, and minpac
v3.1.0. Initialize them and run the offline tests with Python 3 and Git.

```sh
git submodule update --init --recursive
python test/run.py
python test/run.py --vim /path/to/vim
```
