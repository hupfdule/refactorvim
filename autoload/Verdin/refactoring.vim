" Pattern for a function name with namespace, e.g. "Verdin#refactoring#move_function"
let s:pattern_function_with_namespace = '\v\C^([A-Za-z_]+#)+[A-Za-z_]+$'
" Pattern for a function name without namespace, e.g. "move_function"
let s:pattern_function_name = '\v\C^[A-Za-z_]+$'
" Pattern for a line with a function signature. The functions name will be
" in the first submatch.
let s:pattern_function_signature_line = '\C^\s*function!\?\s\+\(\w\+\%(#\w\+\)\+\)\s*('



""
" Search for definitions of autoload functions.
"
" @returns a list with the names of all autoload functions
function! Verdin#refactoring#get_autoload_functions() abort
  execute ':lcd ' . s:find_root_directory()

  let l:function_pattern = s:pattern_function_signature_line
  execute ':silent vimgrep /\C' . l:function_pattern . '/j **/*'

  " FIXME: Save current buffer here and restore it afterwards?
  "        If cwindow is automatically called, we would land in it otherwise.
  " FIXME: Store the content of the current quickfix list and restore it
  " afterwards?
  let l:resultlist = []
  for e in getqflist()
    let l:function_name = matchlist(e.text, l:function_pattern)[1]
    let l:resultlist = add(l:resultlist, l:function_name)
  endfor

  " Reset the quickfix list to the previous one
  " FIXME: Doesn't work if there is no previous one
  "silent colder

  lcd -
  return l:resultlist
endfunction



""
" Search for existing namespaces of autoload functions.
"
" @returns a list with the names of all existing namespaces of functions
function! Verdin#refactoring#get_autoload_namespaces() abort
  execute ':lcd ' . s:find_root_directory()

  let l:autoload_dir = 'autoload'
  let l:autoload_files = globpath(l:autoload_dir, '**/*.vim', 0, 1)

  let l:resultlist = []

  for e in l:autoload_files
    let l:trimmed = matchstr(e, 'autoload\/\zs.*\ze\.vim$')
    let l:namespace = substitute(l:trimmed, '/', '#', 'g')
    let l:resultlist = add(l:resultlist, l:namespace)
  endfor

  lcd -
  return l:resultlist
endfunction


""
" Get the name of the autoload function the cursor is currently in.
"
" If the cursor is inside a comment directly before an autoload function
" (without any empty lines between the comment block and the function
" signature) the cursor is considered being inside that function.
"
" @returns the name of the current autoload function or an empty string if
"          the cursor is outside of an autoload function.
function! Verdin#refactoring#get_current_autoload_function() abort
  " Locate function signature
  let l:prev_function_signature_line = search(s:pattern_function_signature_line, 'Wbcn')
  " TODO: This breaks on functions containing an inner function. Need to count
  " function/endfunction keywords.
  let l:prev_endfunction_line = search('\C^\s*endfunction', 'Wbn', l:prev_function_signature_line)

  if l:prev_function_signature_line !=# 0 && l:prev_endfunction_line < l:prev_function_signature_line
    let l:prev_function_signature = getline(l:prev_function_signature_line)
    return matchlist(l:prev_function_signature, s:pattern_function_signature_line)[1]
  else
    " if we are outside of a function we can check whether we are in the
    " functions leading comment
    if getline('.') =~# '\C^\s*"'
      let l:next_non_comment_line = search('\C^\(\s*"\)\@!', 'Wn')
      let l:next_function_signature = getline(l:next_non_comment_line)
      let l:match_fn_signature = matchlist(l:next_function_signature, s:pattern_function_signature_line)
      if !empty(l:match_fn_signature)
        return l:match_fn_signature[1]
      endif
    endif
  endif

  return ""
endfunction

