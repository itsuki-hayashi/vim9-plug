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

if !exists('g:vim9_plug_test_upstream')
  PlugStatus
  final initial_status = getline(1, '$')
  normal R
  assert_equal(initial_status, getline(1, '$'))
endif

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
var same_name = -1
if !exists('g:vim9_plug_test_upstream')
  execute 'lcd' fnameescape($VIM9_PLUG_TEST_ROOT)
  same_name = bufadd(matchstr(getline('.'), '\x\{7,}'))
  bufload(same_name)
  setbufline(same_name, 1, 'Unsaved file with the same name as the commit')
endif
normal o
var previews = filter(getwininfo(), (_, window) => !empty(getwinvar(window.winid, '&previewwindow')))
assert_equal(1, len(previews))
if !empty(previews)
  assert_match('Second version', join(getbufline(previews[0].bufnr, 1, '$'), "\n"))
  pclose
endif
if same_name >= 0
  assert_equal(['Unsaved file with the same name as the commit'], getbufline(same_name, 1, '$'))
  assert_equal('', getbufvar(same_name, '&buftype'))
  assert_true(getbufvar(same_name, '&modified'))

  execute 'pedit' fnameescape($VIM9_PLUG_TEST_ROOT .. '/other-preview')
  wincmd P
  final previous_preview = bufnr()
  setlocal bufhidden=wipe
  setline(1, 'Unsaved text in an existing preview')
  wincmd p
  normal o
  wincmd P
  assert_notequal(previous_preview, bufnr())
  assert_match('Second version', join(getline(1, '$'), "\n"))
  wincmd p
  pclose
  assert_equal(['Unsaved text in an existing preview'], getbufline(previous_preview, 1, '$'))
  assert_equal('wipe', getbufvar(previous_preview, '&bufhidden'))
  assert_true(getbufvar(previous_preview, '&modified'))
endif

var snapshot = $VIM9_PLUG_TEST_ROOT .. '/saved snapshot.vim'
execute 'PlugSnapshot!' fnameescape(snapshot)
assert_true(filereadable(snapshot))
final snapshot_text = readfile(snapshot)
if exists('g:vim9_plug_test_upstream')
  assert_match('silent! let g:plugs', join(snapshot_text, "\n"))
else
  assert_equal('vim9script', snapshot_text[0])
  assert_match('plug\.Restore(', join(snapshot_text, "\n"))
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

if !exists('g:vim9_plug_test_upstream')
  final managed_dir = g:plugs.managed.dir
  final tagged_dir = g:plugs.tagged.dir
  final frozen_dir = g:plugs.frozen.dir
  final pins_file = $VIM9_PLUG_TEST_ROOT .. '/pinned.vim'
  plug.Begin()
  plug.Add($VIM9_PLUG_TEST_REMOTE, {as: '--sync', dir: managed_dir, frozen: 1,
    commit: $VIM9_PLUG_TEST_FIRST_SHA})
  plug.Add($VIM9_PLUG_TEST_REMOTE, {as: "O'Brien", dir: tagged_dir})
  plug.Add($VIM9_PLUG_TEST_REMOTE, {as: 'removed', dir: frozen_dir})
  plug.End()
  execute 'PlugSnapshot!' fnameescape(pins_file)
  Git(managed_dir, 'checkout', '--detach', $VIM9_PLUG_TEST_FIRST_SHA)

  plug.Begin()
  plug.Add($VIM9_PLUG_TEST_REMOTE, {as: '--sync', dir: managed_dir, frozen: 1})
  plug.Add($VIM9_PLUG_TEST_REMOTE, {as: 'added later'})
  plug.Add($VIM9_PLUG_TEST_LOCAL, {as: "O'Brien"})
  plug.End()
  execute 'source' fnameescape(pins_file)
  assert_equal($VIM9_PLUG_TEST_SECOND_SHA, Git(managed_dir, 'rev-parse', 'HEAD'))
  assert_equal($VIM9_PLUG_TEST_SECOND_SHA, g:plugs['--sync'].commit)
  assert_false(isdirectory(g:plugs['added later'].dir))
  assert_false(has_key(g:plugs["O'Brien"], 'commit'))

  plug.Begin()
  plug.Add($VIM9_PLUG_TEST_REMOTE, {as: 'added later'})
  plug.End()
  final previous_buffer = bufnr()
  execute 'source' fnameescape(pins_file)
  assert_equal(previous_buffer, bufnr())
  assert_false(isdirectory(g:plugs['added later'].dir))
  assert_false(has_key(g:plugs['added later'], 'commit'))
endif

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
