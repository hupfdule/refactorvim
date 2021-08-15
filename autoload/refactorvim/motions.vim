" Matches a function name (in a function call).
let s:pattern_functionname = '\C\w\+\%(#\w\+\)\+\ze\s*('

" Pattern for a line with a function signature. The functions name will be
" in the first submatch.
" FIXME: This is a copy of the same regex in renaming.vim. Reuse these patterns?
let s:pattern_function_signature_line         = '\C^\s*function!\?\s\+\(\w\+\%(#\w\+\)\+\)\s*('
let s:pattern_function_signature_line_start   = '\C^\s*function!\?\s\+\zs'
let s:pattern_function_signature_line_end     = '\ze\s*('

" Pattern for a line with a variable declaration. The variables name will
" be in the first submatch.
" Attention! This regex relies on the 'iskeyword' setting of refactorvim and
" there will likely not work outside of refactorvim.
let s:pattern_variable_declaration_line       = '\C\v^\s*let\s+(\k+)\s*\='
let s:pattern_variable_declaration_line_start = '\C\v^\s*let\s+\zs'
let s:pattern_variable_declaration_line_end   = '\ze\s*\='



" FIXME: Autoload functions and variables /may/ be preceded by g:

""
" Jump to definition of the current "<cword>".
"
" This supports function defintions and variable declarations.
function! refactorvim#motions#goto_definition() abort
  let l:cword = expand('<cword>')
  let l:cword_type = s:get_cword_type()
  if l:cword_type ==# 'function'
    call s:goto_function_definition(l:cword)
  else
    call s:goto_variable_declaration(l:cword)
  endif
endfunction


""
" Jump to the definition of {function_name}.
"
" @param {function_name} the function name to search for
function! s:goto_function_definition(function_name) abort
  if a:function_name[0:1] ==# 's:'
    " Remember the current position in the jump list, then jump
    normal! m'
    call s:search_function(a:function_name)
  elseif stridx(a:function_name, '#') isnot -1
    let l:split_function_name = split(a:function_name, '#')
    let l:bare_function_name  = l:split_function_name[-1]
    let l:script_name = l:split_function_name[-2] . '.vim'
    let l:root_dir = s:find_root_directory()
    if l:root_dir is 0
      echohl WarningMsg | echom a:function_name . ' is an autoload function, but no autoload dir was found.' | echohl Normal
      return
    endif
    let l:autoload_file_path = l:root_dir . '/autoload/'
    for l:autoload_dir in l:split_function_name[0:-3]
      let l:autoload_file_path .= l:autoload_dir . '/'
    endfor

    " Remember the current position in the jump list, then jump
    normal! m'
    execute 'edit ' . l:autoload_file_path . l:script_name
    call s:search_function(a:function_name)
  endif
endfunction


