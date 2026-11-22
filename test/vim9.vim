vim9script

final user_runtime = $VIM9_PLUG_TEST_ROOT .. '/user runtime'
final first_entry = escape(user_runtime, ',')
final last_entry = escape(user_runtime .. '/after', ',')
final fixture_home = $VIM9_PLUG_TEST_ROOT .. '/plugin home'
final fixture_opt = fixture_home .. '/pack/vim9-plug/opt'
mkdir(user_runtime .. '/plugin', 'p')
mkdir(user_runtime .. '/after', 'p')
&rtp = join([first_entry, escape($VIM9_PLUG_TEST_ROOT, ','), &rtp, last_entry], ',')
import autoload 'plug.vim' as plug

def AssertRejected(repository: string, options: dict<any> = {})
  var rejected = false
  try
    plug.Add(repository, options)
  catch /^vim9-plug:/
    rejected = true
  endtry
  assert_true(rejected, repository .. ' ' .. string(options))
enddef

g:load_order = []
assert_false(plug.Begin(user_runtime .. '/plugin'))
assert_false(plug.Begin($VIM9_PLUG_TEST_ROOT .. '/comma, home'))
assert_false(plug.Begin($VIM9_PLUG_TEST_ROOT .. '/[glob] home'))
assert_true(plug.Begin())
assert_equal(user_runtime .. '/plugged', substitute(g:plug_home, '\\', '/', 'g'))
assert_true(plug.Begin(fixture_home))
assert_equal(0, exists('*plug#begin'))
assert_notequal(2, exists(':Plug'))
AssertRejected('owner/plugin', {tag: 1})
AssertRejected('owner/plugin', {dir: user_runtime})
AssertRejected('owner/plugin', {rtp: 'vim'})
AssertRejected('owner/plugin', {as: 'invalid name'})
AssertRejected('owner/plugin', {as: '..'})
AssertRejected(user_runtime)
assert_equal([], g:plugs_order)
plug.Add($VIM9_PLUG_TEST_LOCAL, {'as': 'eager'})
plug.End()
if has("vim_starting")
  runtime! plugin/**/*.vim
endif
assert_equal(['eager', 'after eager'], g:load_order)
assert_true(plug.Helptags())
assert_equal(2, exists(':PlugUpgrade'))

# Clean only the managed native package tree.
final clean_home = $VIM9_PLUG_TEST_ROOT .. '/clean packages'
final clean_opt = clean_home .. '/pack/vim9-plug/opt'
final keep = clean_opt .. '/keep'
final marker = keep .. '/data/marker'
final outside = $VIM9_PLUG_TEST_ROOT .. '/outside-clean'
mkdir(keep .. '/data', 'p')
writefile(['keep'], marker)
mkdir(clean_opt .. '/keep-old', 'p')
mkdir(clean_home .. '/unregistered/deep', 'p')
assert_true(plug.Begin(clean_home))
plug.Add(keep)
if has('unix')
  final target = clean_home .. '/link-target'
  for dir in [target, outside]
    mkdir(dir, 'p')
    writefile(['keep'], dir .. '/marker')
  endfor
  for [link, dest] in [['active-link', target], ['stale-link', outside]]
    system('ln -s ' .. shellescape(dest) .. ' ' .. shellescape(clean_opt .. '/' .. link))
    assert_equal(0, v:shell_error)
  endfor
  plug.Add(clean_opt .. '/active-link')
endif
plug.End()
PlugClean!
if has('unix')
  assert_equal('link', getftype(clean_opt .. '/active-link'))
  assert_true(filereadable(clean_home .. '/link-target/marker'))
  assert_true(filereadable(outside .. '/marker'))
endif
assert_true(filereadable(marker), join(getline(1, '$'), "\n"))
assert_false(isdirectory(clean_opt .. '/keep-old'))
assert_true(isdirectory(clean_home .. '/unregistered/deep'))
normal q

if has('unix')
  final link_home = $VIM9_PLUG_TEST_ROOT .. '/linked clean packages'
  final link_group = link_home .. '/pack/vim9-plug'
  mkdir(link_group, 'p')
  mkdir(outside .. '/unmanaged', 'p')
  system('ln -s ' .. shellescape(outside) .. ' ' .. shellescape(link_group .. '/opt'))
  assert_equal(0, v:shell_error)
  assert_true(plug.Begin(link_home))
  plug.End()
  PlugClean!
  assert_true(isdirectory(outside .. '/unmanaged'))
  normal q
endif

final ft_dir = fixture_opt .. '/ft'
mkdir(ft_dir .. '/plugin', 'p')
mkdir(ft_dir .. '/after/plugin', 'p')
mkdir(ft_dir .. '/syntax', 'p')
writefile(["call add(g:load_order, 'filetype plugin')"], ft_dir .. '/plugin/test.vim')
writefile(["call add(g:load_order, 'after filetype')"], ft_dir .. '/after/plugin/test.vim')
writefile(["let g:fixture_syntax = 1"], ft_dir .. '/syntax/plugfixture.vim')
final map_dir = fixture_opt .. '/mapped-plugin'
mkdir(map_dir .. '/plugin', 'p')
writefile(['vim9script', 'nnoremap <Plug>(fixture-map) <ScriptCmd>g:fixture_map = v:count<CR>'],
  map_dir .. '/plugin/map.vim')
