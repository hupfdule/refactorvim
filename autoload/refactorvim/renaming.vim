" Pattern for a function name with namespace, e.g. "refactorvim#renaming#move_function"
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
function! refactorvim#renaming#get_autoload_functions() abort
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
    let l:resultlist = add(l:resultlist, l:function_name . '()')
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
function! refactorvim#renaming#get_autoload_namespaces() abort
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
function! refactorvim#renaming#get_current_autoload_function() abort
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
" Rename an autoload function or a whole autoload namespace.
"
" If a namespace is modified, the function(s) will be moved to the file
" corresponding to that namespace.
"
" Additionally it replaces the references to the function(s) in all .vim
" files of the same plugin.
"
" @parameter {source} The function or namespace to rename.
"                     A function name /must/ include the namespace.
"                     For example this function would be specified
"                     as "refactorvim#renaming#move_function()".
"                     To rename the whole namespace it must be
"                     specified as "refactorvim#renaming#".
"                     In both cases the trailing "()" and "#" are
"                     optional. If they are missing this function
"                     will try to guess whether it specifies a
"                     function or a namespace.
" @parameter {target} The target name.
"                     If the {source} is a namespace this must also be
"                     a namespace. If the {source} is a function this may
"                     either be a namespace, a function with namespace or a
"                     function name without namespace.
"                     For example to rename this function
"                     from "refactorvim#renaming#rename_function()" to
"                     "refactorvim#renaming#frobnitz()" this parameter
"                     could be specified as "frobnitz()" or
"                     "refactorvim#renaming#frobnitz()".
"                     To rename it to "foo#bar#frobnitz()" this parameter
"                     could be specified as "foo#bar#frobnitz()" or
"                     "foo#bar".
function! refactorvim#renaming#rename(source, target) abort
  " TODO: Validate parameters? For example don't accept source functions without
  "       namespace

  " Expand source and target
  try
    let l:source = s:expand_name(a:source)
  catch /^R001/
    echohl ErrorMsg | echo 'Source name "' . a:source . '" is ambiguous. Please specify "()" or "#" suffix.' | echohl None
    return
  endtry
  try
    let l:target = s:expand_name(a:target)
  catch /^R001/
    echohl ErrorMsg | echo 'Target name "' . a:target . '" is ambiguous. Please specify "()" or "#" suffix.' | echohl None
    return
  endtry

  " Modify and backup 'hidden' settings
  let l:orig_hidden = &hidden
  set hidden

  try
    if l:source =~# '()$'
      " source is a function
      let l:old_function_name = l:source " FIXME: Call expand on it and check if function
      let l:old_function = s:split_function_name(l:old_function_name)
      " If target is only a function name without namespace, prepend the namespace from the source
      if l:target =~# '()$' && l:target !~# '#'
        let l:target = l:old_function['namespace'] . '#' . l:target
      endif
      let l:new_function_name = l:target " dito, also change namespace if necessary
      let l:new_function = s:split_function_name(l:new_function_name)

      if l:old_function['namespace'] !=# l:new_function['namespace']
        " If the namespace changed, move the function to the new namespace
        call s:move_function(l:old_function_name, l:new_function_name)
      else
        " Otherwise rename the function in place
        call s:rename_function(l:old_function_name, l:new_function_name)
      endif
    elseif l:source =~# '#$'
      " source is a namespace
      " TODO: target may not be a function
      call s:rename_namespace(l:source, l:target)
    endif
  finally
    " restore 'hidden' setting
    let &hidden = l:orig_hidden
  endtry
endfunction


""
" Expand a given function or namespace to its full form including a suffix.
"
" If the suffix is already given, this just returns the given argument.
"
" If the given argument exists as a function the "()" is appended.
" If the given argument exists as a .vim file the "#" is appended.
"
" In all other cases an R001 exception is thrown.
"
" @param {name} the name to expand
" @returns the expanded name
" @throws R001 if the type of the argument cannot be clearly identified
function! s:expand_name(name) abort
  if a:name =~# '()$' || a:name =~# '#$'
    " if the name includes the specific suffix, nothing needs to be expanded
    return a:name
  endif

  " Try to find a function with that name
  let l:root_dir = s:find_root_directory()
  let l:fn = s:split_function_name(a:name)
  let l:autoload_file = l:root_dir . '/' . 'autoload/' . substitute(l:fn['namespace'], '#', '/', 'g') . '.vim'

  " Open buffer for the expected file
  execute ":badd" . l:autoload_file
  let l:bufnr_orig_file = bufnr(l:autoload_file)
  execute l:bufnr_orig_file . "buffer"

  " Locate function signature
  let l:function_signature_line = search('\C^\s*function!\?\s\+' . a:name . '\s*(', 'wc')
  if l:function_signature_line > 0
    " if such a method exists, this is a method
    return a:name . '()'
  endif

  " Try to find a namespace with that name
  let l:autoload_file = l:root_dir . '/' . 'autoload/' . substitute(l:fn['namespace'], '#', '/', 'g') . '/' . l:fn['function'] . '.vim'
  if filereadable(l:autoload_file)
    " if such a file exists, this is a namespace
    return a:name . '#'
  endif

  " Otherwise we are not sure and have to break here
  throw "R001: Ambiguous name"
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
"                                "refactorvim#renaming#move_function"
" @parameter {new_function_name} The new name of the function.
"                                Must include the namespace.
function! s:rename_function(old_function_name, new_function_name) abort
  if trim(a:old_function_name) ==# "" || trim(a:new_function_name) ==# ""
    throw 'Old and new function name may not be empty'
  endif

  execute ':lcd ' . s:find_root_directory()
  pwd
  execute ':silent noautocmd vimgrep /' substitute(a:old_function_name, '()$', '', '') . '/ **/* .'
  execute ':silent cfdo %s/' . substitute(a:old_function_name, '()$', '\\(\\s*(\\)', '') . '/' . substitute(a:new_function_name, '()$', '\\1', '') . '/ge'
  wall
  lcd -
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
"                            "refactorvim#renaming#move_function"
"                            If an empty string the vimscript function the cursor
"                            is currently in will be used
" @parameter {new_function_name} The new function name including namespace.
"                                The namespace defines the file the
"                                function will be moved to. For example
"                                this function has the namespace
"                                "refactorvim#renaming" and therefore resides
"                                in the file
"                                "autoload/refactorvim/renaming.vim".
function! s:move_function(function_name, new_function_name) abort
  " FIXME: Get as parameter a buffer and the lines?
  " FIXME: Avoid duplicating a function name!
  "        Check the the target doesn't exist yet.

  " Prepare variables for the files to modify
  let l:root_dir = s:find_root_directory()
  let l:fn_old = s:split_function_name(a:function_name)
  let l:fn_new = s:split_function_name(a:new_function_name)
  let l:orig_autoload_file = l:root_dir . '/' . 'autoload/' . substitute(l:fn_old['namespace'], '#', '/', 'g') . '.vim'
  let l:new_autoload_file = l:root_dir . '/' . 'autoload/' . substitute(l:fn_new['namespace'], '#', '/', 'g') . '.vim'

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
  update

  " Create target dir, if necessary
  call mkdir(fnamemodify(l:new_autoload_file, ":h"), 'p')
  " Open buffer for the target file
  execute ":badd" . l:new_autoload_file
  let l:bufnr_new_file = bufnr(l:new_autoload_file)
  execute l:bufnr_new_file . "buffer"
  " FIXME: if this is a new file it should start in the first line
  execute "normal! G\"apO\<c-u>"
  update
  normal! zt

  " Rename the function in all .vim files
  call s:rename_function(a:function_name, a:new_function_name)

  " restore registers and settings
  let @a = l:orig_reg_a
