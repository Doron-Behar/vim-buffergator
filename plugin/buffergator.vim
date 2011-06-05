""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""
""  Buffergator
""
""  Vim document buffer navigation utility
""
""  Copyright 2011 Jeet Sukumaran.
""
""  This program is free software; you can redistribute it and/or modify
""  it under the terms of the GNU General Public License as published by
""  the Free Software Foundation; either version 3 of the License, or
""  (at your option) any later version.
""
""  This program is distributed in the hope that it will be useful,
""  but WITHOUT ANY WARRANTY; without even the implied warranty of
""  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
""  GNU General Public License <http://www.gnu.org/licenses/>
""  for more details.
""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""""

" Reload and Compatibility Guard {{{1
" ============================================================================
" Reload protection.
if (exists('g:did_buffergator') && g:did_buffergator) || &cp || version < 700
    finish
endif

"" DISABLED TO ALLOW RELOAD FOR DEBUGGING
"let g:did_buffergator = 1

" avoid line continuation issues (see ':help user_41.txt')
let s:save_cpo = &cpo
set cpo&vim
" 1}}}

" Script Data and Variables {{{1
" =============================================================================

" Split Modes {{{2
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
" Split modes are indicated by a single letter. Upper-case letters indicate
" that the SCREEN (i.e., the entire application "window" from the operating
" system's perspective) should be split, while lower-case letters indicate
" that the VIEWPORT (i.e., the "window" in Vim's terminology, referring to the
" various subpanels or splits within Vim) should be split.
" Split policy indicators and their corresponding modes are:
"   ``/`d`/`D'  : use default splitting mode
"   `n`/`N`     : NO split, use existing window.
"   `L`         : split SCREEN vertically, with new split on the left
"   `l`         : split VIEWPORT vertically, with new split on the left
"   `R`         : split SCREEN vertically, with new split on the right
"   `r`         : split VIEWPORT vertically, with new split on the right
"   `T`         : split SCREEN horizontally, with new split on the top
"   `t`         : split VIEWPORT horizontally, with new split on the top
"   `B`         : split SCREEN horizontally, with new split on the bottom
"   `b`         : split VIEWPORT horizontally, with new split on the bottom
let s:buffergator_viewport_split_modes = {
            \ "d"   : "sp",
            \ "D"   : "sp",
            \ "N"   : "buffer",
            \ "n"   : "buffer",
            \ "L"   : "topleft vert sbuffer",
            \ "l"   : "leftabove vert sbuffer",
            \ "R"   : "botright vert sbuffer",
            \ "r"   : "rightbelow vert sbuffer",
            \ "T"   : "topleft sbuffer",
            \ "t"   : "leftabove sbuffer",
            \ "B"   : "botright sbuffer",
            \ "b"   : "rightbelow",
            \ }
" 2}}}

" Catalog Sort Regimes {{{2
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
let s:buffergator_catalog_sort_regimes = ['basename', 'filepath', 'bufnum']
let s:buffergator_catalog_sort_regime_desc = {
            \ 'basename' : ["basename", "by basename"],
            \ 'filepath' : ["filepath", "by (full) filepath"],
            \ 'bufnum'  : ["bufnum", "by buffer number"],
            \ }
" 2}}}


" 1}}}

" Utilities {{{1
" ==============================================================================

" Text Formatting {{{2
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~
function! s:_format_align_left(text, width, fill_char)
    let l:fill = repeat(a:fill_char, a:width-len(a:text))
    return a:text . l:fill
endfunction

function! s:_format_align_right(text, width, fill_char)
    let l:fill = repeat(a:fill_char, a:width-len(a:text))
    return l:fill . a:text
endfunction

function! s:_format_time(secs)
    if exists("*strftime")
        return strftime("%Y-%m-%d %H:%M:%S", a:secs)
    else
        return (localtime() - a:secs) . " secs ago"
    endif
endfunction

function! s:_format_escaped_filename(file)
  if exists('*fnameescape')
    return fnameescape(a:file)
  else
    return escape(a:file," \t\n*?[{`$\\%#'\"|!<")
  endif
endfunction

" trunc: -1 = truncate left, 0 = no truncate, +1 = truncate right
function! s:_format_truncated(str, max_len, trunc)
    if len(a:str) > a:max_len
        if a:trunc > 0
            return strpart(a:str, a:max_len - 4) . " ..."
        elseif a:trunc < 0
            return '... ' . strpart(a:str, len(a:str) - a:max_len + 4)
        endif
    else
        return a:str
    endif
endfunction

" Pads/truncates text to fit a given width.
" align: -1/0 = align left, 0 = no align, 1 = align right
" trunc: -1 = truncate left, 0 = no truncate, +1 = truncate right
function! s:_format_filled(str, width, align, trunc)
    let l:prepped = a:str
    if a:trunc != 0
        let l:prepped = s:Format_Truncate(a:str, a:width, a:trunc)
    endif
    if len(l:prepped) < a:width
        if a:align > 0
            let l:prepped = s:_format_align_right(l:prepped, a:width, " ")
        elseif a:align < 0
            let l:prepped = s:_format_align_left(l:prepped, a:width, " ")
        endif
    endif
    return l:prepped
endfunction

" 2}}}

" Messaging {{{2
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

function! s:NewMessenger(name)

    " allocate a new pseudo-object
    let l:messenger = {}
    let l:messenger["name"] = a:name
    if empty(a:name)
        let l:messenger["title"] = "buffergator"
    else
        let l:messenger["title"] = "buffergator (" . l:messenger["name"] . ")"
    endif

    function! l:messenger.format_message(leader, msg) dict
        return self.title . ": " . a:leader.a:msg
    endfunction

    function! l:messenger.format_exception( msg) dict
        return a:msg
    endfunction

    function! l:messenger.send_error(msg) dict
        redraw
        echohl ErrorMsg
        echomsg self.format_message("[ERROR] ", a:msg)
        echohl None
    endfunction

    function! l:messenger.send_warning(msg) dict
        redraw
        echohl WarningMsg
        echomsg self.format_message("[WARNING] ", a:msg)
        echohl None
    endfunction

    function! l:messenger.send_status(msg) dict
        redraw
        echohl None
        echomsg self.format_message("", a:msg)
    endfunction

    function! l:messenger.send_info(msg) dict
        redraw
        echohl None
        echo self.format_message("", a:msg)
    endfunction

    return l:messenger

endfunction
" 2}}}

" Buffer Management {{{2
" ~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

" Returns a list of all existing buffer numbers, excluding unlisted ones
" unless `include_unlisted` is non-empty.
" function! s:_get_bufnums(include_unlisted)
"     let l:bufnum_list = []
"     for l:idx in range(1, bufnr("$"))
"         if bufexists(l:idx) && (empty(a:include_unlisted) || buflisted(l:idx))
"             call add(l:bufnum_list, l:idx)
"         endif
"     endfor
"     return l:bufnum_list
" endfunction

" Returns a list of all existing buffer names, excluding unlisted ones
" unless `include_unlisted` is non-empty.
" function! s:_get_buf_names(include_unlisted, expand_modifiers)
"     let l:buf_name_list = []
"     for l:idx in range(1, bufnr("$"))
"         if bufexists(l:idx) && (empty(!a:include_unlisted) || buflisted(l:idx))
"             call add(l:buf_name_list, expand(bufname(l:idx).a:expand_modifiers))
"         endif
"     endfor
"     return l:buf_name_list
" endfunction

" Searches for all windows that have a window-scoped variable `varname`
" with value that matches the expression `expr`. Returns list of window
" numbers that meet the criterion.
" function! s:_find_windows_with_var(varname, expr)
"     let l:results = []
"     for l:wni in range(1, winnr("$"))
"         let l:wvar = getwinvar(l:wni, "")
"         if empty(a:varname)
"             call add(l:results, l:wni)
"         elseif has_key(l:wvar, a:varname) && l:wvar[a:varname] =~ a:expr
"             call add(l:results, l:wni)
"         endif
"     endfor
"     return l:results
" endfunction

" Searches for all buffers that have a buffer-scoped variable `varname`
" with value that matches the expression `expr`. Returns list of buffer
" numbers that meet the criterion.
function! s:_find_buffers_with_var(varname, expr)
    let l:results = []
    for l:bni in range(1, bufnr("$"))
        if !bufexists(l:bni)
            continue
        endif
        let l:bvar = getbufvar(l:bni, "")
        if empty(a:varname)
            call add(l:results, l:bni)
        elseif has_key(l:bvar, a:varname) && l:bvar[a:varname] =~ a:expr
            call add(l:results, l:bni)
        endif
    endfor
    return l:results
endfunction

" Returns a dictionary with the buffer number as keys (if `key` is empty)
" and the parsed information regarding each buffer as values. If `key` is
" given (e.g. key='bufnum'; key='basename', key='filepath') then that field will
" be used as the dictionary keys instead.
function! s:_get_buffers_info(key)
    if empty(a:key)
        let l:key = "bufnum"
    else
        let l:key = a:key
    endif
    redir => buffers_output
    execute('silent ls')
    redir END
    let l:buffers_info = {}
    let l:buffers_output_rows = split(l:buffers_output, "\n")
    for l:buffers_output_row in l:buffers_output_rows
        let l:parts = matchlist(l:buffers_output_row, '^\s*\(\d\+\)\(.....\) "\(.*\)"\s\+line \d\+$')
        let l:info = {}
        let l:info["bufnum"] = l:parts[1] + 0
        if l:parts[2][0] == "u"
            let l:info["is_unlisted"] = 1
            let l:info["is_listed"] = 0
        else
            let l:info["is_unlisted"] = 0
            let l:info["is_listed"] = 1
        endif
        if l:parts[2][1] == "%"
            let l:info["is_current"] = 1
            let l:info["is_alternate"] = 0
        elseif l:parts[2][1] == "#"
            let l:info["is_current"] = 0
            let l:info["is_alternate"] = 1
        else
            let l:info["is_current"] = 0
            let l:info["is_alternate"] = 0
        endif
        if l:parts[2][2] == "a"
            let l:info["is_active"] = 1
            let l:info["is_loaded"] = 1
            let l:info["is_visible"] = 1
        elseif l:parts[2][2] == "h"
            let l:info["is_active"] = 0
            let l:info["is_loaded"] = 1
            let l:info["is_visible"] = 0
        else
            let l:info["is_active"] = 0
            let l:info["is_loaded"] = 0
            let l:info["is_visible"] = 0
        endif
        if l:parts[2][3] == "-"
            let l:info["is_modifiable"] = 0
            let l:info["is_readonly"] = 0
        elseif l:parts[2][3] == "="
            let l:info["is_modifiable"] = 1
            let l:info["is_readonly"] = 1
        else
            let l:info["is_modifiable"] = 1
            let l:info["is_readonly"] = 0
        endif
        if l:parts[2][4] == "+"
            let l:info["is_modified"] = 1
            let l:info["is_readerror"] = 0
        elseif l:parts[2][4] == "x"
            let l:info["is_modified"] = 0
            let l:info["is_readerror"] = 0
        else
            let l:info["is_modified"] = 0
            let l:info["is_readerror"] = 0
        endif
        let l:info["bufname"] = parts[3]
        let l:info["filepath"] = fnamemodify(l:info["bufname"], ":p")
        let l:info["basename"] = fnamemodify(l:info["bufname"], ":t")
        if !has_key(l:info, l:key)
            throw s:_buffergator_messenger.format_exception("Invalid key requested: '" . l:key . "'")
        endif
        let l:buffers_info[l:info[l:key]] = l:info
    endfor
    return l:buffers_info
endfunction

" Returns split mode to use for a new Buffersaurus viewport. If given an
" argument, this should be a single letter indicating the split policy. If
" no argument is given and `g:buffergator_viewport_split_policy` exists, then it
" will be used. If `g:buffergator_viewport_split_policy` does not exist, then a
" default will be used.
function! s:_get_split_mode(...)
    if a:0 == 0
        if exists("g:buffergator_viewport_split_policy")
            if has_key(s:buffergator_viewport_split_modes, g:buffergator_viewport_split_policy)
                return s:buffergator_viewport_split_modes[g:buffergator_viewport_split_policy]
            else
                call s:_buffergator_messenger.send_error("Unrecognized split mode specified by 'g:buffergator_viewport_split_policy': " . g:buffergator_viewport_split_policy)
            endif
        endif
    else
        let l:policy = a:1
        if has_key(s:buffergator_viewport_split_modes, l:policy[0])
            return s:buffergator_viewport_split_modes[l:policy[0]]
        else
            throw s:_buffergator_messenger.format_exception("Unrecognized split mode: '" . l:policy . "')
        endif
    endif
    return s:buffergator_viewport_split_modes["B"]
endfunction

" Detect filetype. From the 'taglist' plugin.
" Copyright (C) 2002-2007 Yegappan Lakshmanan
function! s:_detect_filetype(fname)
    " Ignore the filetype autocommands
    let old_eventignore = &eventignore
    set eventignore=FileType
    " Save the 'filetype', as this will be changed temporarily
    let old_filetype = &filetype
    " Run the filetypedetect group of autocommands to determine
    " the filetype
    exe 'doautocmd filetypedetect BufRead ' . a:fname
    " Save the detected filetype
    let ftype = &filetype
    " Restore the previous state
    let &filetype = old_filetype
    let &eventignore = old_eventignore
    return ftype
endfunction

" 2}}}

" 1}}}

" CatalogViewer {{{1
" ============================================================================
function! s:NewCatalogViewer()

    " abort if catalog is empty
    " if len(a:catalog.matched_lines) == 0
    "     throw s:_buffergator_messenger.format_exception("CatalogViewer() called on empty catalog")
    " endif

    " initialize
    let l:catalog_viewer = {}

    " Initialize object state.
    let l:catalog_viewer["bufnum"] = -1
    let l:catalog_viewer["bufname"] = "[[buffergator]]"
    let l:catalog_viewer["title"] = "buffergator"
    let l:buffergator_bufs = s:_find_buffers_with_var("is_buffergator_buffer", 1)
    if len(l:buffergator_bufs) > 0
        let l:catalog_viewer["bufnum"] = l:buffergator_bufs[0]
    endif
    let l:catalog_viewer["jump_map"] = {}
    let l:catalog_viewer["split_mode"] = s:_get_split_mode()
    let l:catalog_viewer["buffers_catalog"] = {}
    let l:catalog_viewer["sort_regime"] = "bufnum"
    let l:catalog_viewer["buffer_catalog_display"] = "basename" " basename, relname, fullpath

    " Populates the buffer list
    function! l:catalog_viewer.update_buffers_info() dict
        let self.buffers_catalog = s:_get_buffers_info(self.sort_regime)
    endfunction

    " Opens the buffer for viewing, creating it if needed. If non-empty first
    " argument is given, forces re-rendering of buffer.
    function! l:catalog_viewer.open(...) dict
        " populate data
        call self.update_buffers_info()
        " get buffer number of the catalog view buffer, creating it if neccessary
        if self.bufnum < 0 || !bufexists(self.bufnum)
            " create and render a new buffer
            call self.create_buffer()
        else
            " buffer exists: activate a viewport on it according to the
            " spawning mode, re-rendering the buffer with the catalog if needed
            call self.activate_viewport()
            if (a:0 > 0 && a:1) || b:buffergator_catalog_viewer != self
                call self.render_buffer()
            endif
        endif
    endfunction

    " Creates a new buffer, renders and opens it.
    function! l:catalog_viewer.create_buffer() dict
        " get a new buf reference
        let self.bufnum = bufnr(self.bufname, 1)
        " get a viewport onto it
        call self.activate_viewport()
        " initialize it (includes "claiming" it)
        call self.initialize_buffer()
        " render it
        call self.render_buffer()
    endfunction

    " Opens a viewport on the buffer according, creating it if neccessary
    " according to the spawn mode. Valid buffer number must already have been
    " obtained before this is called.
    function! l:catalog_viewer.activate_viewport() dict
        let l:bfwn = bufwinnr(self.bufnum)
        if l:bfwn == winnr()
            " viewport wth buffer already active and current
            return
        elseif l:bfwn >= 0
            " viewport with buffer exists, but not current
            execute(l:bfwn . " wincmd w")
        else
            " create viewport
            let self.split_mode = s:_get_split_mode()
            execute("silent keepalt keepjumps " . self.split_mode . " " . self.bufnum)
        endif
    endfunction

    " Sets up buffer environment.
    function! l:catalog_viewer.initialize_buffer() dict
        call self.claim_buffer()
        call self.setup_buffer_opts()
        call self.setup_buffer_syntax()
        call self.setup_buffer_commands()
        call self.setup_buffer_keymaps()
        call self.setup_buffer_folding()
        call self.setup_buffer_statusline()
    endfunction

    " 'Claims' a buffer by setting it to point at self.
    function! l:catalog_viewer.claim_buffer() dict
        call setbufvar("%", "is_buffergator_buffer", 1)
        call setbufvar("%", "buffergator_catalog_viewer", self)
        call setbufvar("%", "buffergator_last_render_time", 0)
        call setbufvar("%", "buffergator_cur_line", 0)
    endfunction

    " 'Unclaims' a buffer by stripping all buffergator vars
    function! l:catalog_viewer.unclaim_buffer() dict
        for l:var in ["is_buffergator_buffer",
                    \ "buffergator_catalog_viewer",
                    \ "buffergator_last_render_time",
                    \ "buffergator_cur_line"
                    \ ]
            if exists("b:" . l:var)
                unlet b:{l:var}
            endif
        endfor
    endfunction

    " Sets buffer options.
    function! l:catalog_viewer.setup_buffer_opts() dict
        setlocal buftype=nofile
        setlocal noswapfile
        setlocal nowrap
        set bufhidden=hide
        setlocal nobuflisted
        setlocal nolist
        setlocal noinsertmode
        " setlocal nonumber
        setlocal cursorline
        setlocal nospell
    endfunction

    " Sets buffer syntax.
    function! l:catalog_viewer.setup_buffer_syntax() dict
        " if has("syntax")
        "     syntax clear
        "     if self.catalog.is_show_context()
        "         syn region BuffersaurusSyntaxFileGroup       matchgroup=BuffersaurusSyntaxFileGroupTitle start='^[^ ]'   keepend       end='\(^[^ ]\)\@=' fold
        "         syn region BuffersaurusSyntaxContextedEntry  start='^  \['  end='\(^  \[\|^[^ ]\)\@=' fold containedin=BuffersaurusSyntaxFileGroup
        "         syn region BuffersaurusSyntaxContextedKeyRow start='^  \[\s\{-}.\{-1,}\s\{-}\]' keepend oneline end='$' containedin=BuffersaurusSyntaxContextedEntry
        "         syn region BuffersaurusSyntaxContextLines    start='^  \s*\d\+ :'  oneline end='$' containedin=BuffersaurusSyntaxContextedEntry
        "         syn region BuffersaurusSyntaxMatchedLines    start='^  \s*\d\+ >'  oneline end='$'  containedin=BuffersaurusSyntaxContextedEntry

        "         syn match BuffersaurusSyntaxFileGroupTitle            ':: .\+ :::'                          containedin=BuffersaurusSyntaxFileGroup
        "         syn match BuffersaurusSyntaxKey                       '^  \zs\[\s\{-}.\{-1,}\s\{-}\]\ze'    containedin=BuffersaurusSyntaxcOntextedKeyRow
        "         syn match BuffersaurusSyntaxContextedKeyFilename      '  \zs".\+"\ze, L\d\+-\d\+:'          containedin=BuffersaurusSyntaxContextedKeyRow
        "         syn match BuffersaurusSyntaxContextedKeyLines         ', \zsL\d\+-\d\+\ze:'                 containedin=BuffersaurusSyntaxContextedKeyRow
        "         syn match BuffersaurusSyntaxContextedKeyDesc          ': .*$'                               containedin=BuffersaurusSyntaxContextedKeyRow

        "         syn match BuffersaurusSyntaxContextLineNum            '^  \zs\s*\d\+\s*\ze:'                containedin=BuffersaurusSyntaxContextLines
        "         syn match BuffersaurusSyntaxContextLineText           ': \zs.*\ze'                          containedin=BuffersaurusSyntaxContextLines

        "         syn match BuffersaurusSyntaxMatchedLineNum            '^  \zs\s*\d\+\s*\ze>'                containedin=BuffersaurusSyntaxMatchedLines
        "         syn match BuffersaurusSyntaxMatchedLineText           '> \zs.*\ze'                          containedin=BuffersaurusSyntaxMatchedLines
        "     else
        "         syn match BuffersaurusSyntaxFileGroupTitle             '^\zs::: .* :::\ze.*$'                   nextgroup=BuffersaurusSyntaxKey
        "         syn match BuffersaurusSyntaxKey                        '^  \zs\[\s\{-}.\{-1,}\s\{-}\]\ze'       nextgroup=BuffersaurusSyntaxUncontextedLineNum
        "         syn match BuffersaurusSyntaxUncontextedLineNum         '\s\+\s*\zs\d\+\ze:'                nextgroup=BuffersaurusSyntaxUncontextedLineText
        "     endif
        "     highlight! link BuffersaurusSyntaxFileGroupTitle       Title
        "     highlight! link BuffersaurusSyntaxKey                  Identifier
        "     highlight! link BuffersaurusSyntaxContextedKeyFilename Comment
        "     highlight! link BuffersaurusSyntaxContextedKeyLines    Comment
        "     highlight! link BuffersaurusSyntaxContextedKeyDesc     Comment
        "     highlight! link BuffersaurusSyntaxContextLineNum       Normal
        "     highlight! link BuffersaurusSyntaxContextLineText      Normal
        "     highlight! link BuffersaurusSyntaxMatchedLineNum       Question
        "     highlight! link BuffersaurusSyntaxMatchedLineText      Question
        "     highlight! link BuffersaurusSyntaxUncontextedLineNum   Question
        "     highlight! link BuffersaurusSyntaxUncontextedLineText  Normal
        "     highlight! def BuffersaurusCurrentEntry gui=reverse cterm=reverse term=reverse
        " endif
    endfunction

    " Sets buffer commands.
    function! l:catalog_viewer.setup_buffer_commands() dict
        " command! -bang -nargs=* Bdfilter :call b:buffergator_catalog_viewer.set_filter('<bang>', <q-args>)
        " augroup BuffersaurusCatalogViewer
        "     au!
        "     autocmd CursorHold,CursorHoldI,CursorMoved,CursorMovedI,BufEnter,BufLeave <buffer> call b:buffergator_catalog_viewer.highlight_current_line()
        "     autocmd BufLeave <buffer> let s:_buffergator_last_catalog_viewed = b:buffergator_catalog_viewer
        " augroup END
    endfunction

    " Sets buffer key maps.
    function! l:catalog_viewer.setup_buffer_keymaps() dict

        """" Index buffer management
        " noremap <buffer> <silent> c       :call b:buffergator_catalog_viewer.toggle_context()<CR>
        " noremap <buffer> <silent> s       :call b:buffergator_catalog_viewer.cycle_sort_regime()<CR>
        " noremap <buffer> <silent> f       :call b:buffergator_catalog_viewer.toggle_filter()<CR>
        " noremap <buffer> <silent> F       :call b:buffergator_catalog_viewer.prompt_and_apply_filter()<CR>
        " noremap <buffer> <silent> u       :call b:buffergator_catalog_viewer.rebuild_catalog()<CR>
        " noremap <buffer> <silent> <C-G>   :call b:buffergator_catalog_viewer.catalog.describe()<CR>
        " noremap <buffer> <silent> g<C-G>  :call b:buffergator_catalog_viewer.catalog.describe_detail()<CR>
        " noremap <buffer> <silent> q       :call b:buffergator_catalog_viewer.quit_view()<CR>

        """" Movement within buffer

        " jump to next/prev key entry
        " noremap <buffer> <silent> <C-N>  :<C-U>call b:buffergator_catalog_viewer.goto_index_entry("n", 0, 1)<CR>
        " noremap <buffer> <silent> <C-P>  :<C-U>call b:buffergator_catalog_viewer.goto_index_entry("p", 0, 1)<CR>

        " jump to next/prev file entry
        " noremap <buffer> <silent> ]f     :<C-U>call b:buffergator_catalog_viewer.goto_file_start("n", 0, 1)<CR>
        " noremap <buffer> <silent> [f     :<C-U>call b:buffergator_catalog_viewer.goto_file_start("p", 0, 1)<CR>

        """" Movement within buffer that updates the other window

        " show target line in other window, keeping catalog open and in focus
        " noremap <buffer> <silent> .           :call b:buffergator_catalog_viewer.visit_target(1, 1, "")<CR>
        " noremap <buffer> <silent> <SPACE>     :<C-U>call b:buffergator_catalog_viewer.goto_index_entry("n", 1, 1)<CR>
        " noremap <buffer> <silent> <C-SPACE>   :<C-U>call b:buffergator_catalog_viewer.goto_index_entry("p", 1, 1)<CR>
        " noremap <buffer> <silent> <C-@>       :<C-U>call b:buffergator_catalog_viewer.goto_index_entry("p", 1, 1)<CR>

        """" Movement that moves to the current search target

        " go to target line in other window, keeping catalog open
        " noremap <buffer> <silent> <CR>  :call b:buffergator_catalog_viewer.visit_target(1, 0, "")<CR>
        " noremap <buffer> <silent> o     :call b:buffergator_catalog_viewer.visit_target(1, 0, "")<CR>
        " noremap <buffer> <silent> ws    :call b:buffergator_catalog_viewer.visit_target(1, 0, "sb")<CR>
        " noremap <buffer> <silent> wv    :call b:buffergator_catalog_viewer.visit_target(1, 0, "vert sb")<CR>

        " open target line in other window, closing catalog
        " noremap <buffer> <silent> O     :call b:buffergator_catalog_viewer.visit_target(0, 0, "")<CR>
        " noremap <buffer> <silent> wS    :call b:buffergator_catalog_viewer.visit_target(0, 0, "sb")<CR>
        " noremap <buffer> <silent> wV    :call b:buffergator_catalog_viewer.visit_target(0, 0, "vert sb")<CR>

    endfunction

    " Sets buffer folding.
    function! l:catalog_viewer.setup_buffer_folding() dict
        " if has("folding")
        "     "setlocal foldcolumn=3
        "     setlocal foldmethod=syntax
        "     setlocal foldlevel=4
        "     setlocal foldenable
        "     setlocal foldtext=BuffersaurusFoldText()
        "     " setlocal fillchars=fold:\ "
        "     setlocal fillchars=fold:.
        " endif
    endfunction

    " Sets buffer status line.
    function! l:catalog_viewer.setup_buffer_statusline() dict
        " setlocal statusline=\-buffergator\-\|\ %{BuffersaurusStatusLineCurrentLineInfo()}%<%=\|%{BuffersaurusStatusLineSortRegime()}\|%{BuffersaurusStatusLineFilterRegime()}
        " setlocal statusline=\-buffergator\-\|\ %{BuffersaurusStatusLineCurrentLineInfo()}%<%=\|%{BuffersaurusStatusLineSortRegime()}
    endfunction

    " Populates the buffer with the catalog index.
    function! l:catalog_viewer.render_buffer() dict
        setlocal modifiable
        call self.claim_buffer()
        call self.clear_buffer()
        let self.jump_map = {}
        call self.setup_buffer_syntax()
        let l:buffer_catalog_keys = sort(keys(self.buffers_catalog))
        for l:key in l:buffer_catalog_keys
            let l:bufinfo = self.buffers_catalog[key]
            let l:bufnum_str = s:_format_filled(l:bufinfo.bufnum, 3, 1, 0)
            let l:line = "[" . l:bufnum_str . "] "
            if self.buffer_catalog_display == "basename"
                let l:line .= s:_format_align_left(l:bufinfo.basename, 30, " ")
                let l:line .= fnamemodify(l:bufinfo.filepath, ":h")
            elseif self.buffer_catalog_display == "filepath"
                let l:line .= l:bufinfo.filepath
            elseif self.buffer_catalog_display == "bufname"
                let l:line .= l:bufinfo.bufname
            else
                throw s:_buffergator_messenger.format_exception("Invalid display mode")
            endif
            call self.append_line(l:line, l:bufinfo.bufnum)
        endfor
        let b:buffergator_last_render_time = localtime()
        try
            " remove extra last line
            execute("normal! GVX")
        catch //
        endtry
        setlocal nomodifiable
        call cursor(1, 1)
        " call self.goto_index_entry("n", 0, 1)
    endfunction

    " Appends a line to the buffer and registers it in the line log.
    function! l:catalog_viewer.append_line(text, jump_to_bufnum) dict
        let l:line_map = {
                    \ "target" : [a:jump_to_bufnum],
                    \ }
        if a:0 > 0
            call extend(l:line_map, a:1)
        endif
        let self.jump_map[line("$")] = l:line_map
        call append(line("$")-1, a:text)
    endfunction

    " Close and quit the viewer.
    function! l:catalog_viewer.quit_view() dict
        execute("bwipe " . self.bufnum)
    endfunction

    function! l:catalog_viewer.highlight_current_line()
        " if line(".") != b:buffergator_cur_line
            let l:prev_line = b:buffergator_cur_line
            let b:buffergator_cur_line = line(".")
            3match none
            exec '3match BuffersaurusCurrentEntry /^\%'. b:buffergator_cur_line .'l.*/'
        " endif
    endfunction

    " Clears the buffer contents.
    function! l:catalog_viewer.clear_buffer() dict
        call cursor(1, 1)
        exec 'silent! normal! "_dG'
    endfunction

    " Returns a string corresponding to line `ln1` from buffer ``buf``.
    " If the line is unavailable, then "#INVALID#LINE#" is returned.
    function! l:catalog_viewer.fetch_buf_line(buf, ln1)
        let l:lines = getbufline(a:buf, a:ln1)
        if len(l:lines) > 0
            return l:lines[0]
        else
            return "#INVALID#LINE#"
        endif
    endfunction

    " Returns a list of strings corresponding to the contents of lines from
    " `ln1` to `ln2` from buffer `buf`. If lines are not available, returns a
    " list with (ln2-ln1+1) elements consisting of copies of the string
    " "#INVALID LINE#".
    function! l:catalog_viewer.fetch_buf_lines(buf, ln1, ln2)
        let l:lines = getbufline(a:buf, a:ln1, a:ln2)
        if len(l:lines) > 0
            return l:lines
        else
            let l:lines = []
            for l:idx in range(a:ln1, a:ln2)
                call add(l:lines, "#INVALID#LINE#")
            endfor
            return l:lines
        endif
    endfunction

    " from NERD_Tree, via VTreeExplorer: determine the number of windows open
    " to this buffer number.
    function! l:catalog_viewer.num_viewports_on_buffer(bnum) dict
        let cnt = 0
        let winnum = 1
        while 1
            let bufnum = winbufnr(winnum)
            if bufnum < 0
                break
            endif
            if bufnum ==# a:bnum
                let cnt = cnt + 1
            endif
            let winnum = winnum + 1
        endwhile
        return cnt
    endfunction

    " from NERD_Tree: find the window number of the first normal window
    function! l:catalog_viewer.first_usable_viewport() dict
        let i = 1
        while i <= winnr("$")
            let bnum = winbufnr(i)
            if bnum != -1 && getbufvar(bnum, '&buftype') ==# ''
                        \ && !getwinvar(i, '&previewwindow')
                        \ && (!getbufvar(bnum, '&modified') || &hidden)
                return i
            endif

            let i += 1
        endwhile
        return -1
    endfunction

    " from NERD_Tree: returns 0 if opening a file from the tree in the given
    " window requires it to be split, 1 otherwise
    function! l:catalog_viewer.is_usable_viewport(winnumber) dict
        "gotta split if theres only one window (i.e. the NERD tree)
        if winnr("$") ==# 1
            return 0
        endif
        let oldwinnr = winnr()
        execute(a:winnumber . "wincmd p")
        let specialWindow = getbufvar("%", '&buftype') != '' || getwinvar('%', '&previewwindow')
        let modified = &modified
        execute(oldwinnr . "wincmd p")
        "if its a special window e.g. quickfix or another explorer plugin then we
        "have to split
        if specialWindow
            return 0
        endif
        if &hidden
            return 1
        endif
        return !modified || self.num_viewports_on_buffer(winbufnr(a:winnumber)) >= 2
    endfunction

    " Acquires a viewport to show the source buffer. Returns the split command
    " to use when switching to the buffer.
    function! l:catalog_viewer.acquire_viewport(split_cmd)
        if self.split_mode == "buffer" && empty(a:split_cmd)
            " buffergator used original buffer's viewport,
            " so the the buffergator viewport is the viewport to use
            return ""
        endif
        if !self.is_usable_viewport(winnr("#")) && self.first_usable_viewport() ==# -1
            " no appropriate viewport is available: create new using default
            " split mode
            " TODO: maybe use g:buffergator_viewport_split_policy?
            if empty(a:split_cmd)
                return "sb"
            else
                return a:split_cmd
            endif
        else
            try
                if !self.is_usable_viewport(winnr("#"))
                    execute(self.first_usable_viewport() . "wincmd w")
                else
                    execute('wincmd p')
                endif
            catch /^Vim\%((\a\+)\)\=:E37/
                echo v:exception
                " call s:putCursorInTreeWin()
                " throw "NERDTree.FileAlreadyOpenAndModifiedError: ". self.path.str() ." is already open and modified."
            catch /^Vim\%((\a\+)\)\=:/
                echo v:exception
            endtry
            return a:split_cmd
        endif
    endfunction

    " Visits the specified buffer in the previous window, if it is already
    " visible there. If not, then it looks for the first window with the
    " buffer showing and visits it there. If no windows are showing the
    " buffer, ... ?
    function! l:catalog_viewer.visit_buffer(bufnum, split_cmd) dict
        " acquire window
        let l:split_cmd = self.acquire_viewport(a:split_cmd)
        " switch to buffer in acquired window
        let l:old_switch_buf = &switchbuf
        if empty(l:split_cmd)
            " explicit split command not given: switch to buffer in current
            " window
            let &switchbuf="useopen"
            execute("silent keepalt keepjumps buffer " . a:bufnum)
        else
            " explcit split command given: split current window
            let &switchbuf="split"
            execute("silent keepalt keepjumps " . l:split_cmd . " " . a:bufnum)
        endif
        let &switchbuf=l:old_switch_buf
        endfunction

    " Go to the line mapped to by the current line/index of the catalog
    " viewer.
    function! l:catalog_viewer.visit_target(keep_catalog, refocus_catalog, split_cmd) dict
        let l:cur_line = line(".")
        if !has_key(l:self.jump_map, l:cur_line)
            call s:_buffergator_messenger.send_info("Not a valid navigation line")
            return 0
        endif
        let [l:jump_to_bufnum, l:jump_to_lnum, l:jump_to_col, l:dummy] = self.jump_map[l:cur_line].target
        let l:cur_win_num = winnr()
        if !a:keep_catalog
            call self.quit_view()
        endif
        call self.visit_buffer(l:jump_to_bufnum, a:split_cmd)
        call setpos('.', [l:jump_to_bufnum, l:jump_to_lnum, l:jump_to_col, l:dummy])
        execute(s:buffergator_post_move_cmd)
        if a:keep_catalog && a:refocus_catalog && winnr() != l:cur_win_num
            execute(l:cur_win_num."wincmd w")
        endif
        let l:report = ""
        if self.jump_map[l:cur_line].entry_index >= 0
            let l:report .= "(" . string(self.jump_map[l:cur_line].entry_index + 1). " of " . self.catalog.size() . "): "
            let l:report .= '"' . expand(bufname(l:jump_to_bufnum)) . '", Line ' . l:jump_to_lnum
        else
            let l:report .= 'File: "'  . expand(bufname(l:jump_to_bufnum)) . '"'
        endif

        call s:_buffergator_messenger.send_info(l:report)
    endfunction

    " Finds next line with occurrence of a rendered index
    function! l:catalog_viewer.goto_index_entry(direction, visit_target, refocus_catalog) dict
        let l:ok = self.goto_pattern("^  \[", a:direction)
        execute("normal! zz")
        if l:ok && a:visit_target
            call self.visit_target(1, a:refocus_catalog, "")
        endif
    endfunction

    " Finds next line with occurrence of a file pattern.
    function! l:catalog_viewer.goto_file_start(direction, visit_target, refocus_catalog) dict
        let l:ok = self.goto_pattern("^:::", a:direction)
        execute("normal! zz")
        if l:ok && a:visit_target
            call self.visit_target(1, a:refocus_catalog, "")
        endif
    endfunction

    " Finds next occurrence of specified pattern.
    function! l:catalog_viewer.goto_pattern(pattern, direction) dict range
        if a:direction == "b" || a:direction == "p"
            let l:flags = "b"
            " call cursor(line(".")-1, 0)
        else
            let l:flags = ""
            " call cursor(line(".")+1, 0)
        endif
        if g:buffergator_move_wrap
            let l:flags .= "W"
        else
            let l:flags .= "w"
        endif
        let l:flags .= "e"
        let l:lnum = -1
        for i in range(v:count1)
            if search(a:pattern, l:flags) < 0
                break
            else
                let l:lnum = 1
            endif
        endfor
        if l:lnum < 0
            if l:flags[0] == "b"
                call s:_buffergator_messenger.send_info("No previous results")
            else
                call s:_buffergator_messenger.send_info("No more results")
            endif
            return 0
        else
            return 1
        endif
    endfunction

    " Toggles context on/off.
    function! l:catalog_viewer.toggle_context() dict
        let self.catalog.show_context = !self.catalog.show_context
        let l:line = line(".")
        if has_key(b:buffergator_catalog_viewer.jump_map, l:line)
            let l:jump_line = b:buffergator_catalog_viewer.jump_map[l:line]
            if l:jump_line.entry_index > 0
                let l:entry_index = l:jump_line.entry_index
            elseif has_key(l:jump_line, "proxy_key")
                let l:entry_index = l:jump_line.proxy_key
            else
                let l:entry_index = ""
            endif
        else
            let l:entry_index = ""
        endif
        call self.open(1)
        if !empty(l:entry_index)
            let l:rendered_entry_index = self.render_entry_index(l:entry_index)
            let l:lnum = search('^'.escape(l:rendered_entry_index, '[]'), "e")
            if l:lnum > 0
                call setpos(".", [bufnr("%"), l:lnum, 0, 0])
                execute("normal! zz")
            endif
        endif
    endfunction

    " Cycles sort regime.
    function! l:catalog_viewer.cycle_sort_regime() dict
        call self.catalog.cycle_sort_regime()
        call self.open(1)
        call s:_buffergator_messenger.send_info("sorted " . self.catalog.format_sort_status())
    endfunction

    " Rebuilds catalog.
    function! l:catalog_viewer.rebuild_catalog() dict
        call self.update_buffers_info()
        call s:_buffergator_messenger.send_info("updated index: found " . self.catalog.format_status_message())
        call self.open(1)
    endfunction

    " return object
    return l:catalog_viewer

endfunction
" 1}}}

" Global Initialization {{{1
" ==============================================================================
if exists("s:_buffergator_messenger")
    unlet s:_buffergator_messenger
endif
let s:_buffergator_messenger = s:NewMessenger("")
" 1}}}

" Functions Supporting Global Commands {{{1
" ==============================================================================
function! s:ShowBuffergator(global)
    let l:catalog_viewer = s:NewCatalogViewer()
    call l:catalog_viewer.open()
endfunction
" 1}}}

" Public Command and Key Maps {{{1
" ==============================================================================
command! -bang -nargs=*         Buffergator          :call <SID>ShowBuffergator('<bang>')
" 1}}}

" Restore State {{{1
" ============================================================================
" restore options
let &cpo = s:save_cpo
" 1}}}

" vim:foldlevel=4:
