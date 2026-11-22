vim9script

final home = $VIM9_PLUG_TEST_ROOT .. '/package home'
final native = home .. '/pack/vim9-plug/opt'
final foreign = $VIM9_PLUG_TEST_ROOT .. '/external packages'

if !exists('g:package_runs')
  final user_dir = escape($VIM9_PLUG_TEST_ROOT, ',')
  &rtp = join([user_dir, escape($VIMRUNTIME, ','), user_dir .. '/after'], ',')
  &packpath = escape(foreign, ',') .. ',' .. escape($VIMRUNTIME, ',')
endif
import autoload 'plug.vim' as plug

def MakePlugin(directory: string, marker: string, ...commands: list<string>)
  mkdir(directory .. '/plugin', 'p')
  writefile([$"call add(g:package_runs, '{marker}')"] + commands,
    directory .. '/plugin/fixture.vim')
enddef

def RuntimeDirs(): list<string>
  return mapnew(split(&rtp, '\\\@<!,'), (_, entry) => substitute(entry, '\\', '/', 'g'))
enddef

# This script is sourced first as the vimrc, then again via -S after Vim
# completes its native plugin loading pass.
if !exists('g:package_runs')
  g:package_runs = []
  MakePlugin(native .. '/native-eager', 'eager')
  MakePlugin(native .. '/native-eager/after', 'after eager')
  MakePlugin(native .. '/native-lazy', 'lazy',
    'command! -nargs=1 PackageFixture let g:package_argument = <q-args>')
  MakePlugin(native .. '/native-lazy/after', 'after lazy')
  MakePlugin(native .. '/native-manual', 'manual')
  MakePlugin(home .. '/pack/foreign/opt/native-blocked', 'ignored name collision')
  MakePlugin(native .. '/native-stale', 'stale')
  MakePlugin(foreign .. '/pack/foreign/start/independent', 'independent start')
  MakePlugin(foreign .. '/pack/foreign/opt/native-lazy', 'name collision')
  MakePlugin(home .. '/legacy', 'flat')
  set wildignore+=*/pack/foreign/opt/native-blocked

  final lazy = native .. '/native-lazy'
  mkdir(lazy .. '/ftdetect', 'p')
  writefile(['autocmd BufNewFile *.packfixture setfiletype packfixture'],
    lazy .. '/ftdetect/fixture.vim')
  mkdir(lazy .. '/ftplugin', 'p')
  writefile(['let b:package_ftplugin = 1'], lazy .. '/ftplugin/packfixture.vim')

  assert_true(plug.Begin(home))
  plug.Add($VIM9_PLUG_TEST_REMOTE, {as: 'native-eager'})
  plug.Add($VIM9_PLUG_TEST_REMOTE, {as: 'native-lazy', on: 'PackageFixture', for: 'packfixture'})
  plug.Add($VIM9_PLUG_TEST_REMOTE, {as: 'native-manual', on: []})
  plug.Add($VIM9_PLUG_TEST_REMOTE, {as: 'legacy'})
  assert_equal(native .. '/legacy/', substitute(g:plugs.legacy.dir, '\\', '/', 'g'))
  var collision = false
  try
    plug.Add($VIM9_PLUG_TEST_REMOTE, {as: 'native-blocked'})
  catch /^vim9-plug:/
    collision = true
  endtry
  assert_true(collision)
  assert_false(has_key(g:plugs, 'native-blocked'))
  plug.End()
  assert_equal([], g:package_runs)
  finish
endif

assert_equal(index(v:argv, '--noplugin') < 0, &loadplugins)
if &loadplugins
  assert_equal(['after eager', 'eager', 'independent start'],
    sort(copy(g:package_runs)))
  assert_true(index(g:package_runs, 'eager') < index(g:package_runs, 'after eager'))
else
  assert_equal([], g:package_runs)
endif
final startup_dirs = RuntimeDirs()
final vim_runtime = substitute($VIMRUNTIME, '\\', '/', 'g')
assert_equal(1, count(startup_dirs, native .. '/native-eager'))
assert_equal(1, count(startup_dirs, native .. '/native-eager/after'))
final runtime_index = index(startup_dirs, vim_runtime)
assert_true(runtime_index >= 0 && runtime_index < index(startup_dirs, native .. '/native-eager'),
  string(startup_dirs) .. ' vs ' .. vim_runtime)
assert_equal(-1, index(startup_dirs, native .. '/native-lazy'))
assert_equal(-1, index(startup_dirs, native .. '/native-manual'))

final before = len(g:package_runs)
if &loadplugins
  final late_collision = home .. '/pack/foreign/opt/native-lazy'
  MakePlugin(late_collision, 'late collision')
  var rejected = false
  try
    plug.Load(['native-lazy'])
  catch /^vim9-plug:/
    rejected = true
  endtry
  assert_true(rejected)
  assert_equal(before, len(g:package_runs))
  assert_equal(0, rename(late_collision, late_collision .. '-renamed'))

  execute 'edit' fnameescape($VIM9_PLUG_TEST_ROOT .. '/buffer.packfixture')
  assert_equal('packfixture', &filetype)
  assert_equal(1, get(b:, 'package_ftplugin', 0))
endif
PackageFixture packaged
assert_equal('packaged', g:package_argument)
assert_equal(['lazy', 'after lazy'], g:package_runs[before :])
assert_equal(1, count(RuntimeDirs(), native .. '/native-lazy'))
assert_equal(-1, index(RuntimeDirs(), foreign .. '/pack/foreign/opt/native-lazy'))
assert_false(plug.Load(['native-lazy']))
assert_true(plug.Load(['native-manual']))
assert_false(plug.Load(['native-manual']))
assert_equal('manual', g:package_runs[-1])
assert_equal(-1, index(RuntimeDirs(), home .. '/pack/foreign/opt/native-blocked'))

if &loadplugins
  final manual = native .. '/native-manual'
  assert_false(isdirectory(manual .. '/after'))
  mkdir(manual .. '/after')
  plug.End()
  final updated_dirs = RuntimeDirs()
  assert_equal(1, count(updated_dirs, manual))
  assert_equal(1, count(updated_dirs, manual .. '/after'))
endif

packadd native-stale
assert_equal('stale', g:package_runs[-1])

assert_true(plug.Begin())
plug.Add($VIM9_PLUG_TEST_REMOTE, {as: 'native-manual', on: []})
plug.End()
final redeclared_dirs = RuntimeDirs()
assert_equal(-1, index(redeclared_dirs, native .. '/native-eager'))
assert_equal(-1, index(redeclared_dirs, native .. '/native-eager/after'))
assert_equal(-1, index(redeclared_dirs, native .. '/native-lazy'))
assert_equal(1, count(redeclared_dirs, native .. '/native-manual'))
assert_equal(1, count(redeclared_dirs, native .. '/native-stale'))

writefile(['Native packages'], $VIM9_PLUG_TEST_OUTPUT)
if !empty(v:errors)
  for message in v:errors
    echomsg message
  endfor
  cquit 1
endif
qa!
