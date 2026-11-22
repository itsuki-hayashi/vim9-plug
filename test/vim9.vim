vim9script

var user_runtime = $VIM9_PLUG_TEST_ROOT .. '/user, runtime'
var first_entry = escape(user_runtime, ',')
var last_entry = escape(user_runtime .. '/after', ',')
mkdir(user_runtime .. '/plugin', 'p')
mkdir(user_runtime .. '/after', 'p')
&rtp = join([first_entry, escape($VIM9_PLUG_TEST_ROOT, ','), &rtp, last_entry], ',')
import autoload 'plug.vim' as plug
g:load_order = []
assert_false(plug.Begin(user_runtime .. '/plugin'))
assert_true(plug.Begin())
assert_equal(user_runtime .. '/plugged', substitute(g:plug_home, '\\', '/', 'g'))
assert_true(plug.Begin($VIM9_PLUG_TEST_ROOT .. '/plugin home'))
assert_equal(0, exists('*plug#begin'))
assert_notequal(2, exists(':Plug'))
var rejected = false
try
  plug.Add('owner/plugin', {tag: 1})
catch /vim9-plug: Invalid "tag" option/
  rejected = true
endtry
assert_true(rejected)
assert_equal([], g:plugs_order)
plug.Add($VIM9_PLUG_TEST_LOCAL, {'as': 'eager'})
plug.End()
if has("vim_starting")
  runtime! plugin/**/*.vim
endif
assert_equal(['eager', 'after eager'], g:load_order)
assert_true(plug.Helptags())
assert_equal(2, exists(':PlugUpgrade'))

# Keep all ancestors and contents of declared plugins when cleaning nested layouts.
final clean_home = $VIM9_PLUG_TEST_ROOT .. '/nested clean'
final nested = clean_home .. '/group/subgroup/keep'
final marker = nested .. '/data/marker'
mkdir(nested .. '/data', 'p')
writefile(['keep'], marker)
mkdir(clean_home .. '/group/subgroup/keep-old', 'p')
mkdir(clean_home .. '/group/stale', 'p')
mkdir(clean_home .. '/unregistered/deep', 'p')
assert_true(plug.Begin(clean_home))
plug.Add(nested)
if has('unix')
  final target = clean_home .. '/link-target'
  final outside = $VIM9_PLUG_TEST_ROOT .. '/outside-clean'
  for dir in [target, outside]
    mkdir(dir, 'p')
    writefile(['keep'], dir .. '/marker')
  endfor
  for [link, dest] in [['active-link', target], ['stale-link', outside]]
    system('ln -s ' .. shellescape(dest) .. ' ' .. shellescape(clean_home .. '/' .. link))
    assert_equal(0, v:shell_error)
  endfor
  mkdir(outside .. '/unmanaged', 'p')
  mkdir(clean_home .. '/pack/vim9-plug', 'p')
  system('ln -s ' .. shellescape(outside) .. ' '
    .. shellescape(clean_home .. '/pack/vim9-plug/opt'))
  assert_equal(0, v:shell_error)
  plug.Add(clean_home .. '/active-link')
endif
plug.End()
PlugClean!
if has('unix')
  assert_equal('link', getftype(clean_home .. '/active-link'))
  assert_true(filereadable(clean_home .. '/link-target/marker'))
  assert_equal('', getftype(clean_home .. '/stale-link'))
  assert_true(isdirectory(clean_home .. '/pack/vim9-plug/opt/unmanaged'))
  assert_true(filereadable($VIM9_PLUG_TEST_ROOT .. '/outside-clean/marker'))
endif
assert_true(filereadable(marker), join(getline(1, '$'), "\n"))
assert_false(isdirectory(clean_home .. '/group/subgroup/keep-old'))
assert_false(isdirectory(clean_home .. '/group/stale'))
assert_false(isdirectory(clean_home .. '/unregistered'))
normal q

var comma_dir = $VIM9_PLUG_TEST_ROOT .. '/comma, ft plugin,'
mkdir(comma_dir .. '/plugin', 'p')
mkdir(comma_dir .. '/after/plugin', 'p')
mkdir(comma_dir .. '/syntax', 'p')
writefile(["call add(g:load_order, 'filetype plugin')"], comma_dir .. '/plugin/test.vim')
writefile(["call add(g:load_order, 'after filetype')"], comma_dir .. '/after/plugin/test.vim')
writefile(["let g:fixture_syntax = 1"], comma_dir .. '/syntax/plugfixture.vim')
var map_dir = $VIM9_PLUG_TEST_ROOT .. '/mapped plugin'
mkdir(map_dir .. '/plugin', 'p')
writefile(['vim9script', 'nnoremap <Plug>(fixture-map) <ScriptCmd>g:fixture_map = v:count<CR>'],
  map_dir .. '/plugin/map.vim')
g:load_order = []
assert_true(plug.Begin())
plug.Add(substitute(comma_dir, '/', has('win32') ? '\' : '/', 'g'),
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

var mixed_dir = $VIM9_PLUG_TEST_ROOT .. '/mixed triggers'
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
assert_equal(last_entry, entries[-1])
assert_true(index(entries, extra_entry) >= 0)
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

var shared_dir = $VIM9_PLUG_TEST_ROOT .. '/shared bindings'
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
plug.Add(comma_dir, {as: 'manual', on: []})
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
