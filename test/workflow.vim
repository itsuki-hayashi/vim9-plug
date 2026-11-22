vim9script

set nomore
execute 'set runtimepath^=' .. fnameescape($VIM9_PLUG_TEST_ROOT)
import autoload 'plug.vim' as plug
g:load_order = []
g:observed = []
var plugin_home = $VIM9_PLUG_TEST_ROOT .. '/plugin home'

def Git(path: string, ...args: list<string>): string
  final dir = has('win32') ? substitute(path, '\\', '/', 'g') : path
  final argv = ['git', '-C', substitute(dir, '/\+$', '', '')] + args
  final command = join(mapnew(argv, (_, arg) => plug.ShellEscape(arg, &shell, false)))
  final prefix = &shell =~? '\%(pwsh\|powershell\)\%(\.exe\)\?$' ? '& ' : ''
  final result = system(prefix .. command)
  assert_equal(0, v:shell_error, command .. ': ' .. result)
  return trim(result)
enddef

assert_true(plug.Begin(plugin_home))
plug.Add($VIM9_PLUG_TEST_LOCAL, {'as': 'eager'})
plug.Add($VIM9_PLUG_TEST_LAZY, {'as': 'lazy', 'on': ['FixtureLazy', '<Plug>(fixture-lazy)']})
plug.Add($VIM9_PLUG_TEST_REMOTE, {'as': 'managed', 'branch': 'main', 'do': (info) => add(g:observed, string(info.status))})
plug.Add($VIM9_PLUG_TEST_REMOTE, {'as': 'tagged', 'tag': 'v*'})
plug.Add($VIM9_PLUG_TEST_REMOTE, {'as': 'frozen', 'frozen': 1, 'on': []})
assert_equal(['eager', 'lazy', 'managed', 'tagged', 'frozen'], g:plugs_order)
plug.End()
if has("vim_starting")
  runtime! plugin/**/*.vim
endif
assert_equal(['eager', 'after eager'], g:load_order)
assert_equal(0, get(g:, 'managed_plugin', 0))
assert_equal(2, exists(':FixtureLazy'))
assert_true(plug.Helptags())
assert_true(filereadable($VIM9_PLUG_TEST_LOCAL .. '/doc/tags'))
assert_equal(["'a b'", '^"a b^"', "'a b'"], map(['sh', 'cmd.exe', 'pwsh'],
      \ (_, sh) => plug.ShellEscape('a b', sh, false)))
assert_equal('^"^^%%PATH^^%%^"', plug.ShellEscape('^%PATH^%', 'cmd.exe'))
assert_equal('^"^^^%PATH^^^%^"',
      \ plug.ShellEscape('^%PATH^%', 'cmd.exe', false))
assert_equal('''\"Foo\\''''\\Bar\"''',
      \ plug.ShellEscape('"Foo\''\Bar"', 'powershell.exe'))

setline(1, ['first', 'second'])
:1,2FixtureLazy! hello world
assert_equal([1, 1, 2, 'hello world'], g:lazy_call)
assert_false(plug.Load(['lazy']))
assert_equal(['eager', 'after eager', 'lazy'], g:load_order)
add(g:observed, string(g:load_order))

PlugInstall --sync 2
assert_true(isdirectory(g:plugs.managed.dir .. '/.git'), getline(1, '$')->join("\n"))
assert_true(filereadable(g:plugs.managed.dir .. '/vendor/submodule/.git'),
      \ join(getline(1, '$'), "\n"))
assert_equal(1, get(g:, 'managed_plugin', 0))
assert_equal(['managed'], getcompletion('PlugUpdate ma', 'cmdline'))
assert_equal($VIM9_PLUG_TEST_FIRST_SHA, Git(g:plugs.managed.dir, 'rev-parse', 'HEAD'))
assert_equal($VIM9_PLUG_TEST_FIRST_SHA, Git(g:plugs.tagged.dir, 'rev-parse', 'HEAD'))
assert_equal($VIM9_PLUG_TEST_FIRST_SHA, Git(g:plugs.frozen.dir, 'rev-parse', 'HEAD'))

PlugStatus
assert_equal('Finished. 0 error(s).', getline(1))
add(g:observed, getline(1))
add(g:observed, string(sort(getline(4, '$'))))

Git($VIM9_PLUG_TEST_GIT_REPO, 'update-ref', 'refs/heads/main', 'refs/fixtures/next')
Git($VIM9_PLUG_TEST_GIT_REPO, 'tag', 'v2', 'refs/fixtures/next')
PlugUpdate --sync
assert_equal($VIM9_PLUG_TEST_SECOND_SHA, Git(g:plugs.managed.dir, 'rev-parse', 'HEAD'),
      \ join(getline(1, '$'), "\n"))
assert_equal($VIM9_PLUG_TEST_FIRST_SHA, Git(g:plugs.frozen.dir, 'rev-parse', 'HEAD'))
assert_equal($VIM9_PLUG_TEST_SECOND_SHA, Git(g:plugs.tagged.dir, 'rev-parse', 'HEAD'))
assert_equal(2, g:managed_plugin)
PlugDiff
assert_match('1 plugin(s) updated', getline(1))
assert_match('Second version', join(getline(1, '$'), "\n"))
search('Second version')
normal o
var previews = filter(getwininfo(), (_, window) => !empty(getwinvar(window.winid, '&previewwindow')))
assert_equal(1, len(previews))
if !empty(previews)
  assert_match('Second version', join(getbufline(previews[0].bufnr, 1, '$'), "\n"))
  pclose
endif

var snapshot = $VIM9_PLUG_TEST_ROOT .. '/saved snapshot.vim'
execute 'PlugSnapshot!' fnameescape(snapshot)
assert_true(filereadable(snapshot))
final snapshot_text = readfile(snapshot)
if exists('g:vim9_plug_test_upstream')
  assert_match('silent! let g:plugs', join(snapshot_text, "\n"))
else
  assert_equal('vim9script', snapshot_text[0])
  assert_match('g:plugs\[', join(snapshot_text, "\n"))
endif
add(g:observed, string(getline('$')))
PlugDiff
search('Second version')
feedkeys("Xy\<CR>", 'xt')
assert_equal($VIM9_PLUG_TEST_FIRST_SHA, Git(g:plugs.managed.dir, 'rev-parse', 'HEAD'))
execute 'source' fnameescape(snapshot)
assert_equal($VIM9_PLUG_TEST_SECOND_SHA, Git(g:plugs.managed.dir, 'rev-parse', 'HEAD'))

var stale = plugin_home .. '/obsolete clone'
mkdir(stale, 'p')
PlugClean!
assert_true(isdirectory(g:plugs.managed.dir))
assert_false(isdirectory(stale))
assert_match('Removed 1 directories', join(getline(1, '$'), "\n"))

assert_true(plug.Begin())
plug.Add($VIM9_PLUG_TEST_LOCAL, {'as': 'eager'})
plug.End()
assert_equal(['eager'], g:plugs_order)

writefile(g:observed, $VIM9_PLUG_TEST_OUTPUT)
if !empty(v:errors)
  for message in v:errors
    echomsg message
  endfor
  cquit 1
endif
qa!
