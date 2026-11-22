vim9script

set nomore
execute 'set runtimepath^=' .. fnameescape($VIM9_PLUG_TEST_ROOT)
import autoload 'plug.vim' as plug

plug.Begin($VIM9_PLUG_TEST_ROOT .. '/metadata plugins')
plug.Add($VIM9_PLUG_TEST_METADATA_URI, {as: 'packed', branch: 'm.in'})
plug.Add($VIM9_PLUG_TEST_METADATA_URI, {as: 'linked'})
plug.End()

var rejected = false
try
  plug.Restore({packed: $VIM9_PLUG_TEST_FIRST_SHA, linked: ''})
catch /vim9-plug: Invalid commit ID/
  rejected = true
endtry
assert_true(rejected)
assert_false(has_key(g:plugs.packed, 'commit'))
assert_false(has_key(g:plugs.linked, 'commit'))

PlugStatus
assert_equal('Finished. 0 error(s).', getline(1), join(getline(1, '$'), "\n"))
PlugSnapshot
for name in ['packed', 'linked']
  final pin = printf("  '%s': '%s',", name, $VIM9_PLUG_TEST_FIRST_SHA)
  assert_true(index(getline(1, '$'), pin) >= 0, join(getline(1, '$'), "\n"))
endfor
PlugClean!
assert_true(filereadable(g:plugs.linked.dir .. '/.git'), join(getline(1, '$'), "\n"))

plug.Add($VIM9_PLUG_TEST_REMOTE, {as: 'tagged', tag: 'v1'})
PlugInstall tagged --sync
assert_notmatch('x tagged:', join(getline(1, '$'), "\n"))
PlugStatus
assert_equal('Finished. 0 error(s).', getline(1), join(getline(1, '$'), "\n"))

# An unreadable Git configuration gives no evidence that the checkout is unused.
writefile(['[broken'], g:plugs.tagged.dir .. '/.git/config')
PlugClean!
assert_true(isdirectory(g:plugs.tagged.dir .. '/.git'))
PlugStatus
assert_match('Unable to read the Git configuration', join(getline(1, '$'), "\n"))

writefile(['Tagged installs, linked worktrees and packed refs'], $VIM9_PLUG_TEST_OUTPUT)
if !empty(v:errors)
  for message in v:errors
    echomsg message
  endfor
  cquit 1
endif
qa!
