set nomore
execute 'set runtimepath^=' .. fnameescape($VIM9_PLUG_TEST_ROOT)
let g:load_order = []
let g:observed = []
let plugin_home = $VIM9_PLUG_TEST_ROOT .. '/plugin home'

function! s:Git(dir, ...)
  let opts = {'shell': &shell, 'script': 0}
  let dir = has('win32') ? substitute(a:dir, '\\', '/', 'g') : a:dir
  let argv = ['git', '-C', substitute(dir, '/\+$', '', '')] + a:000
  let command = join(map(argv, {_, arg -> plug#shellescape(arg, opts)}))
  let prefix = &shell =~? '\%(pwsh\|powershell\)\%(\.exe\)\?$' ? '& ' : ''
  let result = system(prefix .. command)
  call assert_equal(0, v:shell_error, command .. ': ' .. result)
  return trim(result)
endfunction

call assert_equal(1, plug#begin(plugin_home))
execute 'Plug' string($VIM9_PLUG_TEST_LOCAL) .. ", {'as': 'eager'}"
execute 'Plug' string($VIM9_PLUG_TEST_LAZY) .. ", {'as': 'lazy', 'on': ['FixtureLazy', '<Plug>(fixture-lazy)']}"
execute 'Plug' string($VIM9_PLUG_TEST_REMOTE) .. ", {'as': 'managed', 'branch': 'main', 'do': { info -> add(g:observed, string(info.status)) }}"
execute 'Plug' string($VIM9_PLUG_TEST_REMOTE) .. ", {'as': 'tagged', 'tag': 'v*'}"
execute 'Plug' string($VIM9_PLUG_TEST_REMOTE) .. ", {'as': 'frozen', 'frozen': 1, 'on': []}"
call assert_equal(['eager', 'lazy', 'managed', 'tagged', 'frozen'], g:plugs_order)
call assert_equal(0, plug#end())
if has("vim_starting")
  runtime! plugin/**/*.vim
endif
call assert_equal(['eager', 'after eager'], g:load_order)
call assert_equal(0, get(g:, 'managed_plugin', 0))
call assert_equal(2, exists(':FixtureLazy'))
call assert_equal(1, plug#helptags())
call assert_true(filereadable($VIM9_PLUG_TEST_LOCAL .. '/doc/tags'))
call assert_equal(["'a b'", '^"a b^"', "'a b'"], map(['sh', 'cmd.exe', 'pwsh'],
      \ {_, sh -> plug#shellescape('a b', {'shell': sh, 'script': 0})}))
call assert_equal('^"^^%%PATH^^%%^"', plug#shellescape('^%PATH^%', {'shell': 'cmd.exe'}))
call assert_equal('^"^^^%PATH^^^%^"',
      \ plug#shellescape('^%PATH^%', {'shell': 'cmd.exe', 'script': 0}))
call assert_equal('''\"Foo\\''''\\Bar\"''',
      \ plug#shellescape('"Foo\''\Bar"', {'shell': 'powershell.exe'}))

call setline(1, ['first', 'second'])
1,2FixtureLazy! hello world
call assert_equal([1, 1, 2, 'hello world'], g:lazy_call)
call assert_equal(0, plug#load(['lazy']))
call assert_equal(['eager', 'after eager', 'lazy'], g:load_order)
call add(g:observed, string(g:load_order))

PlugInstall --sync 2
call assert_true(isdirectory(g:plugs.managed.dir .. '/.git'), getline(1, '$')->join("\n"))
call assert_true(filereadable(g:plugs.managed.dir .. '/vendor/submodule/.git'),
      \ join(getline(1, '$'), "\n"))
call assert_equal(1, get(g:, 'managed_plugin', 0))
call assert_equal(['managed'], getcompletion('PlugUpdate ma', 'cmdline'))
call assert_equal($VIM9_PLUG_TEST_FIRST_SHA, s:Git(g:plugs.managed.dir, 'rev-parse', 'HEAD'))
call assert_equal($VIM9_PLUG_TEST_FIRST_SHA, s:Git(g:plugs.tagged.dir, 'rev-parse', 'HEAD'))
call assert_equal($VIM9_PLUG_TEST_FIRST_SHA, s:Git(g:plugs.frozen.dir, 'rev-parse', 'HEAD'))

PlugStatus
call assert_equal('Finished. 0 error(s).', getline(1))
call add(g:observed, getline(1))
call add(g:observed, string(sort(getline(4, '$'))))

call s:Git($VIM9_PLUG_TEST_GIT_REPO, 'update-ref', 'refs/heads/main', 'refs/fixtures/next')
call s:Git($VIM9_PLUG_TEST_GIT_REPO, 'tag', 'v2', 'refs/fixtures/next')
PlugUpdate --sync
call assert_equal($VIM9_PLUG_TEST_SECOND_SHA, s:Git(g:plugs.managed.dir, 'rev-parse', 'HEAD'),
      \ join(getline(1, '$'), "\n"))
call assert_equal($VIM9_PLUG_TEST_FIRST_SHA, s:Git(g:plugs.frozen.dir, 'rev-parse', 'HEAD'))
call assert_equal($VIM9_PLUG_TEST_SECOND_SHA, s:Git(g:plugs.tagged.dir, 'rev-parse', 'HEAD'))
call assert_equal(2, g:managed_plugin)
PlugDiff
call assert_match('1 plugin(s) updated', getline(1))
call assert_match('Second version', join(getline(1, '$'), "\n"))
call search('Second version')
normal o
let previews = filter(getwininfo(), {_, window -> getwinvar(window.winid, '&previewwindow')})
call assert_equal(1, len(previews))
if !empty(previews)
  call assert_match('Second version', join(getbufline(previews[0].bufnr, 1, '$'), "\n"))
  pclose
endif

let snapshot = $VIM9_PLUG_TEST_ROOT .. '/saved snapshot.vim'
execute 'PlugSnapshot!' fnameescape(snapshot)
call assert_true(filereadable(snapshot))
call assert_match('silent! let g:plugs', join(readfile(snapshot), "\n"))
call add(g:observed, string(getline('$')))
PlugDiff
call search('Second version')
call feedkeys("Xy\<CR>", 'xt')
call assert_equal($VIM9_PLUG_TEST_FIRST_SHA, s:Git(g:plugs.managed.dir, 'rev-parse', 'HEAD'))
execute 'source' fnameescape(snapshot)
call assert_equal($VIM9_PLUG_TEST_SECOND_SHA, s:Git(g:plugs.managed.dir, 'rev-parse', 'HEAD'))

let stale = plugin_home .. '/obsolete clone'
call mkdir(stale, 'p')
PlugClean!
call assert_true(isdirectory(g:plugs.managed.dir))
call assert_false(isdirectory(stale))
call assert_match('Removed 1 directories', join(getline(1, '$'), "\n"))

call assert_equal(1, plug#begin())
execute 'Plug' string($VIM9_PLUG_TEST_LOCAL) .. ", {'as': 'eager'}"
call assert_equal(0, plug#end())
call assert_equal(['eager'], g:plugs_order)

call writefile(g:observed, $VIM9_PLUG_TEST_OUTPUT)
if !empty(v:errors)
  for message in v:errors
    echomsg message
  endfor
  cquit 1
endif
qa!
