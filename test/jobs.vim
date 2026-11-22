set nomore
execute 'set runtimepath^=' .. fnameescape($VIM9_PLUG_TEST_ROOT)

function! s:WaitFor(predicate, message)
  let start = reltime()
  while !a:predicate() && reltimefloat(reltime(start)) < 8.0
    sleep 20m
  endwhile
  call assert_true(a:predicate(), a:message .. ': ' .. join(getline(1, '$'), "\n"))
endfunction

function! s:Run()
  let g:load_order = []
  let home = $VIM9_PLUG_TEST_ROOT .. '/job plugins'
  call plug#begin(home)
  let missing = $VIM9_PLUG_TEST_REMOTE .. '.does-not-exist'
  execute 'Plug' string(missing) .. ", {'as': 'failure'}"
  execute 'Plug' string($VIM9_PLUG_TEST_REMOTE) .. ", {'as': 'available'}"
  call plug#end()

  let previous_directory = getcwd()
  let previous_shell = [&shell, &shellcmdflag, &shellredir]
  let $GIT_TERMINAL_PROMPT = '1'
  PlugInstall 2
  call s:WaitFor({-> getline(1) =~ '^Updated\.'}, 'Asynchronous install')
  call assert_match('x failure:', join(getline(1, '$'), "\n"))
  call assert_match('fatal:', join(getline(1, '$'), "\n"))
  call assert_true(isdirectory(g:plugs.available.dir .. '/.git'))
  call assert_equal('1', $GIT_TERMINAL_PROMPT)
  call assert_equal(previous_shell, [&shell, &shellcmdflag, &shellredir])
  call assert_equal(previous_directory, getcwd())

  let g:plugs.failure.uri = $VIM9_PLUG_TEST_REMOTE
  normal R
  call s:WaitFor({-> isdirectory(g:plugs.failure.dir .. '/.git') && getline(1) =~ '^Updated\.'}, 'Retry')

  if exists('$VIM9_PLUG_TEST_SLOW')
    execute 'Plug' string($VIM9_PLUG_TEST_REMOTE) .. ", {'as': 'slow'}"
    PlugInstall slow
    call s:WaitFor({-> isdirectory(g:plugs.slow.dir)}, 'Slow clone started')
    normal q
    call s:WaitFor({-> getline(1) =~ '^Updated\.'}, 'Cancel from pane')
    call assert_match('Aborted', join(getline(1, '$'), "\n"))
    call assert_false(isdirectory(g:plugs.slow.dir))
    PlugInstall slow
    call s:WaitFor({-> isdirectory(g:plugs.slow.dir)}, 'Second slow clone started')
    PlugStatus
    call assert_false(isdirectory(g:plugs.slow.dir))
    call assert_match('^Finished\.', getline(1))

    execute 'Plug' string($VIM9_PLUG_TEST_REMOTE) .. ", {'as': 'missing-git'}"
    let old_path = $PATH
    try
      let $PATH = $VIM9_PLUG_TEST_ROOT .. '/no-executables'
      PlugInstall missing-git --sync
      call assert_match('x missing-git:', join(getline(1, '$'), "\n"))
      call assert_false(isdirectory(g:plugs['missing-git'].dir))
    finally
      let $PATH = old_path
    endtry
  endif

  call writefile(['Install failure, retry and job ownership'], $VIM9_PLUG_TEST_OUTPUT)
  if !empty(v:errors)
    for message in v:errors
      echomsg message
    endfor
    cquit 1
  endif
  qa!
endfunction

if has('job') && has('channel')
  autocmd VimEnter * ++once call s:Run()
else
  call writefile(['Job scenarios require jobs and channels'], $VIM9_PLUG_TEST_OUTPUT)
  qa!
endif
