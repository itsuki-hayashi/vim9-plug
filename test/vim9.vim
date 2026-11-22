vim9script

execute 'set runtimepath^=' .. fnameescape($VIM9_PLUG_TEST_ROOT)
import autoload 'plug.vim' as plug
g:load_order = []
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

var comma_dir = $VIM9_PLUG_TEST_ROOT .. '/comma, ft plugin'
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
feedkeys("3\<Plug>(fixture-map)", 'xt')
assert_equal(3, get(g:, 'fixture_map', 0))

assert_true(plug.Begin())
plug.Add(comma_dir, {as: 'manual', on: []})
plug.Add($VIM9_PLUG_TEST_LAZY, {as: 'status-one', on: []})
plug.Add(map_dir, {as: 'status-two', on: []})
plug.End()
assert_false(plug.Load([]))
assert_true(plug.Load(['manual']))
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
