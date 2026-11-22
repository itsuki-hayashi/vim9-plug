vim9script noclear

# vim9-plug, based on vim-plug 0.15.0 (4c4e56b).
# Copyright (c) 2024 Junegunn Choi
#
# MIT License
#
# Permission is hereby granted, free of charge, to any person obtaining
# a copy of this software and associated documentation files (the
# "Software"), to deal in the Software without restriction, including
# without limitation the rights to use, copy, modify, merge, publish,
# distribute, sublicense, and/or sell copies of the Software, and to
# permit persons to whom the Software is furnished to do so, subject to
# the following conditions:
#
# The above copyright notice and this permission notice shall be
# included in all copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND,
# EXPRESS OR IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF
# MERCHANTABILITY, FITNESS FOR A PARTICULAR PURPOSE AND
# NONINFRINGEMENT. IN NO EVENT SHALL THE AUTHORS OR COPYRIGHT HOLDERS BE
# LIABLE FOR ANY CLAIM, DAMAGES OR OTHER LIABILITY, WHETHER IN AN ACTION
# OF CONTRACT, TORT OR OTHERWISE, ARISING FROM, OUT OF OR IN CONNECTION
# WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE SOFTWARE.

if exists('g:loaded_plug')
  finish
endif

const is_win = has('win32')
const upgrade_origin = 'https://github.com/itsuki-hayashi/vim9-plug.git'
const use_jobs = has('job') && has('channel')
const TYPE = {string: v:t_string, list: v:t_list, dict: v:t_dict, funcref: v:t_func}
const base_spec: dict<any> = {branch: '', frozen: 0}
var loaded: dict<number> = exists('loaded') ? loaded : {}
var triggers: dict<dict<list<string>>> = exists('triggers') ? triggers : {}
var plug_buf = exists('plug_buf') ? plug_buf : -1
var shell_error = 0
var codepage = 0
var git_version: list<number> = []
var first_rtp = ''
var last_rtp = ''
var prtp = exists('prtp') ? prtp : ''
var middle = exists('middle') ? middle : ''
var rtp_reset = exists('rtp_reset') ? rtp_reset : true
var clean_count = 0
var update_state: dict<any> = {}
var jobs: dict<dict<any>> = {}
var clone_opt: list<string> = []
var submodule_opts: list<string> = []
var pumping = false
var plug_file = ''

# Scope the option change to path handling on Windows.
def PlugCall(Callable: string, ...args: list<any>): any
  if is_win && &shellslash
    set noshellslash
    try
      return call(Callable, args)
    finally
      set shellslash
    endtry
  endif
  return call(Callable, args)
enddef

