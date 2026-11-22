set nomore
execute 'set runtimepath^=' .. fnameescape($VIM9_PLUG_TEST_ROOT)
let g:load_order = []
call assert_equal(1, plug#begin($VIM9_PLUG_TEST_ROOT .. '/plugin home'))
execute 'Plug' string($VIM9_PLUG_TEST_LAZY) .. ", {'as': 'lazy', 'on': 'FixtureLazy'}"
call plug#end()

let script = $VIM9_PLUG_TEST_ROOT .. '/autoload/plug.vim'
let initial = readfile(script, 'b')
let $GIT_CONFIG_KEY_0 = 'url.' .. $VIM9_PLUG_TEST_GOOD_URL .. '.insteadOf'
PlugUpgrade
call assert_equal(1, get(g:, 'upgrade_fixture', 0))
call assert_equal(initial, readfile(script .. '.old', 'b'))
call assert_equal(['lazy'], g:plugs_order)
let installed = readfile(script, 'b')
PlugUpgrade
call assert_equal(installed, readfile(script, 'b'))

let $GIT_CONFIG_KEY_0 = 'url.' .. $VIM9_PLUG_TEST_BAD_URL .. '.insteadOf'
PlugUpgrade
call assert_equal(installed, readfile(script, 'b'))
call assert_equal(['lazy'], g:plugs_order)
FixtureLazy! test after rollback
call assert_equal([1, 1, 1, 'test after rollback'], g:lazy_call)
call assert_equal(['lazy'], g:load_order)

call writefile(['Self-upgrade and rollback'], $VIM9_PLUG_TEST_OUTPUT)
if !empty(v:errors)
  for message in v:errors
    echomsg message
  endfor
  cquit 1
endif
qa!
