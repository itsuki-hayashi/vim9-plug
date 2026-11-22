vim9script

set nomore
execute 'set runtimepath^=' .. fnameescape($VIM9_PLUG_TEST_ROOT)
import autoload 'plug.vim' as plug

def EscapeFromCompiledCaller(): string
  return plug.ShellEscape('two words', 'sh')
enddef

g:load_order = []
assert_true(plug.Begin($VIM9_PLUG_TEST_ROOT .. '/plugin home'))
plug.Add($VIM9_PLUG_TEST_LAZY, {'as': 'lazy', 'on': 'FixtureLazy'})
plug.End()

var script = $VIM9_PLUG_TEST_ROOT .. '/autoload/plug.vim'
var initial = readfile(script, 'b')
assert_equal("'two words'", EscapeFromCompiledCaller())
$GIT_CONFIG_KEY_0 = 'url.' .. $VIM9_PLUG_TEST_GOOD_URL .. '.insteadOf'
PlugUpgrade
assert_equal(1, get(g:, 'upgrade_fixture', 0))
assert_equal("'two words'", EscapeFromCompiledCaller())
assert_equal(initial, readfile(script .. '.old', 'b'))
assert_equal(['lazy'], g:plugs_order)
var installed = readfile(script, 'b')
PlugUpgrade
assert_equal(installed, readfile(script, 'b'))

$GIT_CONFIG_KEY_0 = 'url.' .. $VIM9_PLUG_TEST_BAD_URL .. '.insteadOf'
PlugUpgrade
assert_equal(installed, readfile(script, 'b'))
assert_equal(['lazy'], g:plugs_order)
assert_equal("'two words'", EscapeFromCompiledCaller())
FixtureLazy! test after rollback
assert_equal([1, 1, 1, 'test after rollback'], g:lazy_call)
assert_equal(['lazy'], g:load_order)

writefile(['Self-upgrade and rollback'], $VIM9_PLUG_TEST_OUTPUT)
if !empty(v:errors)
  for message in v:errors
    echomsg message
  endfor
  cquit 1
endif
qa!