def Path(path: string): string
  return Trim(is_win ? substitute(path, '/', '\', 'g') : path)
enddef

def Dirpath(path: string): string
  return is_win ? Path(path) .. '\' : substitute(path, '[/\\]*$', '/', '')
enddef

def IsLocalPlug(repo: string): bool
  return is_win ? repo =~? '^[a-z]:\|^[%~]' : repo[0] =~ '[/$~]'
enddef

# Legacy vimrc values can use numeric strings for flags.
def Enabled(value: any): bool
  return type(value) == v:t_string ? str2nr(value) != 0 : !empty(value)
enddef

# Preserve the legacy function names and the expression and range syntax.
legacy function! plug#begin(...)
  return call('s:Begin', a:000)
endfunction

legacy function! plug#end()
  return s:End()
endfunction

legacy function! plug#(repo, ...)
  return call('s:Declare', [a:repo] + a:000)
endfunction

legacy function! plug#load(...)
  return call('s:Load', a:000)
endfunction

legacy function! plug#helptags()
  return s:Helptags()
endfunction

legacy function! plug#shellescape(arg, ...)
  return call('s:Shellescape', [a:arg] + a:000)
endfunction

legacy function! s:DefinePlug()
  command! -nargs=+ -bar Plug call plug#(<args>)
endfunction

legacy function! s:StatusUpdateRange() range
  call s:StatusUpdate(a:firstline, a:lastline)
endfunction

legacy function! s:DeleteOpAdapter(type, ...)
  call call('s:DeleteOp', [a:type] + a:000)
endfunction

def RegisterCommands()
  DefinePlug()
  if !executable('git')
    Err('`git` executable not found. Most commands will not be available.'
      .. ' To suppress this message, prepend ' .. '`silent!` to ' .. '`call plug#begin(...)`.')
    return
  endif
  if is_win && &shellslash && (&shell =~ 'cmd\(\.exe\)\?$' || IsPowershell(&shell))
    Err($'vim-plug does not support shell, {&shell}, when shellslash is set.')
    return
  endif
  command! -nargs=* -bar -bang -complete=customlist,s:Names PlugInstall Install(<bang>0 ? 1 : 0, [<f-args>])
  command! -nargs=* -bar -bang -complete=customlist,s:Names PlugUpdate Update(<bang>0 ? 1 : 0, [<f-args>])
  command! -nargs=0 -bar -bang PlugClean Clean(<bang>0 ? 1 : 0)
  command! -nargs=0 -bar PlugUpgrade if StageUpgrade() | try | unlet g:loaded_plug | execute 'source' fnameescape(plug_file) | echo 'vim9-plug has been upgraded' | catch | RollbackUpgrade(v:exception) | execute 'source' fnameescape(plug_file) | endtry | endif
  command! -nargs=0 -bar PlugStatus Status()
  command! -nargs=0 -bar PlugDiff Diff()
  command! -nargs=? -bar -bang -complete=file PlugSnapshot Snapshot(<bang>0 ? 1 : 0, <f-args>)
enddef

def IsPowershell(shell: string): bool
  return shell =~# 'powershell\(\.exe\)\?$' || shell =~# 'pwsh\(\.exe\)\?$'
enddef

def Isabsolute(dir: string): bool
  return dir =~# '^/' || (has('win32') && dir =~? '^\%(\\\|[A-Z]:\)')
enddef

def GitDir(dir: string): string
  var gitdir = Trim(dir) .. '/.git'
  if isdirectory(gitdir)
    return gitdir
  endif
  if !filereadable(gitdir)
    return ''
  endif
  gitdir = matchstr(get(readfile(gitdir), 0, ''), '^gitdir: \zs.*')
  if !empty(gitdir) && !Isabsolute(gitdir)
    gitdir = dir .. '/' .. gitdir
  endif
  return isdirectory(gitdir) ? gitdir : ''
enddef

def GitOriginUrl(dir: string): string
  var gitdir = GitDir(dir)
  var config = gitdir .. '/config'
  if empty(gitdir) || !filereadable(config)
    return ''
  endif
  return matchstr(join(readfile(config)), '\[remote "origin"\].\{-}url\s*=\s*\zs\S*\ze')
enddef

def GitRevision(dir: string): string
  var gitdir = GitDir(dir)
  var head = gitdir .. '/HEAD'
  if empty(gitdir) || !filereadable(head)
    return ''
  endif

  var line = get(readfile(head), 0, '')
  var ref = matchstr(line, '^ref: \zs.*')
  if empty(ref)
    return line
  endif

  if filereadable(gitdir .. '/' .. ref)
    return get(readfile(gitdir .. '/' .. ref), 0, '')
  endif

  if filereadable(gitdir .. '/packed-refs')
    for packed_ref in readfile(gitdir .. '/packed-refs')
      if packed_ref =~# ' ' .. ref
        return matchstr(packed_ref, '^[0-9a-f]*')
      endif
    endfor
  endif

  return ''
enddef

def GitLocalBranch(dir: string): string
  var gitdir = GitDir(dir)
  var head = gitdir .. '/HEAD'
  if empty(gitdir) || !filereadable(head)
    return ''
  endif
  var branch = matchstr(get(readfile(head), 0, ''), '^ref: refs/heads/\zs.*')
  return !empty(branch) ? branch : 'HEAD'
enddef

def GitOriginBranch(spec: dict<any>): string
  if !empty(spec.branch)
    return spec.branch
  endif

  # The file may not be present if this is a local repository
  var gitdir = GitDir(spec.dir)
  var origin_head = gitdir .. '/refs/remotes/origin/HEAD'
  if !empty(gitdir) && filereadable(origin_head)
    return matchstr(get(readfile(origin_head), 0, ''),
                      '^ref: refs/remotes/origin/\zs.*')
  endif

  # The command may not return the name of a branch in detached HEAD state
  var result = Lines(System(['git', 'symbolic-ref', '--short', 'HEAD'], spec.dir))
  return shell_error != 0 ? '' : result[-1]
enddef

def GetWorkingDirectory(): string
  return PlugCall('getcwd')
enddef

def ModifyFilename(fname: string, mods: string): string
  return PlugCall('fnamemodify', fname, mods)
enddef

def ExpandFilename(fmt: string): string
  return PlugCall('expand', fmt, 1)
enddef

def TempName(): string
  return PlugCall('tempname')
enddef

def Begin(...args: list<any>): number
  var home: string
  if len(args) > 0
    home = Path(ModifyFilename(ExpandFilename(args[0]), ':p'))
  elseif exists('g:plug_home')
    home = Path(g:plug_home)
  elseif !empty(&rtp)
    home = Path(split(&rtp, ',')[0]) .. '/plugged'
  else
    return Err('Unable to determine plug home. Try calling plug#begin() with a path argument.')
  endif
  if ModifyFilename(home, ':t') ==# 'plugin' && ModifyFilename(home, ':h') ==# first_rtp
    return Err('Invalid plug home. ' .. home .. ' is a standard Vim runtime path and is not allowed.')
  endif

  JobAbort(false)
  g:plug_home = home
  g:plugs = {}
  g:plugs_order = []
  for name in keys(triggers)
    RemoveTriggers(name)
  endfor

  RegisterCommands()
  return 1
enddef

def ToA(v: any): list<any>
  return type(v) == TYPE.list ? v : [v]
enddef

def Glob(from: string, pattern: string): list<string>
  return globpath(escape(from, ','), pattern, false, true)
enddef

def Source(from: string, ...args: list<string>): number
  var found = 0
  for pattern in args
    for vim in Glob(from, pattern)
      execute 'source' fnameescape(vim)
      found = 1
    endfor
  endfor
  return found
enddef

def Assoc(dict: dict<any>, key: string, val: string)
  dict[key] = add(get(dict, key, []), val)
enddef

def Ask(message: string, ...args: list<any>): number
  inputsave()
  echohl WarningMsg
  var answer: string
  try
    answer = input(message .. (!empty(args) ? ' (y/N/a) ' : ' (y/N) '))
  finally
    echohl None
    inputrestore()
  endtry
  echo "\r"
  return (!empty(args) && answer =~? '^a') ? 2 : (answer =~? '^y') ? 1 : 0
enddef

def AskNoInterrupt(message: string): number
  try
    return Ask(message)
  catch
    return 0
  endtry
enddef

def Lazy(plug: dict<any>, opt: string): bool
  return has_key(plug, opt) &&
            (empty(ToA(plug[opt]))         ||
            !isdirectory(plug.dir)             ||
            len(Glob(PluginRuntimePath(plug), 'plugin')) ||
            len(Glob(PluginRuntimePath(plug), 'after/plugin')))
enddef

def End(): number
  if !exists('g:plugs')
    return Err('plug#end() called without calling plug#begin() first')
  endif

  if exists('#PlugLOD')
    augroup PlugLOD
      autocmd!
    augroup END
    augroup! PlugLOD
  endif
  var lod = { 'ft': {}, 'map': {}, 'cmd': {} }

  if get(g:, 'did_load_filetypes', 0)
    filetype off
  endif
  for name in g:plugs_order
    if !has_key(g:plugs, name)
      continue
    endif
    var plug = g:plugs[name]
    if get(loaded, name, 0) || !Lazy(plug, 'on') && !Lazy(plug, 'for')
      loaded[name] = 1
      continue
    endif

    if has_key(plug, 'on')
      triggers[name] = { 'map': [], 'cmd': [] }
      for cmd in ToA(plug.on)
        if cmd =~? '^<Plug>.\+'
          if empty(mapcheck(cmd)) && empty(mapcheck(cmd, 'i'))
            Assoc(lod.map, cmd, name)
          endif
          add(triggers[name].map, cmd)
        elseif cmd =~# '^[A-Z]'
          final command_name = substitute(cmd, '!*$', '', '')
          if exists(':' .. command_name) != 2
            Assoc(lod.cmd, command_name, name)
          endif
          add(triggers[name].cmd, command_name)
        else
          Err('Invalid `on` option: ' .. cmd ..
              '. Should start with an uppercase letter or `<Plug>`.')
        endif
      endfor
    endif

    if has_key(plug, 'for')
      var types = ToA(plug.for)
      if !empty(types)
        augroup filetypedetect
        Source(PluginRuntimePath(plug), 'ftdetect/**/*.vim', 'after/ftdetect/**/*.vim')
        augroup END
      endif
      for type in types
        Assoc(lod.ft, type, name)
      endfor
    endif
  endfor

  for [cmd, names] in items(lod.cmd)
    execute printf(
          'command! -nargs=* -range -bang -complete=file %s call LodCmd(%s, "<bang>", <line1>, <line2>, <q-args>, <q-mods>, %s)',
          cmd, string(cmd), string(names))
  endfor

  for [map, names] in items(lod.map)
    for [mode, map_prefix, key_prefix] in
              [['i', '<C-\><C-O>', ''], ['n', '', ''], ['v', '', 'gv'], ['o', '', '']]
      execute printf(
          '%snoremap <silent> %s %s:<C-U>call <SID>LodMap(%s, %s, %s, "%s")<CR>',
          mode, map, map_prefix, string(map), string(names), mode == 'i' ? 'v:false' : 'v:true', key_prefix)
    endfor
  endfor

  for [ft, names] in items(lod.ft)
    augroup PlugLOD
      execute printf('autocmd FileType %s LodFt(%s, %s)',
                ft, string(ft), string(names))
    augroup END
  endfor

  ReorgRtp()
  filetype plugin indent on
  if has('vim_starting')
    if has('syntax') && !exists('g:syntax_on')
      syntax enable
    endif
  else
    ReloadPlugins()
  endif
  return 0
enddef

def LoadedNames(): list<string>
  return filter(copy(g:plugs_order), (_, name) => !!get(loaded, name, 0))
enddef

def LoadPlugin(spec: dict<any>)
  Source(PluginRuntimePath(spec), 'plugin/**/*.vim', 'after/plugin/**/*.vim')
enddef

def ReloadPlugins()
  for name in LoadedNames()
    LoadPlugin(g:plugs[name])
  endfor
enddef

def Trim(str: string): string
  return substitute(str, '[\/]\+$', '', '')
enddef

def VersionRequirement(val: list<number>, min: list<number>): number
  for idx in range(0, len(min) - 1)
    var v = get(val, idx, 0)
    if     v < min[idx] | return 0
    elseif v > min[idx] | return 1
    endif
  endfor
  return 1
enddef

def GitVersionRequirement(...args: list<number>): number
  if empty(git_version)
    final version = matchstr(System(['git', '--version']), '\d\+\(\.\d\+\)\+')
    git_version = mapnew(split(version, '\.'), (_, part) => str2nr(part))
    if empty(git_version)
      return 0
    endif
  endif
  return VersionRequirement(git_version, args)
enddef

def ProgressOpt(base: bool): string
  return base && !is_win &&
            GitVersionRequirement(1, 7, 1) ? '--progress' : ''
enddef

def PluginRuntimePath(spec: dict<any>): string
  return Path(spec.dir .. get(spec, 'rtp', ''))
enddef

  # Copied from fzf

def WrapCmds(cmds: any): list<string>
  var wrapped = [
        '@echo off',
        'setlocal enabledelayedexpansion']
      + (type(cmds) == type([]) ? cmds : [cmds])
      + ['endlocal']
  if exists_compiled('*libcallnr')
    if has('iconv')
      if codepage == 0
        codepage = libcallnr('kernel32.dll', 'GetACP', 0)
      endif
      return map(wrapped, (_, line) => iconv(line .. "\r", &encoding, printf("cp%d", codepage)))
    endif
  endif
  return map(wrapped, (_, line) => line .. "\r")
enddef

def Batchfile(cmd: string): list<string>
  var batchfile = TempName() .. '.bat'
  writefile(WrapCmds(cmd), batchfile)
  var run_cmd = Shellescape(batchfile, {'shell': &shell, 'script': 0})
  if IsPowershell(&shell)
    run_cmd = '& ' .. run_cmd
  endif
  return [batchfile, run_cmd]
enddef

def Err(msg: string): number
  echohl ErrorMsg
  echom '[vim-plug] ' .. msg
  echohl None
  return 0
enddef

def Warn(cmd: string, msg: string): number
  echohl WarningMsg
  execute cmd string(msg)
  echohl None
  return 0
enddef

def EscapeRuntimePath(path: string): string
  return escape(path, ' ,')
enddef

def RemoveRtp()
  for name in LoadedNames()
    var rtp = PluginRuntimePath(g:plugs[name])
    execute 'set rtp-=' .. EscapeRuntimePath(rtp)
    var after = globpath(escape(rtp, ','), 'after')
    if isdirectory(after)
      execute 'set rtp-=' .. EscapeRuntimePath(after)
    endif
  endfor
enddef

def ReorgRtp()
  if !empty(first_rtp)
    execute 'set rtp-=' .. first_rtp
    execute 'set rtp-=' .. last_rtp
  endif

  # &rtp is modified from outside
  if !rtp_reset && prtp !=# &rtp
    RemoveRtp()
    rtp_reset = true
  endif

  middle = rtp_reset ? &rtp : middle
  rtp_reset = false
  var rtps     = map(LoadedNames(), (_, name) => PluginRuntimePath(g:plugs[name]))
  var afters   = map(filter(copy(rtps), (_, dir) => isdirectory(dir .. '/after')), (_, dir) => Path(dir .. '/after'))
  var rtp      = join(map(rtps, (_, dir) => escape(dir, ',')), ',')
                     .. ',' .. middle .. ','
                     .. join(map(afters, (_, dir) => escape(dir, ',')), ',')
  &rtp     = substitute(substitute(rtp, ',,*', ',', 'g'), '^,\|,$', '', 'g')
  prtp   = &rtp

  if !empty(first_rtp)
    execute 'set rtp^=' .. first_rtp
    execute 'set rtp+=' .. last_rtp
  endif
enddef

def Doautocmd(...args: list<string>)
  if exists('#' .. join(args, '#'))
    execute 'doautocmd' '<nomodeline>' join(args)
  endif
enddef

def Dobufread(names: list<string>)
  # Nothing to detect in an unnamed empty buffer, e.g. the one on startup
  if empty(bufname('%')) && line('$') == 1 && empty(getline(1))
    return
  endif
  for name in names
    var path = PluginRuntimePath(g:plugs[name])
    for dir in ['ftdetect', 'ftplugin', 'after/ftdetect', 'after/ftplugin']
      if isdirectory(path .. '/' .. dir)
        if exists('#BufRead')
          doautocmd BufRead
        endif
        return
      endif
    endfor
  endfor
enddef

def Load(...args: list<any>): number
  if len(args) == 0
    return Err('Argument missing: plugin name(s) required')
  endif
  if !exists('g:plugs')
    return Err('plug#begin was not called')
  endif
  var names = len(args) == 1 && type(args[0]) == TYPE.list ? args[0] : args
  var unknowns = filter(copy(names), (_, name) => !has_key(g:plugs, name))
  if !empty(unknowns)
    var s = len(unknowns) > 1 ? 's' : ''
    return Err(printf('Unknown plugin%s: %s', s, join(unknowns, ', ')))
  endif
  var unloaded = filter(copy(names), (_, name) => !get(loaded, name, 0))
  if !empty(unloaded)
    for name in unloaded
      Lod([name], ['ftdetect', 'after/ftdetect', 'plugin', 'after/plugin'])
    endfor
    Dobufread(unloaded)
    return 1
  endif
  return 0
enddef

def RemoveTriggers(name: string)
  if !has_key(triggers, name)
    return
  endif
  for cmd in triggers[name].cmd
    execute 'silent! delc' cmd
  endfor
  for map in triggers[name].map
    execute 'silent! unmap' map
    execute 'silent! iunmap' map
  endfor
  remove(triggers, name)
enddef

def Lod(names: list<string>, types: list<string>, ...args: list<string>)
  for name in names
    RemoveTriggers(name)
    loaded[name] = 1
  endfor
  ReorgRtp()

  for name in names
    var rtp = PluginRuntimePath(g:plugs[name])
    for dir in types
      Source(rtp, dir .. '/**/*.vim')
    endfor
    if !empty(args)
      if !Source(rtp, args[0]) && !empty(Glob(rtp, args[1]))
        execute 'runtime' args[0]
      endif
      Source(rtp, args[1])
    endif
    Doautocmd('User', name)
  endfor
enddef

def LodFt(pat: string, names: list<string>)
  var syn = 'syntax/' .. pat .. '.vim'
  Lod(names, ['plugin', 'after/plugin'], syn, 'after/' .. syn)
  execute 'autocmd! PlugLOD FileType' pat
  Doautocmd('filetypeplugin', 'FileType')
  Doautocmd('filetypeindent', 'FileType')
enddef

def LodCmd(cmd: string, bang: string, l1: number, l2: number, args: string, mods: string, names: list<string>)
  Lod(names, ['ftdetect', 'after/ftdetect', 'plugin', 'after/plugin'])
  Dobufread(names)
  execute printf('legacy %s %s%s%s %s', mods, (l1 == l2 ? '' : (l1 .. ',' .. l2)), cmd, bang, args)
enddef

def LodMap(map: string, names: list<string>, with_prefix: bool, prefix: string)
  Lod(names, ['ftdetect', 'after/ftdetect', 'plugin', 'after/plugin'])
  Dobufread(names)
  var extra = ''
  while true
    final key = getcharstr(0)
    if empty(key) || key == "\<Ignore>"
      break
    endif
    extra ..= key
    # In Ex mode, reading again at EOF yields Escape indefinitely.
    if key == "\<Esc>"
      break
    endif
  endwhile

  if with_prefix
    var replay_prefix = v:count > 0 ? string(v:count) : ''
    replay_prefix ..= '"' .. v:register .. prefix
    if mode(1) == 'no'
      if v:operator == 'c'
        replay_prefix = "\<esc>" .. replay_prefix
      endif
      replay_prefix ..= v:operator
    endif
    feedkeys(replay_prefix, 'n')
  endif
  feedkeys(substitute(map, '^<Plug>', "\<Plug>", '') .. extra)
enddef

def Declare(repo_arg: any, ...args: list<any>): number
  if len(args) > 1
    return Err('Invalid number of arguments (1..2)')
  endif

  var repo = ''
  try
    repo = Trim(repo_arg)
    var opts = len(args) == 1 ? ParseOptions(args[0]) : base_spec
    var name = get(opts, 'as', ModifyFilename(repo, ':t:s?\.git$??'))
    var spec = extend(InferProperties(name, repo), opts)
    if !has_key(g:plugs, name)
      add(g:plugs_order, name)
    endif
    g:plugs[name] = spec
    loaded[name] = get(loaded, name, 0)
  catch
    return Err(repo .. ' ' .. v:exception)
  endtry
  return 0
enddef

def ParseOptions(arg: any): dict<any>
  var opts = copy(base_spec)
  var type = type(arg)
  var opt_errfmt = 'Invalid argument for "%s" option of :Plug (expected: %s)'
  if type == TYPE.string
    if empty(arg)
      throw printf(opt_errfmt, 'tag', 'string')
    endif
    opts.tag = arg
  elseif type == TYPE.dict
    for opt in ['branch', 'tag', 'commit', 'rtp', 'dir', 'as']
      if has_key(arg, opt)
          && (type(arg[opt]) != TYPE.string || empty(arg[opt]))
        throw printf(opt_errfmt, opt, 'string')
      endif
    endfor
    for opt in ['on', 'for']
      if has_key(arg, opt)
          && type(arg[opt]) != TYPE.list
          && (type(arg[opt]) != TYPE.string || empty(arg[opt]))
        throw printf(opt_errfmt, opt, 'string or list')
      endif
    endfor
    if has_key(arg, 'do')
          && type(arg.do) != TYPE.funcref
          && (type(arg.do) != TYPE.string || empty(arg.do))
        throw printf(opt_errfmt, 'do', 'string or funcref')
    endif
    extend(opts, arg)
    if has_key(opts, 'dir')
      opts.dir = Dirpath(ExpandFilename(opts.dir))
    endif
  else
    throw 'Invalid argument type (expected: string or dictionary)'
  endif
  return opts
enddef

def InferProperties(name: string, repo: string): dict<any>
  var uri: string
  if IsLocalPlug(repo)
    return { 'dir': Dirpath(ExpandFilename(repo)) }
  else
    if repo =~ ':'
      uri = repo
    else
      if repo !~ '/'
        throw printf('Invalid argument: %s (implicit `vim-scripts'' expansion is deprecated)', repo)
      endif
      var fmt = get(g:, 'plug_url_format', 'https://git::@github.com/%s.git')
      uri = printf(fmt, repo)
    endif
    return { 'dir': Dirpath(g:plug_home .. '/' .. name), 'uri': uri }
  endif
enddef

def Install(force: number, names: list<string>)
  UpdateImpl(0, force, names)
enddef

def Update(force: number, names: list<string>)
  UpdateImpl(1, force, names)
enddef

def Helptags(): number
  if !exists('g:plugs')
    return Err('plug#begin was not called')
  endif
  for spec in values(g:plugs)
    var docd = join([PluginRuntimePath(spec), 'doc'], '/')
    if isdirectory(docd)
      silent! execute 'helptags' fnameescape(docd)
    endif
  endfor
  return 1
enddef

def Syntax()
  syntax clear
  syntax region plug1 start=/\%1l/ end=/\%2l/ contains=plugNumber
  syntax region plug2 start=/\%2l/ end=/\%3l/ contains=plugBracket,plugX,plugAbort
  syntax match plugNumber /[0-9]\+[0-9.]*/ contained
  syntax match plugBracket /[[\]]/ contained
  syntax match plugX /x/ contained
  syntax match plugAbort /\~/ contained
  syntax match plugDash /^-\{1}\ /
  syntax match plugPlus /^+/
  syntax match plugStar /^*/
  syntax match plugMessage /\(^- \)\@<=.*/
  syntax match plugName /\(^- \)\@<=[^ ]*:/
  syntax match plugSha /\%(: \)\@<=[0-9a-f]\{4,}$/
  syntax match plugTag /(tag: [^)]\+)/
  syntax match plugInstall /\(^+ \)\@<=[^:]*/
  syntax match plugUpdate /\(^* \)\@<=[^:]*/
  syntax match plugCommit /^  \X*[0-9a-f]\{7,9} .. */ contains=plugRelDate,plugEdge,plugTag
  syntax match plugEdge /^  \X\+$/
  syntax match plugEdge /^  \X*/ contained nextgroup=plugSha
  syntax match plugSha /[0-9a-f]\{7,9}/ contained
  syntax match plugRelDate /([^)]*)$/ contained
  syntax match plugNotLoaded /(not loaded)$/
  syntax match plugError /^x.*/
  syntax region plugDeleted start=/^\~ .. */ end=/^\ze\S/
  syntax match plugH2 /^.*:\n-\+$/
  syntax match plugH2 /^-\{2,}/
  syntax keyword Function PlugInstall PlugStatus PlugUpdate PlugClean
  highlight default link plug1       Title
  highlight default link plug2       Repeat
  highlight default link plugH2      Type
  highlight default link plugX       Exception
  highlight default link plugAbort   Ignore
  highlight default link plugBracket Structure
  highlight default link plugNumber  Number

  highlight default link plugDash    Special
  highlight default link plugPlus    Constant
  highlight default link plugStar    Boolean

  highlight default link plugMessage Function
  highlight default link plugName    Label
  highlight default link plugInstall Function
  highlight default link plugUpdate  Type

  highlight default link plugError   Error
  highlight default link plugDeleted Ignore
  highlight default link plugRelDate Comment
  highlight default link plugEdge    PreProc
  highlight default link plugSha     Identifier
  highlight default link plugTag     Constant

  highlight default link plugNotLoaded Comment