g:load_order = []
assert_true(plug.Begin(fixture_home))
plug.Add(substitute(ft_dir, '/', has('win32') ? '\' : '/', 'g'),
  {as: 'filetype', for: 'plugfixture'})
plug.Add(map_dir, {as: 'mapping', on: '<Plug>(fixture-map)'})
plug.End()
assert_equal([], g:load_order)
setfiletype plugfixture
assert_equal(['filetype plugin', 'after filetype'], g:load_order)
assert_equal(1, get(g:, 'fixture_syntax', 0))
assert_equal(1, len(globpath(&rtp, 'syntax/plugfixture.vim', false, true)))
feedkeys("3\<Plug>(fixture-map)", 'xt')
assert_equal(3, get(g:, 'fixture_map', 0))

final mixed_dir = fixture_opt .. '/mixed-triggers'
mkdir(mixed_dir .. '/plugin', 'p')
mkdir(mixed_dir .. '/syntax', 'p')
writefile([
  'vim9script',
  'g:mixed_loads += 1',
  'command! -bang -range -nargs=* FixtureRange g:fixture_range = [<range>, <line1>, <line2>, <bang>0, <q-args>]',
], mixed_dir .. '/plugin/mixed.vim')
writefile(['let g:mixed_syntax = 1'], mixed_dir .. '/syntax/plugmixed.vim')
g:mixed_loads = 0
g:mixed_events = 0
autocmd User mixed g:mixed_events += 1
command FixtureExisting g:fixture_existing = true
xnoremap <Plug>(existing-visual) :echo 'existing'<CR>
final existing_map = maparg('<Plug>(existing-visual)', 'x')
var extra_entry = escape($VIM9_PLUG_TEST_ROOT .. '/added, runtime', ',')
&rtp ..= ',' .. extra_entry
assert_true(plug.Begin())
plug.Add(mixed_dir, {as: 'mixed', for: ['plugmixed', 'plugother'],
  on: ['FixtureRange', 'FixtureExisting', '<Plug>(existing-visual)']})
plug.End()
plug.End()
var entries = split(&rtp, '\\\@<!,')
assert_equal(first_entry, entries[0])
assert_equal([last_entry, extra_entry], entries[-2 :])
assert_equal([], globpath(&rtp, 'syntax/plugfixture.vim', false, true))
setline(1, ['first', 'second'])
cursor(1, 1)
silent :2FixtureRange! test
assert_equal([1, 2, 2, true, 'test'], g:fixture_range)
assert_equal(2, exists(':FixtureExisting'))
assert_equal(existing_map, maparg('<Plug>(existing-visual)', 'x'))
set filetype=plugmixed
assert_equal(1, get(g:, 'mixed_syntax', 0))
set filetype=plugother
assert_equal(1, g:mixed_loads)
assert_equal(1, g:mixed_events)

final shared_dir = fixture_opt .. '/shared-bindings'
mkdir(shared_dir .. '/plugin', 'p')
writefile(['vim9script', 'command FixtureFirst echo "first"',
  'command FixtureShared g:shared_call = true',
  'nnoremap <Plug>(fixture-shared) <Cmd>echo "first"<CR>'], shared_dir .. '/plugin/shared.vim')
assert_true(plug.Begin())
plug.Add(shared_dir, {as: 'first', on: ['FixtureFirst', 'FixtureShared', '<Plug>(fixture-shared)']})
plug.Add(map_dir, {as: 'second', on: ['FixtureShared', '<Plug>(fixture-shared)',
  'FixtureReplaced', '<Plug>(fixture-replaced)', 'FixtureMasked', '<Plug>(fixture-masked)']})
plug.End()
FixtureFirst
final shared_map = maparg('<Plug>(fixture-shared)', 'n')
assert_notequal('', shared_map)
command! FixtureReplaced g:replacement_called = true
xnoremap <Plug>(fixture-replaced) <Cmd>echo "user"<CR>
command -buffer FixtureMasked g:masked_called = true
nnoremap <buffer> <Plug>(fixture-masked) <Cmd>echo "local"<CR>
final caller = win_getid()
assert_true(plug.Load(['second']))
assert_equal(caller, win_getid())
FixtureShared
FixtureReplaced
FixtureMasked
assert_true(g:shared_call && g:replacement_called && g:masked_called)
assert_equal(shared_map, maparg('<Plug>(fixture-shared)', 'n'))
assert_equal('<Cmd>echo "user"<CR>', maparg('<Plug>(fixture-replaced)', 'x'))
assert_equal('', maparg('<Plug>(fixture-replaced)', 's'))
assert_equal('', maparg('<Plug>(fixture-replaced)', 'n'))
assert_equal('<Cmd>echo "local"<CR>', maparg('<Plug>(fixture-masked)', 'n'))
new
assert_equal(0, exists(':FixtureMasked'))
assert_equal('', maparg('<Plug>(fixture-masked)', 'n'))
close

assert_true(plug.Begin())
plug.Add(ft_dir, {as: 'manual', on: []})
plug.Add($VIM9_PLUG_TEST_LAZY, {as: 'status-one', on: []})
plug.Add(map_dir, {as: 'status-two', on: []})
plug.End()
assert_false(plug.Load([]))
g:load_order = []
assert_true(plug.Load(['manual', 'manual']))
assert_equal(['filetype plugin', 'after filetype'], g:load_order)
assert_false(plug.Load(['manual']))
PlugStatus
assert_equal(2, len(filter(getline(4, '$'), (_, text) => text =~ '(not loaded)')))
normal! 4GVG
normal L
assert_equal(0, len(filter(getline(4, '$'), (_, text) => text =~ '(not loaded)')))
assert_false(plug.Load(['status-one', 'status-two']))

writefile(['Vim9 caller'], $VIM9_PLUG_TEST_OUTPUT)
if !empty(v:errors)
  for message in v:errors
    echomsg message
  endfor
  cquit 1
endif
qa!
