" Refactoring plugin for vim plugins
" Language:     vimscript
" Maintainer:   Marco Herrn <marco@mherrn.de>
" Last Changed: 10. November 2019
" URL:          http://github.com/hupfdule/refactorvim/
" License:      MIT

let s:save_cpo = &cpo
set cpo&vim

setlocal iskeyword+=#

if !exists('*s:completeMoveCommand')
  function! s:completeMoveCommand(ArgLead, CmdLine, CursorPos) abort
    let l:split_cmd_line = split(a:CmdLine, '\s\+')
    if len(l:split_cmd_line) ==# 1
      " first parameter must be an autoload function name
      return join(Verdin#refactoring#get_autoload_functions(), "\n")
    elseif len(l:split_cmd_line) ==# 2
      " second parameter must be an autoload namespace
      return join(Verdin#refactoring#get_autoload_namespaces(), "\n")
    else
      " We don't know what to do
      return ""
    endif
  endfunction
endif

if !exists('*s:completeRenameCommand')
  function! s:completeRenameCommand(ArgLead, CmdLine, CursorPos) abort
    let l:split_cmd_line = split(a:CmdLine, '\s\+')
    if len(l:split_cmd_line) ==# 1
      " first parameter must be an autoload function name
      return join(Verdin#refactoring#get_autoload_functions(), "\n")
    elseif len(l:split_cmd_line) ==# 2
      " second parameter must be an autoload function name, but we can only
      " suggest the namespace
      return join(Verdin#refactoring#get_autoload_namespaces(), "#\n")
    else
      " We don't know what to do
      return ""
    endif
  endfunction
endif

" FIXME: These two could be combined into one
" Param 1 _must_ be a function name with namespace
" Param 2 may be:
"   - a function name with namespace
"     This is move and rename at once (change namespace and function name)
"   - a namespace without function name
"     This will only move the function and leave the function name intact.
"     FIXME: Can we handle a missing # at the end of the namespace? Which
"            means: Can we differentiate such a namespace from a full
"            function name?
"            Should we require parentheses on function names?
"   - a function name without namespace
"     This just renames the function name in the same namespace (without
"     moving)
command -buffer -nargs=+ -complete=custom,s:completeMoveCommand RefactorvimMoveFunction :call Verdin#refactoring#move_function(<f-args>)
command -buffer -nargs=+ -complete=custom,s:completeRenameCommand RefactorvimRenameFunction :call Verdin#refactoring#rename_function(<f-args>)

cnoremap <Plug>(RefactorvimCurrentAutoloadFunction)   <c-r>=Verdin#refactoring#get_current_autoload_function()<cr>
cmap <C-R><C-N> <Plug>(RefactorvimCurrentAutoloadFunction)

let &cpo = s:save_cpo