enddef

def Lpad(str: string, len: number): string
  return str .. repeat(' ', len - len(str))
enddef

def Lines(msg: string): list<string>
  return split(msg, "[\r\n]")
enddef

def Lastline(msg: string): string
  return get(Lines(msg), -1, '')
enddef

def NewWindow()
  execute 'legacy ' .. get(g:, 'plug_window', '-tabnew')
enddef

def PaneWindow(): number
  return plug_buf < 0 ? 0 : get(win_findbuf(plug_buf), 0, 0)
enddef

def SwitchIn(): dict<any>
  final pane = PaneWindow()
  if pane == 0
    return {}
  endif

  final previous_window = win_getid()
  final previous_view = winsaveview()
  if pane != previous_window && !win_gotoid(pane)
    return {}
  endif
  if bufnr() != plug_buf
    return {}
  endif
  final view: dict<any> = {
    pane: pane,
    pane_view: winsaveview(),
    previous_window: previous_window,
    previous_view: previous_view,
  }
  setlocal modifiable
  return view
enddef

def SwitchOut(view: dict<any>, action: string = '')
  if win_getid() == view.pane || win_gotoid(view.pane)
    if bufnr() == plug_buf
      winrestview(view.pane_view)
      setlocal nomodifiable
      if !empty(action)
        execute action
      endif
    endif
  endif
  if view.previous_window != view.pane && win_gotoid(view.previous_window)
    winrestview(view.previous_view)
  endif