""
" Move an autoload function to a different namespace (and therefore a
" different file).
"
" This moves the function to file corresponding to the given namespace and
" changes its name accordingly.
" Additionally it replaces the references to that function in all .vim
" files of the same plugin.
"
" All comment lines directly above the moved function (whithout whitespace
" between the last comment line and the function signature) will be moved
" together with it.
"
" After refactoring the cursor will be placed on the function signature of
" the moved function on its new location.
"
" @parameter {function_name} The function to move.
"                            Must include the namespace. For example this
"                            function would be specified as
"                            "Verdin#refactoring#move_function"
"                            If an empty string the vimscript function the cursor
"                            is currently in will be used
" @parameter {target_namespace} The namespace to move the function to.
"                               This defines the file the function will be
"                               moved to. For example this function has the
"                               namespace "Verdin#refactoring" and
"                               therefore resides in the file
"                               "autoload/Verdin/refactoring.vim".
function! Verdin#refactoring#move_function(function_name, target_namespace) abort
  " FIXME: This function is a bit long. Split it into subfunctions?

  " FIXME: Avoid duplicating a function name!
  "        Check the the target doesn't exist yet.

  " Prepare variables for the files to modify
  let l:root_dir = s:find_root_directory()
  let l:fn = s:split_function_name(a:function_name)
  let l:orig_autoload_file = l:root_dir . '/' . 'autoload/' . substitute(l:fn['namespace'], '#', '/', 'g') . '.vim'
  let l:new_autoload_file = l:root_dir . '/' . 'autoload/' . substitute(a:target_namespace, '#', '/', 'g') . '.vim'

  " Open buffer for the original file
  execute ":badd" . l:orig_autoload_file
  let l:bufnr_orig_file = bufnr(l:orig_autoload_file)
  execute l:bufnr_orig_file . "buffer"

  " Locate function signature
  let l:function_signature_line = search('\C^\s*function!\?\s\+' . a:function_name . '\s*(', 'wc')
  let l:first_comment_line = search('\C^\(\s*"\)\@!', 'Wbn') + 1
  " TODO: This breaks functions containing an inner function. Need to count
  " function/endfunction keywords.
  let l:endfunction_line = search('\C^\s*endfunction', 'Wn')

  " Save registers and settings
  let l:orig_reg_a = @a
  let l:orig_hidden = &hidden
  set hidden

  " Delete the lines to move into register "a"
  call cursor(l:first_comment_line, 0)
  normal! V
  call cursor(l:endfunction_line, 0)
  normal! $
  normal! "ad

  " Delete the next empty lines
  let l:cur_line = line('.')
  let l:next_non_empty_line = nextnonblank(l:cur_line)
  if l:next_non_empty_line !=# 0
    execute 'normal! ' . (l:next_non_empty_line - l:cur_line) . '"_dd'
  endif

  " Create target dir, if necessary
  call mkdir(fnamemodify(l:new_autoload_file, ":h"), 'p')
  " Open buffer for the target file
  execute ":badd" . l:new_autoload_file
  let l:bufnr_new_file = bufnr(l:new_autoload_file)
  execute l:bufnr_new_file . "buffer"
  execute "normal! G\"apO\<c-u>"
  normal! zt

  " Build the new function name from the existing namespace and target name
  let l:new_function_name = a:target_namespace . "#" . l:fn['function']

  " Rename the function in all .vim files
  call s:rename_function(a:function_name, l:new_function_name)

  " restore registers and settings
  let @a = l:orig_reg_a
  let &hidden = l:orig_hidden
endfunction


""
" Rename an autoload function inside the same namespace.
"
" This renames the functions name, leaving its namespace intact.
" Additionally it replaces the references to that function in all .vim
" files of the same plugin.
"
" @parameter {function_name} The function to rename.
"                            Must include the namespace. For example this
"                            function would be specified as
"                            "Verdin#refactoring#move_function"
"                            If an empty string the vimscript function the cursor
"                            is currently in will be used
" @parameter {target_name} The new name of the function _without_ the
"                          namespace. For example to rename this function
"                          from "Verdin#refactoring#rename_function" to
"                          "Verdin#refactoring#frobnitz" this parameter
"                          would be specified as "frobnitz".
function! Verdin#refactoring#rename_function(function_name, target_name) abort
  " validate arguments
  if a:function_name !~# s:pattern_function_with_namespace
    echohl ErrorMsg | echo 'Invalid function name: ' . a:function_name | echohl None
    return
  endif

  if a:target_name !~# s:pattern_function_name
    echohl ErrorMsg | echo 'Invalid target name: ' . a:target_name | echohl None
    return
  endif

  " FIXME: Avoid duplicating a function name!
  "        Check the the target doesn't exist yet.


  " Split the full function name into namespace and actual function name
  let l:fn = s:split_function_name(a:function_name)

  " Build the new function name from the existing namespace and target name
  let l:new_function_name = l:fn['namespace'] . "#" . a:target_name

  " Rename the function in all .vim files
  let l:orig_hidden = &hidden
  set hidden
  call s:rename_function(a:function_name, l:new_function_name)
  let &hidden = l:orig_hidden
endfunction


""
" Rename an autoload function.
"
" This replaces the name in the function signature as well as the
" references to that function in all .vim files of the same plugin.
"
" @parameter {old_function_name} The function to rename.
"                                Must include the namespace. For example this
"                                function would be specified as
"                                "Verdin#refactoring#move_function"
" @parameter {new_function_name} The new name of the function.
"                                Must include the namespace.
function! s:rename_function(old_function_name, new_function_name) abort
  if trim(a:old_function_name) ==# "" || trim(a:new_function_name) ==# ""
    throw 'Old and new function name may not be empty'
  endif

  execute ':lcd ' . s:find_root_directory()
  pwd
  execute ':silent noautocmd vimgrep /' . a:old_function_name . '/ **/* .'
  execute ':silent cfdo %s/' . a:old_function_name . '/' . a:new_function_name . '/ge'
  wall
  lcd -
endfunction


""
" Splits a function name with namespace into its namespace and actual
" function name.
"
" For example the function name "Verdin#refactoring#rename_function" will
" be splitted into "Verdin#refactoring" and "rename_function".
"
" This function does not check whether the given function_name is a valid
" function name.
"
" @parameter {function_name} The function name to split
" @returns a map with the keys
"          "namespace" containing the namespace
"          "function"  containing the function name
function! s:split_function_name(function_name) abort
  let l:split = split(a:function_name, '#')
  let l:result = {}
  let l:result['namespace'] = join(l:split[:-2], "#")
  let l:result['function'] = join(l:split[-1:])
  return l:result
endfunction


""
" Searches for the root directory of the project of the current file.
"
" This will only work for projects with an "autoload" directory (which is
" necessary for these refactoring functions anyway).
"
" @returns the directory containing an autoload subdirectory or the
"          directory of the current file if no autoload directory could be
"          found.
function! s:find_root_directory() abort
  let l:orig_path = &path
  let l:autoload = finddir("autoload", ";")
  let l:root = substitute(l:autoload, '\C\(.*\)/\?autoload$', '\1', "")
  let &path = l:orig_path

  if l:root ==# ""
    return "."
  else
    return l:root
  endif
endfunction
