vim9script

execute 'set runtimepath^=' .. fnameescape($VIM9_PLUG_TEST_ROOT)
g:load_order = []
assert_equal(1, plug#begin($VIM9_PLUG_TEST_ROOT .. '/plugin home'))
execute 'Plug' string($VIM9_PLUG_TEST_LOCAL) .. ", {'as': 'eager'}"
assert_equal(0, plug#end())
if has("vim_starting")
  runtime! plugin/**/*.vim
endif
assert_equal(['eager', 'after eager'], g:load_order)
assert_equal(1, plug#helptags())
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
writefile(["nnoremap <Plug>(fixture-map) :<C-U>legacy let g:fixture_map = v:count<CR>"],
  map_dir .. '/plugin/map.vim')
g:load_order = []
assert_equal(1, plug#begin())
plug#(substitute(comma_dir, '/', has('win32') ? '\' : '/', 'g'),
  {as: 'filetype', for: 'plugfixture'})
plug#(map_dir, {as: 'mapping', on: '<Plug>(fixture-map)'})
plug#end()
assert_equal([], g:load_order)
setfiletype plugfixture
assert_equal(['filetype plugin', 'after filetype'], g:load_order)
assert_equal(1, get(g:, 'fixture_syntax', 0))
feedkeys("3\<Plug>(fixture-map)", 'xt')
assert_equal(3, get(g:, 'fixture_map', 0))

writefile(['Vim9 caller'], $VIM9_PLUG_TEST_OUTPUT)
if !empty(v:errors)
  for message in v:errors
    echomsg message
  endfor
  cquit 1
endif
qa!