enddef

def FinishBindings()
  nnoremap <silent> <buffer> R  :call <SID>Retry()<cr>
  nnoremap <silent> <buffer> D  :PlugDiff<cr>
  nnoremap <silent> <buffer> S  :PlugStatus<cr>
  nnoremap <silent> <buffer> U  :call <SID>StatusUpdateRange()<cr>
  xnoremap <silent> <buffer> U  :call <SID>StatusUpdateRange()<cr>
  nnoremap <silent> <buffer> ]] :silent! call <SID>Section('')<cr>
  nnoremap <silent> <buffer> [[ :silent! call <SID>Section('b')<cr>
enddef

def Prepare(...args: list<number>)
  if empty(GetWorkingDirectory())
    throw 'Invalid current working directory. Cannot proceed.'
  endif

  for evar in ['$GIT_DIR', '$GIT_WORK_TREE']
    if exists(evar)
      throw evar .. ' detected. Cannot proceed.'
    endif
  endfor

  JobAbort(false)
  final pane = PaneWindow()
  if pane != 0 && win_gotoid(pane)
    if b:plug_preview == 1
      pclose
    endif
    enew
  else
    NewWindow()
  endif

  nnoremap <silent> <buffer> q :call <SID>ClosePane()<cr>
  if len(args) == 0
    FinishBindings()
  endif
  b:plug_preview = -1
  plug_buf = bufnr()
  augroup Vim9PlugUI
    autocmd! * <buffer>
    autocmd BufWipeout <buffer> OnPaneWipe(str2nr(expand('<abuf>')))
  augroup END
  AssignName()

  for k in ['<cr>', 'L', 'o', 'X', 'd', 'dd']
    execute 'silent! unmap <buffer>' k
  endfor
  setlocal buftype=nofile bufhidden=wipe nobuflisted nolist noswapfile nowrap cursorline modifiable nospell
  if exists('+colorcolumn')
    setlocal colorcolumn=
  endif
  setfiletype vim-plug
  if exists('g:syntax_on')
    Syntax()
  endif
enddef

def OnPaneWipe(buffer: number)
  if buffer == plug_buf
    JobAbort(false)
  endif
enddef

def ClosePane()
  if b:plug_preview == 1
    pclose
    b:plug_preview = -1
  elseif !empty(jobs)
    JobAbort(true)
  else
    bdelete
  endif
enddef

def AssignName()
  # Assign buffer name
  var prefix = '[Plugins]'
  var name   = prefix
  var idx    = 2
  while bufexists(name)
    name = printf('%s (%s)', prefix, idx)
    idx += 1
  endwhile
  silent! execute 'f' fnameescape(name)
enddef

def Chsh(swap: number): list<string>
  var prev = [&shell, &shellcmdflag, &shellredir]
  if !is_win
    set shell=sh
  endif
  if swap
    if IsPowershell(&shell)
      &shellredir = '2>&1 | Out-File -Encoding UTF8 %s'
    elseif &shell =~# 'sh' || &shell =~# 'cmd\(\.exe\)\?$'
      set shellredir=>%s\ 2>&1
    endif
  endif
  return prev
enddef

def Bang(cmd: string, ...args: list<string>): string
  var batchfile = ''
  final previous_shell = Chsh(empty(args) ? 0 : 1)
  final had_command = exists('g:_plug_bang')
  final previous_command = get(g:, '_plug_bang', '')
  try
    var run_cmd = !empty(args) ? WithCd(cmd, args[0], {'shell': is_win ? 'cmd.exe' : &shell}) : cmd
    if is_win
      [batchfile, run_cmd] = Batchfile(run_cmd)
    endif
    g:_plug_bang = (is_win && has('gui_running') ? 'silent ' : '') .. '!' .. escape(run_cmd, '#!%')
    execute "normal! :execute g:_plug_bang\<cr>\<cr>"
  finally
    if had_command
      g:_plug_bang = previous_command
    else
      unlet! g:_plug_bang
    endif
    [&shell, &shellcmdflag, &shellredir] = previous_shell
    if is_win && filereadable(batchfile)
      delete(batchfile)
    endif
  endtry
  return v:shell_error != 0 ? 'Exit status: ' .. v:shell_error : ''
enddef

def RegressBar()
  var bar = substitute(getline(2)[1 : -2], '.*\zs=', 'x', '')
  ProgressBar(2, bar, len(bar))
enddef

def IsUpdated(dir: string): bool
  return !empty(SystemChomp(['git', 'log', '--pretty=format:%h', 'HEAD...HEAD@{1}'], dir))
enddef

def RunHook(spec: dict<any>, info: dict<any>): string
  final hook_window = win_getid()
  final directory_scope = haslocaldir()
  final previous_directory = chdir(spec.dir)
  if empty(previous_directory)
    return 'Unable to enter plugin directory: ' .. spec.dir
  endif
  var error = ''
  try
    final Hook = spec.do
    if type(Hook) == v:t_func
      LoadPlugin(spec)
      call(Hook, [info])
    elseif type(Hook) != v:t_string
      error = 'Invalid hook type'
    elseif Hook[0] != ':'
      error = Bang(Hook)
    else
      if !get(loaded, info.name, 0)
        loaded[info.name] = 1
        ReorgRtp()
      endif
      LoadPlugin(spec)
      execute 'legacy ' .. Hook[1 :]
    endif
  catch
    error = v:exception
  finally
    if directory_scope == 0
      execute 'cd' fnameescape(previous_directory)
    elseif win_gotoid(hook_window)
      execute (directory_scope == 1 ? 'lcd' : 'tcd') fnameescape(previous_directory)
    endif
  endtry
  return error
enddef

def RunHooks(request: dict<any>)
  for [name, spec] in items(request.all)
    if index(request.errors, name) >= 0 || !has_key(spec, 'do') || !isdirectory(spec.dir)
      continue
    endif
    final installed = has_key(request.new, name)
    final updated = !installed && request.pull && IsUpdated(spec.dir)
    if !request.force && !installed && !updated
      continue
    endif

    append(3, '- Post-update hook for ' .. name .. ' ... ')
    final status = installed ? 'installed' : updated ? 'updated' : 'unchanged'
    final error = RunHook(spec, {name: name, status: status, force: request.force})
    final pane = PaneWindow()
    if pane == 0 || !win_gotoid(pane)
      throw 'Warning: vim-plug was terminated by the post-update hook of ' .. name
    endif
    setlocal modifiable
    final message = getline(4)
    setline(4, empty(error) ? message .. 'OK' : 'x' .. message[1 :] .. error)
    if !empty(error)
      add(request.errors, name)
      RegressBar()
    endif
  endfor
enddef

def HashMatch(a: string, b: string): bool
  return stridx(a, b) == 0 || stridx(b, a) == 0
enddef

def DisableCredentialHelper(): bool
  return GitVersionRequirement(2) && Enabled(get(g:, 'plug_disable_credential_helper', 1))
enddef

def Checkout(spec: dict<any>): list<any>
  var sha = spec.commit
  var output = GitRevision(spec.dir)
  var error = 0
  if !empty(output) && !HashMatch(sha, Lines(output)[0])
    final fetch = DisableCredentialHelper() ? ['git', '-c', 'credential.helper='] : ['git']
    output = System(fetch + ['fetch', '--depth', '999999'], spec.dir)
    if shell_error == 0
      output ..= System(['git', 'checkout', sha, '--'], spec.dir)
    endif
    error = shell_error
  endif
  return [output, error]
enddef

def Finish(pull: number)
  var new_frozen = len(filter(keys(update_state.new), (_, name) => Enabled(g:plugs[name].frozen)))
  if new_frozen > 0
    var s = new_frozen > 1 ? 's' : ''
    append(3, printf('- Installed %d frozen plugin%s', new_frozen, s))
  endif
  append(3, '- Finishing ... ')
    :4
  redraw
  Helptags()
  End()
  setline(4, getline(4) .. 'Done!')
  redraw
  var msgs: list<string> = []
  if !empty(update_state.errors)
    add(msgs, "Press 'R' to retry.")
  endif
  if pull && len(update_state.new) < len(filter(getline(5, '$'),
                    (_, line) => line =~ '^- ' && line !~ 'Already up.to.date'))
    add(msgs, "Press 'D' to see the updated changes.")
  endif
  echo join(msgs, ' ')
  FinishBindings()
enddef

def Retry()
  if empty(update_state.errors)
    return
  endif
  echo ""
  UpdateImpl(update_state.pull, update_state.force,
            extend(copy(update_state.errors), [string(update_state.threads)]))
enddef

def IsManaged(name: string): bool
  return has_key(g:plugs[name], 'uri')
enddef

def Names(...args: list<any>): list<string>
  return sort(filter(keys(g:plugs), (_, name) => stridx(name, args[0]) == 0 && IsManaged(name)))
enddef

def UpdateImpl(pull: number, force: number, arguments: list<string>)
  final sync = index(arguments, '--sync') >= 0 || has('vim_starting')
  final selected = filter(copy(arguments), (_, arg) => arg != '--sync')
  final thread_count = !empty(selected) && selected[-1] =~ '^[1-9][0-9]*$'
      ? str2nr(remove(selected, -1))
      : str2nr(get(g:, 'plug_threads', 16) .. '')
  final todo = filter(deepcopy(g:plugs), (name, spec) =>
    has_key(spec, 'uri') && (empty(selected)
      ? !Enabled(spec.frozen) || !isdirectory(spec.dir)
      : index(selected, name) >= 0))
  if empty(todo)
    Warn('echo', 'No plugin to ' .. (pull ? 'update' : 'install'))
    return
  endif
  if !isdirectory(g:plug_home)
    try
      mkdir(g:plug_home, 'p')
    catch
      Err('Invalid plug directory: ' .. g:plug_home
        .. '. Try to call plug#begin with a valid directory')
      return
    endtry
  endif

  Prepare(1)
  final git_env: dict<string> = {}
  if !is_win && GitVersionRequirement(2, 3)
    git_env.GIT_TERMINAL_PROMPT = '0'
    for spec in values(todo)
      spec.uri = substitute(spec.uri, '^https://git::@github\.com', 'https://github.com', '')
    endfor
  endif
  final request: dict<any> = {
    start: reltime(),
    all: todo,
    todo: copy(todo),
    errors: [],
    pull: pull,
    force: force,
    new: {},
    threads: use_jobs ? max([1, min([len(todo), thread_count])]) : 1,
    bar: '',
    fin: false,
    cancelled: false,
    abandoned: false,
    env: git_env,
  }
  update_state = request

  append(0, ['', ''])
  normal! 2G

  # Override Git's clone.defaultRemoteName for repositories managed here.
  clone_opt = ['--origin', 'origin']
  if Enabled(get(g:, 'plug_shallow', 1))
    extend(clone_opt, ['--depth', '1'])
    if GitVersionRequirement(1, 7, 10)
      add(clone_opt, '--no-single-branch')
    endif
  endif
  if has('win32unix') || has('wsl')
    extend(clone_opt, ['-c', 'core.eol=lf', '-c', 'core.autocrlf=input'])
  endif
  submodule_opts = GitVersionRequirement(2, 8) ? ['--jobs=' .. thread_count] : []

  Bar()
  try
    Tick()
    while sync && !request.fin
      sleep 50m
    endwhile
  catch
    JobAbort(false)
    throw "vim9-plug: " .. v:exception .. " at " .. v:throwpoint
  endtry
enddef

def JobAbort(show_results: bool)
  if empty(update_state) || update_state.fin
    return
  endif
  final request = update_state
  request.cancelled = true
  request.abandoned = !show_results
  if !show_results
    request.todo = {}
  endif

  if exists_compiled('*job_stop')
    for process in values(copy(jobs))
      if has_key(process, 'handle')
        job_stop(process.handle)
      endif
    endfor
  endif

  if !show_results
    # Wait for the owning jobs so a new clone cannot race their cleanup.
    while !empty(jobs) && request is update_state
      sleep 20m
    endwhile
    request.fin = true
  elseif empty(jobs)
    Tick()
  endif
enddef

def Spawn(name: string, spec: dict<any>, queue: list<any>, options: dict<any>)
  final request = update_state
  final process: dict<any> = {
    name: name,
    spec: spec,
    running: true,
    error: false,
    lines: [''],
    new: !!get(options, 'new', 0),
    created_destination: !!get(options, 'new', 0) && !isdirectory(spec.dir),
    queue: copy(queue),
    exited: false,
    closed: false,
    status: -1,
    updates: 0,
  }
  final Item = remove(process.queue, 0)
  final argv: list<string> = type(Item) == v:t_func ? call(Item, [spec]) : Item
  jobs[name] = process
  final cwd: string = get(options, 'dir', '')

  if exists_compiled('*job_start')
    if use_jobs
      final settings: dict<any> = {
        in_io: 'null',
        out_mode: 'raw',
        err_io: 'out',
        out_cb: (_, chunk: string) => JobOutput(request, process, chunk),
        close_cb: (_) => JobClosed(request, process),
        exit_cb: (_, status: number) => JobExited(request, process, status),
        env: request.env,
      }
      if !empty(cwd)
        settings.cwd = cwd
      endif
      try
        final child: job = PlugCall('job_start', argv, settings)
        process.handle = child
        if job_status(child) != 'fail'
          return
        endif
        process.lines = ['Failed to start job: ' .. argv[0]]
      catch
        process.lines = ['Failed to start job: ' .. argv[0], v:exception]
      endtry
      if process.running
        process.running = false
        process.error = true
      endif
      return
    endif
  endif

  final prompt = getenv('GIT_TERMINAL_PROMPT')
  try
    if has_key(request.env, 'GIT_TERMINAL_PROMPT')
      setenv('GIT_TERMINAL_PROMPT', request.env.GIT_TERMINAL_PROMPT)
    endif
    process.lines = Lines(empty(cwd) ? System(argv) : System(argv, cwd))
    process.error = shell_error != 0
  finally
    setenv('GIT_TERMINAL_PROMPT', prompt)
    process.running = false
  endtry
enddef

def JobOutput(request: dict<any>, process: dict<any>, chunk: string)
  if request isnot update_state || request.cancelled
    return
  endif
  final raw = remove(process.lines, -1) .. chunk
  final lines = split(raw, "\n", true)->map((_, piece) => split(piece, "\r", true)[-1])
  extend(process.lines, lines)
  process.updates += 1
  if process.updates % len(jobs) == 0
    final line_text = LastNonEmptyLine(process.lines)
    if !empty(line_text)
      Log(BulletFor(process), process.name, line_text)
    endif
  endif
enddef

def JobClosed(request: dict<any>, process: dict<any>)
  process.closed = true
  CompleteJob(request, process)
enddef

def JobExited(request: dict<any>, process: dict<any>, status: number)
  process.status = status
  process.exited = true
  CompleteJob(request, process)
enddef

def CompleteJob(request: dict<any>, process: dict<any>)
  if !process.running || !process.closed || !process.exited
    return
  endif
  process.running = false
  var cleanup_error = ''
  if request.cancelled && process.created_destination && isdirectory(process.spec.dir)
    try
      cleanup_error = RemoveDirectory(process.spec.dir)
    catch
      cleanup_error = v:exception
    endtry
  endif
  if request isnot update_state
    return
  endif
  if request.abandoned
    remove(jobs, process.name)
    if empty(jobs)
      request.fin = true
    endif
    if !empty(cleanup_error)
      Warn('echomsg', cleanup_error)
    endif
    return
  endif
  process.error = request.cancelled || process.status != 0
  if request.cancelled
    process.abort = true
    process.lines = empty(cleanup_error) ? ['Aborted'] : ['Aborted', cleanup_error]
  endif
  # A polling call inside Spawn can deliver callbacks before it returns.
  if !pumping
    Tick()
  endif
enddef

def Log4(name: string, msg: string)
  setline(4, printf('- %s (%s)', msg, name))
  redraw
enddef

def UpdateFinish()
  final view = SwitchIn()
  if empty(view)
    return
  endif
  try
    append(3, '- Updating ...')
    :4
    for [name, spec] in items(filter(copy(update_state.all), (name, _) => index(update_state.errors, name) < 0 && (update_state.force || update_state.pull || has_key(update_state.new, name))))
      var [row, _] = Logpos(name)
      if row == 0
        continue
      endif
      var out = ''
      var error = 0
      if has_key(spec, 'commit')
        Log4(name, 'Checking out ' .. spec.commit)
        [out, error] = Checkout(spec)
      elseif has_key(spec, 'tag')
        var tag = spec.tag
        if tag =~ '\*'
          var tags = Lines(System(['git', 'tag', '--list', tag, '--sort', '-version:refname'], spec.dir))
          if shell_error == 0 && !empty(tags)
            tag = tags[0]
            Log4(name, printf('Latest tag for %s -> %s', spec.tag, tag))
            append(3, '')
          endif
        endif
        Log4(name, 'Checking out ' .. tag)
        out = System(['git', 'checkout', '-q', tag, '--'], spec.dir)
        error = shell_error
      endif
      if error == 0 && filereadable(spec.dir .. '/.gitmodules') &&
                (update_state.force || has_key(update_state.new, name) || IsUpdated(spec.dir))
        Log4(name, 'Updating submodules. This may take a while.')
        out ..= System(['git', 'submodule', 'update', '--init', '--recursive'] + submodule_opts, spec.dir)
        error = shell_error
      endif
      var msg = FormatMessage(error != 0 ? 'x' : '-', name, out)
      if error != 0
        add(update_state.errors, name)
        RegressBar()
        silent execute ':' .. row 'delete _'
        append(4, msg)
        :4
      elseif !empty(out)
        setline(row, msg[0])
      endif
      redraw
    endfor
    silent :4 delete _
    try
      RunHooks(update_state)
    catch
      Warn('echom', v:exception)
      Warn('echo', '')
      return
    endtry
    Finish(update_state.pull)
    setline(1, 'Updated. Elapsed time: ' .. split(reltimestr(reltime(update_state.start)))[0] .. ' sec.')
  finally
    SwitchOut(view, 'normal! gg')
  endtry
enddef

def LastNonEmptyLine(lines: list<string>): string
  var len = len(lines)
  for idx in range(len)
    var line = lines[len - idx - 1]
    if !empty(line)
      return line
    endif
  endfor
  return ''
enddef

def BulletFor(state: dict<any>, ...args: list<string>): string
  if state.running
    return state.new ? '+' : '*'
  endif
  if get(state, 'abort', 0)
    return '~'
  endif
  return state.error ? 'x' : get(args, 0, '-')
enddef

def Reap(name: string)
  var job = remove(jobs, name)
  if job.error
    add(update_state.errors, name)
  elseif get(job, 'new', 0)
    update_state.new[name] = 1
  endif

  var more = len(get(job, 'queue', []))
  var result = job.error ? join(job.lines, "\n") : LastNonEmptyLine(job.lines)
  if !empty(result)
    Log(BulletFor(job), name, result)
  endif

  if !job.error && more > 0
    job.spec.queue = job.queue
    update_state.todo[name] = job.spec
  else
    update_state.bar ..= BulletFor(job, '=')
    Bar()
  endif
enddef

def Bar()
  final view = SwitchIn()
  if !empty(view)
    var total = len(update_state.all)
    setline(1, (update_state.pull ? 'Updating' : 'Installing') ..
              ' plugins (' .. len(update_state.bar) .. '/' .. total .. ')')
    ProgressBar(2, update_state.bar, total)
    SwitchOut(view)
  endif
enddef

def Logpos(name: string): list<number>
  var max = line('$')
  for i in range(4, max > 4 ? max : 4)
    final text = getline(i)
    if text =~ '^[-+x*] ' && stridx(text[2 :], name .. ':') == 0
      for j in range(i + 1, max > 5 ? max : 5)
        if getline(j) !~ '^ '
          return [i, j - 1]
        endif
      endfor
      return [i, i]
    endif
  endfor
  return [0, 0]
enddef

def Log(bullet: string, name: string, lines: string)
  final view = SwitchIn()
  if !empty(view)
    var [first, last] = Logpos(name)
    if first > 0
      silent execute printf(':%d,%d delete _', first, last)
      if first > winheight(0)
        first = 4
      endif
    else
      first = 4
    endif
    setlocal modifiable
    append(first - 1, FormatMessage(bullet, name, lines))
    SwitchOut(view)
  endif
enddef

def CheckoutCommand(spec: dict<any>): list<string>
  spec.branch = GitOriginBranch(spec)
  return ['git', 'checkout', '-q', spec.branch, '--']
enddef

def MergeCommand(spec: dict<any>): list<string>
  spec.branch = GitOriginBranch(spec)
  return ['git', 'merge', '--ff-only', 'origin/' .. spec.branch]
enddef

def Tick()
  if pumping || update_state.fin || update_state.abandoned
    return
  endif
  pumping = true
  try
    while true
      for [name, process] in items(copy(jobs))
        if !process.running
          Reap(name)
        endif
      endfor
      if empty(update_state.todo)
        if empty(jobs)
          update_state.fin = true
          UpdateFinish()
        endif
        return
      endif
      if len(jobs) >= update_state.threads
        return
      endif

      final name = keys(update_state.todo)[0]
      final spec: dict<any> = remove(update_state.todo, name)
      if update_state.cancelled
        jobs[name] = {running: false, error: true, abort: true, lines: ['Skipped']}
        continue
      endif
      QueuePlugin(name, spec)
    endwhile
  finally
    pumping = false
  endtry
enddef

def QueuePlugin(name: string, spec: dict<any>)
  if has_key(spec, 'queue')
    Spawn(name, spec, remove(spec, 'queue'), {dir: spec.dir})
    return
  endif
  final pull: bool = !!update_state.pull
  final new = empty(globpath(escape(spec.dir, ','), '.git', 1))
  final progress = ProgressOpt(use_jobs)
  Log(new ? '+' : '*', name, pull ? 'Updating ...' : 'Installing ...')
  redraw

  final has_tag = has_key(spec, 'tag')
  if new
    final cmd = ['git', 'clone']
    if !has_tag
      extend(cmd, clone_opt)
    endif
    if !empty(progress)
      add(cmd, progress)
    endif
    extend(cmd, [spec.uri, Trim(spec.dir)])
    Spawn(name, spec, [cmd, CheckoutCommand, MergeCommand], {new: true})
    return
  endif

  final [error, _] = GitValidate(spec, 0)
  if !empty(error) || !pull
    jobs[name] = {
      running: false,
      error: !empty(error),
      lines: empty(error) ? ['Already installed'] : Lines(error),
    }
    return
  endif

  final fetch = DisableCredentialHelper()
    ? ['git', '-c', 'credential.helper=', 'fetch']
    : ['git', 'fetch']
  if has_tag && filereadable(spec.dir .. '/.git/shallow')
    extend(fetch, ['--depth', '99999999'])
  endif
  if !empty(progress)
    add(fetch, progress)
  endif
  final commands: list<any> = [fetch, ['git', 'remote', 'set-head', 'origin', '-a']]
  if !has_tag && !has_key(spec, 'commit')
    extend(commands, [CheckoutCommand, MergeCommand])
  endif
  Spawn(name, spec, commands, {dir: spec.dir})
enddef

def ShellescCmd(arg: string, script: any): string
  var escaped = substitute('"' .. arg .. '"', '[&|<>()@^!"]', '^&', 'g')
  return substitute(escaped, '%', (Enabled(script) ? '%' : '^') .. '&', 'g')
enddef

def ShellescPs1(arg: string): string
  return "'" .. substitute(escape(arg, '\"'), "'", "''", 'g') .. "'"
enddef

def ShellescSh(arg: string): string
  return "'" .. substitute(arg, "'", "'\\\\''", 'g') .. "'"
enddef

# Escape the shell argument based on the shell.
# The selected shell can differ from the shell Vim uses.
# 1. shellslash determines whether to use single/double quotes.
#    Double-quote escaping is fragile for cmd.exe.
# 2. It does not work for powershell.
# 3. It does not work for *sh shells if the command is executed
#    via cmd.exe (ie. cmd.exe /c sh -c command command_args)
# 4. It does not support batchfile syntax.
#
# Accepts an optional dictionary with the following keys:
# - shell: same as Vim's 'shell' option.
#          If unset, fallback to 'cmd.exe' on Windows or 'sh'.
# - script: If truthy and shell is cmd.exe, escape for batchfile syntax.

def Shellescape(arg: any, ...args: list<any>): string
  if arg =~# '^[A-Za-z0-9_/:.-]\+$'
    return arg
  endif
  var opts = len(args) > 0 && type(args[0]) == TYPE.dict ? args[0] : {}
  var shell = get(opts, 'shell', is_win ? 'cmd.exe' : 'sh')
  var script = get(opts, 'script', 1)
  if shell =~# 'cmd\(\.exe\)\?$'
    return ShellescCmd(arg, script)
  elseif IsPowershell(shell)
    return ShellescPs1(arg)
  endif
  return ShellescSh(arg)
enddef

def GlobDir(path: string): list<string>
  return map(filter(Glob(path, '**'), (_, dir) => isdirectory(dir)), (_, dir) => Dirpath(dir))
enddef

def ProgressBar(line: number, bar: string, total: number)
  setline(line, '[' .. Lpad(bar, total) .. ']')
enddef

def CompareGitUri(a: string, b: string): bool
  # See `git help clone'
  # https:// [user@] github.com[:port] / junegunn/vim-plug [.git]
  #          [git@]  github.com[:port] : junegunn/vim-plug [.git]
  # file://                            / junegunn/vim-plug        [/]
  #                                    / junegunn/vim-plug        [/]
  var pat = '^\%(\w\+://\)\=' .. '\%([^@/]*@\)\=' .. '\([^:/]*\%(:[0-9]*\)\=\)' .. '[:/]' .. '\(.\{-}\)' .. '\%(\.git\)\=/\?$'
  var ma = matchlist(a, pat)
  var mb = matchlist(b, pat)
  return ma[1 : 2] ==# mb[1 : 2]
enddef

def FormatMessage(bullet: string, name: string, message: string): list<string>
  if bullet != 'x'
    return [printf('%s %s: %s', bullet, name, Lastline(message))]
  else
    var lines = map(Lines(message), (_, line) => '    ' .. line)
    return extend([printf('x %s:', name)], lines)
  endif
enddef

def WithCd(cmd: string, dir: string, ...args: list<any>): string
  var opts = len(args) > 0 && type(args[0]) == TYPE.dict ? args[0] : {}
  opts.shell = get(opts, 'shell', &shell)
  opts.script = get(opts, 'script', 1)

  var pwsh = IsPowershell(opts.shell)
  var cd = is_win && !pwsh ? 'cd /d' : 'cd'
  var sep = pwsh ? ';' : '&&'
  var pwsh_block_required = pwsh && !has('patch-9.2.6')
  var start = pwsh_block_required ? '& { ' : ''
  var end = pwsh_block_required ? ' }' : ''

  return printf('%s%s %s %s %s%s', start, cd, Shellescape(dir, opts), sep, cmd, end)
enddef

# Windows and Unix GUI builds can run Git directly with a per-process cwd.
# Keep the serial shell path available on builds without jobs or channels.
if use_jobs && (is_win || has('gui_running'))
  def System(argv: list<string>, directory: string = ''): string
    final output_file = TempName()
    var output: string
    try
      final options: dict<any> = {
        in_io: 'null',
        out_io: 'file',
        out_name: output_file,
        err_io: 'out',
      }
      if !empty(directory)
        options.cwd = directory
      endif
      final child: job = PlugCall('job_start', argv, options)
      while job_status(child) == 'run'
        sleep 5m
      endwhile
      if job_status(child) == 'fail'
        shell_error = -1
        output = 'Failed to start job: ' .. argv[0]
      else
        shell_error = job_info(child).exitval
        output = filereadable(output_file) ? join(readfile(output_file, 'b'), "\n") : ''
      endif
    finally
      delete(output_file)
    endtry
    return output
  enddef
else
  def System(argv: list<string>, directory: string = ''): string
    final previous_shell = Chsh(1)
    var output: string
    try
      var command = join(mapnew(argv, (_, arg) => Shellescape(arg, {shell: &shell, script: 0})))
      if IsPowershell(&shell)
        command = '& ' .. command
      endif
      if !empty(directory)
        command = WithCd(command, directory, {script: 0})
      endif
      output = system(command)
      shell_error = v:shell_error
      if is_win && IsPowershell(&shell)
        # Windows PowerShell's UTF-8 output files start with a BOM.
        output = substitute(output, '^\%uFEFF', '', '')
      endif
    finally
      [&shell, &shellcmdflag, &shellredir] = previous_shell
    endtry
    return output
  enddef
endif

def SystemChomp(argv: list<string>, directory: string = ''): string
  final ret = System(argv, directory)
  return shell_error != 0 ? '' : substitute(ret, '\n$', '', '')
enddef

def GitValidate(spec: dict<any>, check_branch: number): list<any>
  var err = ''
  if isdirectory(spec.dir)
    var result = [GitLocalBranch(spec.dir), GitOriginUrl(spec.dir)]
    var remote = result[-1]
    if empty(remote)
      err = join([remote, 'PlugClean required.'], "\n")
    elseif !CompareGitUri(remote, spec.uri)
      err = join(['Invalid URI: ' .. remote,
                        'Expected:    ' .. spec.uri,
                        'PlugClean required.'], "\n")
    elseif !check_branch
      return ['', 0]
    elseif has_key(spec, 'commit')
      var sha = GitRevision(spec.dir)
      if empty(sha)
        err = join(add(result, 'PlugClean required.'), "\n")
      elseif !HashMatch(sha, spec.commit)
        err = join([printf('Invalid HEAD (expected: %s, actual: %s)',
                                  spec.commit[: 6], sha[: 6]),
                          'PlugUpdate required.'], "\n")
      endif
    elseif has_key(spec, 'tag')
      var tag = SystemChomp(['git', 'describe', '--exact-match', '--tags', 'HEAD'], spec.dir)
      if spec.tag !=# tag && spec.tag !~ '\*'
        err = printf('Invalid tag: %s (expected: %s). Try PlugUpdate.',
                  (empty(tag) ? 'N/A' : tag), spec.tag)
      endif
    elseif check_branch
      var current_branch = result[0]
      var origin_branch = GitOriginBranch(spec)
      if origin_branch !=# current_branch
        err = printf('Invalid branch: %s (expected: %s). Try PlugUpdate.',
                  current_branch, origin_branch)
      endif
      if empty(err)
        var ahead_behind = split(Lastline(System([
              'git', 'rev-list', '--count', '--left-right',
              printf('HEAD...origin/%s', origin_branch)
              ], spec.dir)), '\t')
        if shell_error != 0 || len(ahead_behind) != 2
          err = "Failed to compare with the origin. The default branch might have changed.\nPlugClean required."
        else
          var [ahead, behind] = ahead_behind
          if str2nr(ahead) > 0 && str2nr(behind) > 0
            # Only mention PlugClean if diverged, otherwise it's likely to be
            # pushable (and probably not that messed up).
            err = printf(
                      "Diverged from origin/%s (%d commit(s) ahead and %d commit(s) behind!\n"
                      .. 'Backup local changes and run PlugClean and PlugUpdate to reinstall it.', origin_branch, ahead, behind)
          elseif str2nr(ahead) > 0
            err = printf("Ahead of origin/%s by %d commit(s).\n"
                      .. 'Cannot update until local changes are pushed.',
                      origin_branch, ahead)
          endif
        endif
      endif
    endif
  else
    err = 'Not found'
  endif
  return [err, err =~# 'PlugClean']
enddef

def RemoveDirectory(dir: string): string
  if isdirectory(dir)
    if is_win
      return delete(substitute(dir, '[/\\]\+$', '', ''), 'rf') == 0
        ? ''
        : 'Unable to remove directory: ' .. dir
    endif
    return System(['rm', '-rf', '--', dir])
  endif
  return ''
enddef

def Clean(force: number)
  Prepare()
  append(0, 'Searching for invalid plugins in ' .. g:plug_home)
  append(1, '')

  # List of valid directories
  var dirs: list<string> = []
  var errs: dict<string> = {}
  var [cnt, total] = [0, len(g:plugs)]
  for [name, spec] in items(g:plugs)
    if !IsManaged(name) || Enabled(get(spec, 'frozen', 0))
      add(dirs, spec.dir)
    else
      var [err, clean] = GitValidate(spec, 1)
      if clean
        errs[spec.dir] = Lines(err)[0]
      else
        add(dirs, spec.dir)
      endif
    endif
    cnt += 1
    ProgressBar(2, repeat('=', cnt), total)
    normal! 2G
    redraw
  endfor

  var allowed: dict<number> = {}
  for dir in dirs
    allowed[Dirpath(ModifyFilename(dir, ':h:h'))] = 1
    allowed[dir] = 1
    for child in GlobDir(dir)
      allowed[child] = 1
    endfor
  endfor

  var todo: list<string> = []
  var found = sort(GlobDir(g:plug_home))
  while !empty(found)
    var f = remove(found, 0)
    if !has_key(allowed, f) && isdirectory(f)
      add(todo, f)
      append(line('$'), '- ' .. f)
      if has_key(errs, f)
        append(line('$'), '    ' .. errs[f])
      endif
      found = filter(found, (_, dir) => stridx(dir, f) != 0)
    endif
  endwhile

  cursor(min([4, line('$')]), 1)
  redraw
  if empty(todo)
    append(line('$'), 'Already clean.')
  else
    clean_count = 0
    append(3, ['Directories to delete:', ''])
    redraw!
    if force || AskNoInterrupt('Delete all directories?')
      Delete([6, line('$')], 1)
    else
      setline(4, 'Cancelled.')
      nnoremap <silent> <buffer> d :set opfunc=<SID>DeleteOpAdapter<cr>g@
      nmap     <silent> <buffer> dd d_
      xnoremap <silent> <buffer> d :<c-u>call <SID>DeleteOpAdapter(visualmode(), 1)<cr>
      echo 'Delete the lines (d{motion}) to delete the corresponding directories'
    endif
  endif
  cursor(min([4, line('$')]), 1)
  setlocal nomodifiable
enddef

def DeleteOp(type: string, ...args: list<any>)
  Delete(!empty(args) ? [line("'<"), line("'>")] : [line("'["), line("']")], 0)
enddef

def Delete(range: list<number>, force: number)
  var [l1, l2] = range
  var delete_all = !!force
  var err_count = 0
  while l1 <= l2
    var line = getline(l1)
    if line =~ '^- ' && isdirectory(line[2 : ])
      execute ":" .. l1
      redraw!
      var answer = delete_all ? 1 : Ask('Delete ' .. line[2 : ] .. '?', 1)
      delete_all = delete_all || answer > 1
      if answer != 0
        var err = RemoveDirectory(line[2 : ])
        setlocal modifiable
        if empty(err)
          setline(l1, '~' .. line[1 : ])
          clean_count += 1
        else
          delete _
          append(l1 - 1, FormatMessage('x', line[1 : ], err))
          l2 += len(Lines(err))
          err_count += 1
        endif
        var msg = printf('Removed %d directories.', clean_count)
        if err_count > 0
          msg ..= printf(' Failed to remove %d directories.', err_count)
        endif
        setline(4, msg)
        setlocal nomodifiable
      endif
    endif
    l1 += 1
  endwhile
enddef

def StageUpgrade(): bool
  if !empty(update_state) && !update_state.fin
    Err('Wait for the current plugin update to finish before upgrading.')
    return false
  endif
  echo 'Downloading the latest version of vim9-plug'
  redraw
  final checkout = TempName()
  final candidate = checkout .. '/autoload/plug.vim'
  final staging = plug_file .. '.' .. ModifyFilename(TempName(), ':t')
  final backup = plug_file .. '.old'
  try
    final output = System(['git', 'clone', '--depth', '1', upgrade_origin, checkout])
    if shell_error != 0 || !filereadable(candidate)
      Err('Error upgrading vim9-plug: ' .. (shell_error != 0 ? output : 'autoload/plug.vim is missing'))
      return false
    endif

    final current_bytes = readfile(plug_file, 'b')
    final new_bytes = readfile(candidate, 'b')
    if new_bytes == current_bytes
      echo 'vim9-plug is already up-to-date'
      return false
    endif
    if get(new_bytes, 0, '') !~ '^vim9script\>'
      Err('Error upgrading vim9-plug: invalid autoload/plug.vim')
      return false
    endif
    if writefile(new_bytes, staging, 'b') != 0
      Err('Error upgrading vim9-plug: unable to stage the new file')
      return false
    endif
    setfperm(staging, getfperm(plug_file))
    if rename(plug_file, backup) != 0
      Err('Error upgrading vim9-plug: unable to back up the installed file')
      return false
    endif
    if rename(staging, plug_file) != 0
      if rename(backup, plug_file) != 0
        Err('Error upgrading vim9-plug: restore the installed file from ' .. backup)
      else
        Err('Error upgrading vim9-plug: unable to replace the installed file')
      endif
      return false
    endif
    return true
  catch
    Err('Error upgrading vim9-plug: ' .. v:exception)
  finally
    delete(staging)
    delete(checkout, 'rf')
  endtry
  return false
enddef

def RollbackUpgrade(reason: string)
  Err('Error loading the upgrade: ' .. reason)
  if rename(plug_file .. '.old', plug_file) != 0
    throw 'Unable to restore the backup: ' .. plug_file .. '.old'
  endif
  unlet! g:loaded_plug
enddef

def UpgradeSpecs()
  for spec in values(g:plugs)
    spec.frozen = get(spec, 'frozen', 0)
  endfor
enddef

def Status()
  Prepare()
  append(0, 'Checking plugins')
  append(1, '')

  var ecnt = 0
  var unloaded = 0
  var [cnt, total] = [0, len(g:plugs)]
  for [name, spec] in items(g:plugs)
    var valid: bool
    var msg: string
    var is_dir = isdirectory(spec.dir)
    if has_key(spec, 'uri')
      if is_dir
        var [err, _] = GitValidate(spec, 1)
        [valid, msg] = [empty(err), empty(err) ? 'OK' : err]
      else
        [valid, msg] = [false, 'Not found. Try PlugInstall.']
      endif
    else
      if is_dir
        [valid, msg] = [true, 'OK']
      else
        [valid, msg] = [false, 'Not found.']
      endif
    endif
    cnt += 1
    ecnt += valid ? 0 : 1
    # `s:loaded` entry can be missing if PlugUpgraded
    if is_dir && get(loaded, name, -1) == 0
      unloaded = 1
      msg ..= ' (not loaded)'
    endif
    ProgressBar(2, repeat('=', cnt), total)
    append(3, FormatMessage(valid ? '-' : 'x', name, msg))
    normal! 2G
    redraw
  endfor
  setline(1, 'Finished. ' .. ecnt .. ' error(s).')
  normal! gg
  setlocal nomodifiable
  if unloaded
    echo "Press 'L' on each line to load plugin, or 'U' to update"
    nnoremap <silent> <buffer> L :call <SID>StatusLoad(line('.'))<cr>
    xnoremap <silent> <buffer> L :call <SID>StatusLoad(line('.'))<cr>
  endif
enddef

def ExtractName(str: string, prefix: string, suffix: string): string
  return matchstr(str, '^' .. prefix .. ' \zs[^:]\+\ze:.*' .. suffix .. '$')
enddef

def StatusLoad(lnum: number)
  var line = getline(lnum)
  var name = ExtractName(line, '-', '(not loaded)')
  if !empty(name)
    Load(name)
    setlocal modifiable
    setline(lnum, substitute(line, ' (not loaded)$', '', ''))
    setlocal nomodifiable
  endif
enddef

def StatusUpdate(firstline: number, lastline: number)
  var lines = getline(firstline, lastline)
  var names = filter(map(lines, (_, line) => ExtractName(line, '[x-]', '')), (_, name) => !empty(name))
  if !empty(names)
    echo ""
    execute 'PlugUpdate' join(names)
  endif
enddef

def IsPreviewWindowOpen(): bool
  silent! wincmd P
  if &previewwindow
    wincmd p
    return true
  endif
  return false
enddef

def FindName(lnum: number): string
  for index in reverse(range(1, lnum))
    var line = getline(index)
    if empty(line)
      return ''
    endif
    var name = ExtractName(line, '-', '')
    if !empty(name)
      return name
    endif
  endfor
  return ''
enddef

def PreviewCommit()
  if b:plug_preview < 0
    b:plug_preview = IsPreviewWindowOpen() ? 0 : 1
  endif

  var name: string
  var title: string
  var command: list<string>
  var sha = matchstr(getline('.'), '^  \X*\zs[0-9a-f]\{7,9}')
  if empty(sha)
    name = matchstr(getline('.'), '^- \zs[^:]*\ze:$')
    if empty(name)
      return
    endif
    title = 'HEAD@{1}..'
    command = ['git', 'diff', '--no-color', 'HEAD@{1}']
  else
    title = sha
    command = ['git', 'show', '--no-color', '--pretty=medium', sha]
    name = FindName(line('.'))
  endif

  if empty(name) || !has_key(g:plugs, name) || !isdirectory(g:plugs[name].dir)
    return
  endif

  if !IsPreviewWindowOpen()
    execute get(g:, 'plug_pwindow', 'vertical rightbelow new')
    execute 'e' title
  else
    execute 'pedit' title
    wincmd P
  endif
  setlocal previewwindow filetype=git buftype=nofile bufhidden=wipe nobuflisted modifiable
  try
    final lines = split(System(command, g:plugs[name].dir), '\r\?\n', true)
    if len(lines) > 1 && empty(lines[-1])
      remove(lines, -1)
    endif
    if empty(lines)
      add(lines, '')
    endif
    setline(1, lines)
    if line('$') > len(lines)
      deletebufline(bufnr(), len(lines) + 1, '$')
    endif
    nnoremap <silent> <buffer> q :q<cr>
  finally
    setlocal nomodifiable nomodified
    wincmd p
  endtry
enddef

def Section(flags: string)
  search('\(^[x-] \)\@<=[^:]\+:', flags)
enddef

def FormatGitLog(line: string): string
  var indent = '  '
  var tokens = split(line, nr2char(1))
  if len(tokens) != 5
    return indent .. substitute(line, '\s*$', '', '')
  endif
  var [graph, sha, refs, subject, date] = tokens
  var tag = matchstr(refs, 'tag: [^,)]\+')
  tag = empty(tag) ? ' ' : ' (' .. tag .. ') '
  return printf('%s%s%s%s%s (%s)', indent, graph, sha, tag, subject, date)
enddef

def AppendUl(lnum: number, text: string)
  append(lnum, ['', text, repeat('-', len(text))])
enddef

def Diff()
  Prepare()
  append(0, ['Collecting changes ...', ''])
  var cnts = [0, 0]
  var bar = ''
  var total = filter(copy(g:plugs), (name, spec) => IsManaged(name) && isdirectory(spec.dir))
  ProgressBar(2, bar, len(total))
  for origin in [1, 0]
    var plugs = reverse(sort(items(filter(copy(total), (_, spec) => (has_key(spec, 'commit') || has_key(spec, 'tag')) == (origin == 1)))))
    if empty(plugs)
      continue
    endif
    AppendUl(2, origin ? 'Pending updates:' : 'Last update:')
    for [k, v] in plugs
      var branch = GitOriginBranch(v)
      if !empty(branch)
        var range = origin ? '..origin/' .. branch : 'HEAD@{1}..'
        var cmd = ['git', 'log', '--graph', '--color=never']
        if GitVersionRequirement(2, 10, 0)
          add(cmd, '--no-show-signature')
        endif
        extend(cmd, ['--pretty=format:%x01%h%x01%d%x01%s%x01%cr', range])
        if has_key(v, 'rtp')
          extend(cmd, ['--', v.rtp])
        endif
        var diff = SystemChomp(cmd, v.dir)
        if !empty(diff)
          var ref = has_key(v, 'tag') ? (' (tag: ' .. v.tag .. ')') : has_key(v, 'commit') ? (' ' .. v.commit) : ''
          append(5, extend(['', '- ' .. k .. ':' .. ref], map(Lines(diff), (_, line) => FormatGitLog(line))))
          cnts[origin] += 1
        endif
      endif
      bar ..= '='
      ProgressBar(2, bar, len(total))
      normal! 2G
      redraw
    endfor
    if !cnts[origin]
      append(5, ['', 'N/A'])
    endif
  endfor
  setline(1, printf('%d plugin(s) updated.', cnts[0])
            .. (cnts[1] > 0 ? printf(' %d plugin(s) have pending updates.', cnts[1]) : ''))

  if cnts[0] > 0 || cnts[1] > 0
    nnoremap <silent> <buffer> <plug>(plug-preview) :silent! call <SID>PreviewCommit()<cr>
    if empty(maparg("\<cr>", 'n'))
      nmap <buffer> <cr> <plug>(plug-preview)
    endif
    if empty(maparg('o', 'n'))
      nmap <buffer> o <plug>(plug-preview)
    endif
  endif
  if cnts[0] > 0
    nnoremap <silent> <buffer> X :call <SID>Revert()<cr>
    echo "Press 'X' on each block to revert the update"
  endif
  normal! gg
  setlocal nomodifiable
enddef

def Revert()
  if search('^Pending updates', 'bnW')
    return
  endif

  var name = FindName(line('.'))
  if empty(name) || !has_key(g:plugs, name) ||
        input(printf('Revert the update of %s? (y/N) ', name)) !~? '^y'
    return
  endif

  final spec = g:plugs[name]
  final branch = GitOriginBranch(spec)
  var output = System(['git', 'reset', '--hard', 'HEAD@{1}'], spec.dir)
  if shell_error == 0
    output = System(['git', 'checkout', branch, '--'], spec.dir)
  endif
  if shell_error != 0
    Err(Lastline(output))
    return
  endif
  setlocal modifiable
  normal! "_dap
  setlocal nomodifiable
  echo 'Reverted'
enddef

def Snapshot(force: number, ...args: list<string>)
  Prepare()
  setfiletype vim
  append(0, ['" Generated by vim-plug',
                    '" ' .. strftime("%c"),
                    '" :source this file in vim to restore the snapshot',
                    '" or execute: vim -S snapshot.vim',
                    '', '', 'PlugUpdate!'])
  :1
  var anchor = line('$') - 3
  var names = sort(keys(filter(copy(g:plugs),
            (_, spec) => has_key(spec, 'uri') && isdirectory(spec.dir))))
  for name in reverse(names)
    var sha = has_key(g:plugs[name], 'commit') ? g:plugs[name].commit : GitRevision(g:plugs[name].dir)
    if !empty(sha)
      append(anchor, printf("silent! let g:plugs[%s].commit = %s", string(name), string(sha)))
      redraw
    endif
  endfor

  if len(args) > 0
    var fn = ExpandFilename(args[0])
    if filereadable(fn) && !(force || Ask(args[0] .. ' already exists. Overwrite?'))
      return
    endif
    writefile(getline(1, '$'), fn)
    echo 'Saved as ' .. args[0]
    silent execute 'e' fnameescape(fn)
    setfiletype vim
  endif
enddef

def SplitRtp(): list<string>
  return split(&rtp, '\\\@<!,')
enddef

plug_file = resolve(ModifyFilename(expand('<sfile>:p'), ':p'))
first_rtp = EscapeRuntimePath(get(SplitRtp(), 0, ''))
last_rtp = EscapeRuntimePath(get(SplitRtp(), -1, ''))

if exists('g:plugs')
  g:plugs_order = get(g:, 'plugs_order', keys(g:plugs))
  UpgradeSpecs()
  RegisterCommands()
endif

g:loaded_plug = 1
