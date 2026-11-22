vim9script

# Let the same workflow drive the pinned upstream in its own Vim process.
g:vim9_plug_test_upstream = true

export def Begin(directory: string = ''): bool
  return (empty(directory) ? plug#begin() : plug#begin(directory)) == 1
enddef

export def Add(repository: string, options: dict<any> = {})
  plug#(repository, options)
enddef

export def End()
  plug#end()
enddef

export def Load(names: list<string>): bool
  return plug#load(names) == 1
enddef

export def Helptags(): bool
  return plug#helptags() == 1
enddef

export def ShellEscape(arg: string, shell: string = has('win32') ? 'cmd.exe' : 'sh', for_batch: bool = true): string
  return plug#shellescape(arg, {shell: shell, script: for_batch})
enddef
