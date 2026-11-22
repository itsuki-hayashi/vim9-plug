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
use vim-plug, replace that file and restart Vim. Keep your vimrc and
existing plugin directory.

```vim
call plug#begin()

Plug 'tpope/vim-sensible'

call plug#end()
```

The same declarations work in a Vim9 vimrc. Use `:PlugInstall` to install
plugins and `:PlugUpdate` to update them. See [Vim help](doc/plug.txt) for
the commands, declaration options, mappings, and hooks. To install the
help alongside the script, copy `doc/plug.txt` into the same runtime
directory under `doc/`, then run `:helptags ALL` and `:help plug`.

`:PlugUpgrade` updates the installed script from this repository and
keeps the previous file as `plug.vim.old`. For a Git-managed checkout,
use your usual Git update workflow. Neovim and the old Python and Ruby
installation backends are outside the support scope.

## Development

The reference submodules contain upstream vim-plug and Vim. Initialize
them and run the offline tests with Python 3 and Git.

```sh
git submodule update --init --recursive
python test/run.py
python test/run.py --vim /path/to/vim
```
