" File: closetag.vim
" Summary: Functions and mappings to close open HTML/XML tags
" Uses: <C-_> -- close matching open tag
" Author: Steven Mueller <diffusor@ugcs.caltech.edu>
" Last Modified: Tue Jun 05 21:32:03 PDT 2001 
" Version: 0.8
" TODO - bug in tag completion for vim 5.7: gets out of sync if a tag is 
" on the same line as the cursor, but after the cursor's position
" (works fine in vim60aa+)
" TODO - make matching work for all comments
"
" Description:
" This script eases redundant typing when writing html or xml files (even if
" you're very good with ctrl-p and ctrl-n  :).  Hitting ctrl-_ will initiate a
" search for the most recent open tag above that is not closed in the
" intervening space and then insert the matching close tag at the cursor.  In
" normal mode, the close tag is inserted one character after cursor rather than
" at it, as if a<C-_> had been used.  This allows putting close tags at the
" ends of lines while in normal mode, but disallows inserting them in the
" first column.
"
" For HTML, a configurable list of tags are ignored in the matching process.
" By default, the following tags will not be matched and thus not closed
" automatically: Area, Base, Br, DD, DT, HR, Img, Input, LI, Link, Meta, P,
" and Param.
"
" For XML, all tags must have a closing match or be terminated by />, as in
" <empty-element/>.  These empty element tags are ignored for matching.
"
" Comments are not currently handled very well, so commenting out HTML in
" certain ways may cause a "tag mismatch" message and no completion.  ie,
" having '<!-- a href="blah">link!</a -->' between the cursor and the most
" recent open tag above doesn't work.  Well matched tags in comments don't
" cause a problem.
"
" Install:
" To use, place this file in your standard vim scripts directory, and source
" it while editing the file you wish to close tags in.  If the filetype is not
" set or the file is some sort of template with embedded HTML, you may get
" HTML style tag matching by first setting the closetag_html_style global
" variable.  Otherwise, the default is XML style tag matching.
"
" Example:
"   :let g:closetag_html_style=1
"   :source ~/.vim/scripts/closetag.vim
"
" For greater convenience, load this script in an autocommand:
"   :au Filetype html,xml,xsl source ~/.vim/scripts/closetag.vim
"
" Also, set noignorecase for html files or edit b:unaryTagsStack to match your
" capitalization style.  You may set this variable before or after loading the
" script, or simply change the file itself.

"------------------------------------------------------------------------------
" User configurable settings
"------------------------------------------------------------------------------

" if html, don't close certain tags.  Works best if ignorecase is set.
" otherwise, capitalize these elements according to your html editing style
if !exists("b:unaryTagsStack")
    if &filetype == "html" || exists("g:closetag_html_style")
	let b:unaryTagsStack="Area Base Br DD DT HR Img Input LI Link Meta P Param"
    else " for xsl and xsl
	let b:unaryTagsStack=""
    endif
endif

" Has this already been loaded?
if exists("loaded_closetag")
    finish
endif
let loaded_closetag=1

" set up mappings for tag closing
imap <C-_> <C-R>=GetCloseTag()<CR>
map <C-_> "=GetCloseTag()<CR>p

"------------------------------------------------------------------------------
" Tag closer - uses the stringstack implementation below
"------------------------------------------------------------------------------

