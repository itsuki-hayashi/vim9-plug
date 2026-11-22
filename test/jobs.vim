vim9script

set nomore
execute 'set runtimepath^=' .. fnameescape($VIM9_PLUG_TEST_ROOT)
import autoload 'plug.vim' as plug

def WaitFor(Predicate: func(): bool, message: string)
  var start = reltime()
  while !Predicate() && reltimefloat(reltime(start)) < 8.0
    sleep 20m
  endwhile
  assert_true(Predicate(), message .. ': ' .. join(getline(1, '$'), "\n"))
enddef

def Run()
  g:load_order = []
  var home = $VIM9_PLUG_TEST_ROOT .. '/job plugins'
  plug.Begin(home)
  var missing = $VIM9_PLUG_TEST_REMOTE .. '.does-not-exist'
  plug.Add(missing, {'as': 'failure'})
  plug.Add($VIM9_PLUG_TEST_REMOTE, {as: 'available', do: ':g:fixture_hook = 1'})
  plug.End()

  var previous_directory = getcwd()
  var previous_shell = [&shell, &shellcmdflag, &shellredir]
  $GIT_TERMINAL_PROMPT = '1'
  execute 'PlugInstall 2'
  WaitFor(() => getline(1) =~ '^Updated\.', 'Asynchronous install')
  assert_match('x failure:', join(getline(1, '$'), "\n"))
  assert_match('fatal:', join(getline(1, '$'), "\n"))
  assert_true(isdirectory(g:plugs.available.dir .. '/.git'))
  assert_equal(1, get(g:, 'fixture_hook', 0))
  assert_equal('1', $GIT_TERMINAL_PROMPT)
  assert_equal(previous_shell, [&shell, &shellcmdflag, &shellredir])
  assert_equal(previous_directory, getcwd())

  g:plugs.failure.uri = $VIM9_PLUG_TEST_REMOTE
  normal R
  WaitFor(() => isdirectory(g:plugs.failure.dir .. '/.git') && getline(1) =~ '^Updated\.', 'Retry')

  if exists('$VIM9_PLUG_TEST_SLOW')
    plug.Add($VIM9_PLUG_TEST_REMOTE, {'as': 'slow'})
    execute 'PlugInstall slow'
    WaitFor(() => isdirectory(g:plugs.slow.dir), 'Slow clone started')
    normal q
    WaitFor(() => getline(1) =~ '^Updated\.', 'Cancel from pane')
    assert_match('Aborted', join(getline(1, '$'), "\n"))
    assert_false(isdirectory(g:plugs.slow.dir))
    execute 'PlugInstall slow'
    WaitFor(() => isdirectory(g:plugs.slow.dir), 'Second slow clone started')
    execute 'PlugStatus'
    assert_false(isdirectory(g:plugs.slow.dir))
    assert_match('^Finished\.', getline(1))

    plug.Add($VIM9_PLUG_TEST_REMOTE, {'as': 'missing-git'})
    var old_path = $PATH
    try
      $PATH = $VIM9_PLUG_TEST_ROOT .. '/no-executables'
      execute 'PlugInstall missing-git --sync'
      assert_match('x missing-git:', join(getline(1, '$'), "\n"))
      assert_false(isdirectory(g:plugs['missing-git'].dir))
    finally
      $PATH = old_path
    endtry
  endif

  writefile(['Install failure, retry and job ownership'], $VIM9_PLUG_TEST_OUTPUT)
  if !empty(v:errors)
    for message in v:errors
      echomsg message
    endfor
    cquit 1
  endif
  qa!
enddef

if has('job') && has('channel')
  autocmd VimEnter * ++once Run()
else
  writefile(['Job scenarios require jobs and channels'], $VIM9_PLUG_TEST_OUTPUT)
  qa!
endif