""
" Jump to the declaration of {variable_name}.
"
" This supports script-local variables (starting with "s:"), local
" variables (starting with "l:" or without any prefix), function arguments
" (starting with "a:") and autoload variables.
"
" All of the above are searched in the current buffer instead of autoload
" variables. autoload variables are searched in the script file matching the
" autoload prefix of {variable_name}.
"
" @param {variable_name} the variable name to search for
function! s:goto_variable_declaration(variable_name) abort
  if a:variable_name[0:1] ==# 's:'
    " Search script-local variable from the start of the current file
    " Remember the current position in the jump list, then jump
    normal! m'
    call s:search_variable_declaration(a:variable_name)
  elseif stridx(a:variable_name, '#') isnot -1
    " Search autoload variables from the start of its autoload file
    let l:split_variable_name = split(a:variable_name, '#')
    let l:bare_variable_name  = l:split_variable_name[-1]
    let l:script_name = l:split_variable_name[-2] . '.vim'
    let l:root_dir = s:find_root_directory()
    if l:root_dir is 0
      echohl WarningMsg | echom a:variable_name . ' is an autoload variable, but no autoload dir was found.' | echohl Normal
      return
    endif
    let l:autoload_file_path = l:root_dir . '/autoload/'
    for l:autoload_dir in l:split_variable_name[0:-3]
      let l:autoload_file_path .= l:autoload_dir . '/'
    endfor

    " Remember the current position in the jump list, then jump
    normal! m'
    execute 'edit ' . l:autoload_file_path . l:script_name
    call s:search_variable_declaration(a:variable_name)
  elseif a:variable_name[0:1] ==# 'a:'
    " function arguments are always declared in the signature of the current function
    normal! m'
    let l:matching_line = search(s:pattern_function_signature_line, 'bW')
    if l:matching_line isnot 0
      call cursor(line('.'), 0)
      let l:found_variable = search(a:variable_name[2:], '', line('.'))
      if l:found_variable is 0
        " If the variable name is not contained in the argument list, just
        " jump to the first argument
        normal! f(l
      endif
    endif
  elseif a:variable_name[0:1] ==# 'l:' || a:variable_name[1] !=# ':'
    " Search script-local variables from the start of the current(?) function
    normal! m'
    let l:function_end = search('\C^\s*endfunction', 'Wn')
    if l:function_end isnot 0
      let l:function_start = search(s:pattern_function_signature_line, 'bW')
      if l:function_start isnot 0
        let l:unprefixed_variable_name = a:variable_name[0:1] ==# 'l:' ? a:variable_name[2:] : a:variable_name
        let l:found_variable= search('\C^\s*let\s*\zs\(\%(l:\)\?' . l:unprefixed_variable_name . '\)\ze\s*=' , 'W', l:function_end)
        if l:found_variable is 0
          " If we did not find a variable declaration, jump back
          normal! m'
        endif
      else
        " Jump back if we could not find the function start
        normal! <c-o>
      endif
    endif
  else
    " In all other cases there multiple possibilities. Therefore the
    " quickfix list or location list should be used.
    " TODO: Search for all occurences. If there is more than one, use the
    " quickfix/location list. If it is only one, jump there directly.
  endif
endfunction


""
" Search in the current buffer for a function definition.
"
" The cursor is moved to the match.
"
" @returns the line number of the next found match or 0 if there was no
" match.
function! s:search_function(function_name) abort
  return search(s:pattern_function_signature_line_start . a:function_name . s:pattern_function_signature_line_end, 'w')
endfunction


""
" Search in the current buffer for a variable declaration.
"
" A variable declaration is identified by starting with "let " and making an
" assignment via "=" to {variable_name}.
"
" The cursor is moved to the match.
"
" @returns the line number of the next found match or 0 if there was no
" match.
function! s:search_variable_declaration(variable_name) abort
  " Fixme. This is too inflexible. We must be to search from different
  " positions (and in different directions?)
  return search(s:pattern_variable_declaration_line_start . a:variable_name . s:pattern_variable_declaration_line_end, 'w')
endfunction


""
" Searches for the root directory of the project of the current file.
"
" This will only work for projects with an "autoload" directory (which is
" necessary for these refactoring functions anyway).
"
" @returns the directory containing an autoload subdirectory or 0
"          if no autoload directory could be found.
function! s:find_root_directory() abort
  let l:orig_path = &path
  let l:orig_cwd  = getcwd()
  " move to directory of current file for searching
  execute 'lcd ' . expand('%:p:h')
  let l:autoload = finddir("autoload", ";")
  let l:root = substitute(l:autoload, '\C\(.*\)/\?autoload$', '\1', "")
  let &path = l:orig_path
  execute 'lcd ' . l:orig_cwd

  if l:root ==# ""
    return 0
  else
    return l:root
  endif
endfunction


""
" Get the type of the current <cword>.
"
" This may be either a "function" or a "variable".
"
" @returns - 'function' if the <cword> is considered a function
"          - 'variable' if the <cword> is considered a variable
"          - 0 in all other cases
function! s:get_cword_type() abort
  let l:orig_pos = getcurpos()
  execute 'normal! w'
  if s:get_char_at_cursor() ==# '('
    let l:type = 'function'
  else
    let l:type = 'variable'
  endif

  call setpos('.', l:orig_pos)
  return l:type
endfunction


""
" Get the character at the current cursor position.
"
" @returns the character at the current cursor position or an empty string
"          if ther is no character at the current cursor position
function! s:get_char_at_cursor() abort
  return matchstr(getline('.'), '\%' . col('.') . 'c.')
endfunction