endfunction


""
" Renames an autoload namespace.
"
" The renaming is done by renaming the corresponding files and directories.
"
" @parameter {old_namespace}
" @parameter {new_namespace}
function! s:rename_namespace(old_namespace, new_namespace) abort
   " Find the common root directory
   let l:rootdir = s:find_root_directory() . "/autoload"
   let l:old_ns = s:split_function_name(a:old_namespace)
   let l:new_ns = s:split_function_name(a:new_namespace)
   let l:common_root = simplify(fnamemodify(l:rootdir, ':p'))
   let l:old_parts = add(split(l:old_ns['namespace'], '#'), l:old_ns['function'])
   let l:new_parts = add(split(l:new_ns['namespace'], '#'), l:new_ns['function'])
   let l:old_fully_remains = v:true " specifies that the new namespace is only an extension of the old one
   for i in range(0, len(l:old_parts) - 1)
     if len(l:new_parts) > i && l:old_parts[i] ==# l:new_parts[i]
       let l:common_root .= '/' . l:old_parts[i]
     else
       let l:old_parts = l:old_parts[i:]
       let l:new_parts = l:new_parts[i:]
       let l:old_fully_remains = v:false
       break
     endif
   endfor

   if l:old_fully_remains
     if len(l:new_parts) >=# len(l:old_parts)
       let l:new_parts = l:new_parts[len(l:old_parts):]
     endif
     let l:old_parts = []
   endif

   if len(l:old_parts) ==# 0
     let l:needs_rename = l:common_root
     let l:source_path = l:common_root
   else
     let l:needs_rename = simplify(l:common_root . '/' . l:old_parts[0])
     let l:source_path = simplify(l:common_root . '/' . join(l:old_parts, '/'))
   endif

   " Create necessary target directories
   let l:target_path = l:common_root .  '/' . join(l:new_parts, '/')
   let l:target_parent = fnamemodify(l:target_path, ':h')
   call mkdir(l:target_parent, 'p')

   " Move files in open buffers
   for bufinfo in getbufinfo()
     echom l:needs_rename
     if bufinfo['name'] =~# '\C^' . l:needs_rename
       let l:new_file_name = substitute(bufinfo['name'], join(l:old_parts, '/'), join(l:new_parts, '/'), "")
       echom "[Refactorvim] Renaming buffer " . bufinfo['bufnr'] . " from " . bufinfo['name'] . " to " . l:new_file_name
       execute bufinfo['bufnr'] . "buffer"
       execute "keepalt saveas " . l:new_file_name
       execute "bwipeout " . bufinfo['name']
     endif
   endfor

   " Move remaining files in filesystem

   " FIXME: Check all variants of existing files/dirs
   "        In that case, don't rename, but append

   " Move {namespace} directory
   if isdirectory(l:source_path)
     echom "[Refactorvim] Renaming " . l:source_path . " to " . l:target_path
     call rename(l:source_path, l:target_path)
   endif

   " Move {namespace}.vim file
   if filereadable(l:source_path . '.vim')
     echom "[Refactorvim] Renaming " . l:source_path . ".vim to " . l:target_path . ".vim"
     call rename(l:source_path . '.vim', l:target_path . '.vim')
   endif

   " update all buffers again
   bufdo :e!

   " Now search and replace namespace
   " We can abuse the s:rename_function for that purpose
   call s:rename_function(a:old_namespace, a:new_namespace)
endfunction


""
" Splits a function name with namespace into its namespace and actual
" function name.
"
" For example the function name "refactorvim#renaming#rename_function" will
" be splitted into "refactorvim#renaming" and "rename_function".
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