" Returns the most recent unclosed tag-name
" (ignores tags in the variable referenced by a:unaryTagsStack)
function! GetLastOpenTag(unaryTagsStack)
    " Search backwards through the file line by line using getline()
    " Overall strategy (moving backwards through the file from the cursor):
    "  Push closing tags onto a stack.
    "  On an opening tag, if the tag matches the stack top, discard both.
    "   -- if the tag doesn't match, signal an error.
    "   -- if the stack is empty, use this tag
    let linenum=line(".")
    let lineend=col(".") - 1 " start: cursor position
    let first=1              " flag for first line searched
    let b:TagStack=""        " main stack of tags

    let tagpat='</\=\(\k\|[-:]\)\+\|/>'
    " Search for: closing tags </tag, opening tags <tag, and unary tag ends />
    while (linenum>0)
	" Every time we see an end-tag, we push it on the stack.  When we see an
	" open tag, if the stack isn't empty, we pop it and see if they match.
	" If no, signal an error.
	" If yes, continue searching backwards.
	" If stack is empty, return this open tag as the one that needs closing.
	let line=getline(linenum)
	if first
	    let line=strpart(line,0,lineend)
	else
	    let lineend=strlen(line)
	endif
	let b:lineTagStack=""
	let mpos=0
	" Search the current line in the forward direction, pushing any tags
	" onto a special stack for the current line
	while (mpos > -1)
	    let mpos=matchend(line,tagpat)
	    if mpos > -1
		let tag=matchstr(line,tagpat)
		call Push(matchstr(tag,'[^<>]\+'),"b:lineTagStack")
		"echo "Tag: ".tag." ending at position ".mpos." in '".line."'."
		let lineend=lineend-mpos
		let line=strpart(line,mpos,lineend)
	    endif
	endwhile
	" Process the current line stack
	while (!EmptystackP("b:lineTagStack"))
	    let tag=Pop("b:lineTagStack")
	    if match(tag, "^/") == 0		"found end tag
		call Push(tag,"b:TagStack")
		"echo linenum." ".b:TagStack
	    elseif EmptystackP("b:TagStack") && !Instack(tag, a:unaryTagsStack)	"found unclosed tag
		return tag
	    else
		let endtag=Peekstack("b:TagStack")
		if endtag == "/".tag || endtag == "/"
		    call Pop("b:TagStack")	"found a open/close tag pair
		    "echo linenum." ".b:TagStack
		elseif !Instack(tag, a:unaryTagsStack) "we have a mismatch error
		    echohl Error
		    echon "\rError:"
		    echohl None
		    echo " tag mismatch: <".tag."> doesn't match <".endtag.">.  (Line ".linenum." Tagstack: ".b:TagStack.")"
		    return ""
		endif
	    endif
	endwhile
	let linenum=linenum-1 | let first=0
    endwhile
    " At this point, we have exhausted the file and not found any opening tag
    echo "No opening tags."
    return ""
endfunction

" Returns closing tag for most recent unclosed tag, respecting the
" current setting of b:unaryTagsStack for tags that should not be closed
function! GetCloseTag()
    let tag=GetLastOpenTag("b:unaryTagsStack")
    if tag == ""
	return ""
    else
	return "</".tag.">"
    endif
endfunction


"------------------------------------------------------------------------------
" String Stacks
"------------------------------------------------------------------------------
" These are strings of whitespace-separated elements, matched using the \< and
" \> patterns after setting the iskeyword option.
" 
" The sname argument should contain a symbolic reference to the stack variable
" on which method should operate on (i.e., sname should be a string containing
" a fully qualified (ie: g:, b:, etc) variable name.)

" Helper functions
function! SetKeywords()
    let g:IsKeywordBak=&iskeyword
    let &iskeyword="33-255"
endfunction

function! RestoreKeywords()
    let &iskeyword=g:IsKeywordBak
endfunction

" Push el onto the stack referenced by sname
function! Push(el, sname)
    if !EmptystackP(a:sname)
	exe "let ".a:sname."=a:el.' '.".a:sname
    else
	exe "let ".a:sname."=a:el"
    endif
endfunction

" Check whether the stack is empty
function! EmptystackP(sname)
    exe "let stack=".a:sname
    if match(stack,"^ *$") == 0
	return 1
    else
	return 0
    endif
endfunction

" Return 1 if el is in stack sname, else 0.
function! Instack(el, sname)
    exe "let stack=".a:sname
    call SetKeywords()
    let m=match(stack, "\\<".a:el."\\>")
    call RestoreKeywords()
    if m < 0
	return 0
    else
	return 1
    endif
endfunction

" Return the first element in the stack
function! Peekstack(sname)
    call SetKeywords()
    exe "let stack=".a:sname
    let top=matchstr(stack, "\\<.\\{-1,}\\>")
    call RestoreKeywords()
    return top
endfunction

" Remove and return the first element in the stack
function! Pop(sname)
    if EmptystackP(a:sname)
	echo "Error!  Stack ".a:sname." is empty and can't be popped."
	return ""
    endif
    exe "let stack=".a:sname
    " Find the first space, loc is 0-based.  Marks the end of 1st elt in stack.
    call SetKeywords()
    let loc=matchend(stack,"\\<.\\{-1,}\\>")
    exe "let ".a:sname."=strpart(stack, loc+1, strlen(stack))"
    let top=strpart(stack, match(stack, "\\<"), loc)
    call RestoreKeywords()
    return top
endfunction

function! Clearstack(sname)
    exe "let ".a:sname."=''"
endfunction
