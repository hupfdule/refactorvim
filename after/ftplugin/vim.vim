" Refactoring plugin for vim plugins
" Language:     vimscript
" Maintainer:   Marco Herrn <marco@mherrn.de>
" Last Changed: 21. August 2021
" URL:          http://github.com/hupfdule/refactorvim/
" License:      MIT

let s:save_cpo = &cpo
set cpo&vim

setlocal iskeyword+=#  " to support namespaces of autoload functions
setlocal iskeyword+=:  " to support functions and variables with namespace

if !exists('*s:completeRenameCommand')
  function! s:completeRenameCommand(ArgLead, CmdLine, CursorPos) abort
    return
      \ join(refactorvim#renaming#get_autoload_namespaces(), "#\n")
      \ . "#\n" .
      \ join(refactorvim#renaming#get_autoload_functions(), "\n")
  endfunction
endif

" Rename autoload function
command! -buffer -nargs=+ -complete=custom,s:completeRenameCommand RefactorvimRename :call refactorvim#renaming#rename(<f-args>)

" Insert current autoload function
cnoremap <Plug>(RefactorvimCurrentAutoloadFunction)   <c-r>=refactorvim#renaming#get_current_autoload_function()<cr>
cmap <C-R><C-N> <Plug>(RefactorvimCurrentAutoloadFunction)

" Toggle Visibility
command! -buffer RefactorvimToggleVisibility :call refactorvim#renaming#toggle_visibility(expand('<cword>'))
nnoremap <buffer> <silent> <Plug>(RefactorvimToggleVisibility) :RefactorvimToggleVisibility<cr>
nmap <leader>v <Plug>(RefactorvimToggleVisibility)

" Go to Definition
nnoremap <buffer> <silent> <Plug>(RefactorvimGotoDefinition) :call refactorvim#motions#goto_definition()<cr>
nmap gd <Plug>(RefactorvimGotoDefinition)

let &cpo = s:save_cpo
