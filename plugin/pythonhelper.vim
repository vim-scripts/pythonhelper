" File: pythonhelper.vim
" Author: Michal Vitecek <fuf-at-mageo-dot-cz>
" Version: 0.7
" Last Modified: Oct 2, 2002
"
" Overview
" --------
" Vim script to help moving around in larger Python source files. It displays
" current class, method or function the cursor is placed in in the status
" line for every python file. It's more clever than Yegappan Lakshmanan's
" taglist.vim because it takes into account indetation and comments to
" determine what tag the cursor is placed in.
"
" Requirements
" ------------
" This script needs VIM compiled with Python interpreter and relies on
" exuberant ctags utility to generate the tag listing. You can determine
" whether your VIM has Python support by issuing command :ver and looking for
" +python in the list of features.
"
" The exuberant ctags can be downloaded from http://ctags.sourceforge.net/ and
" should be reasonably new version (tested with 5.3).
"
" Note: The script doesn't display current tag on the status line only in
" NORMAL mode. This is because CursorHold event is fired up only in this mode.
" However if you badly need to know what tag you are on even in INSERT or
" VISUAL mode, contact me on the above specified email address and I'll send
" you patch that enables it.
"
" Installation
" ------------
" 1. Make sure your Vim has python feature on (+python). If not, you will need
"    to recompile it with --with-pythoninterp option to the configure script
" 2. Copy script pythonhelper.vim to the $HOME/.vim/plugin directory
" 3. Edit the script and modify the location of your exuberant tags utility
"    (variable CTAGS_PROGRAM).
" 4. Run Vim and open any python file.
" 
python << EOS

# import of required modules {{{
import vim
import os
import popen2
import time
import sys
# }}}


# CTAGS program and parameters {{{
CTAGS_PROGRAM = "/usr/local/bin/ctags"
CTAGS_PARAMETERS = "--language-force=python --format=2 --sort=0 --fields=+nK -L - -f - "
# }}}

# global dictionaries of tags and their line numbers, keys are buffer numbers {{{
TAGS = {}
TAGLINENUMBERS = {}
BUFFERTICKS = {}
# }}}


def getNearestLineIndex(row, tagLineNumbers):
    # DOC {{{
    """Returns index of line in tagLineNumbers list that is nearest to the
    current cursor row.

    Parameters

	row -- current cursor row

	tagLineNumbers -- list of tags' line numbers (ie. their position)
    """
    # }}}

    # CODE {{{
    nearestLineNumber = -1
    nearestLineIndex = -1
    i = 0
    for lineNumber in tagLineNumbers:
	# if the current line is nearer the current cursor position, take it {{{
	if (nearestLineNumber < lineNumber <= row):
	    nearestLineNumber = lineNumber
	    nearestLineIndex = i
	# }}}
	# if we've got past the current cursor position, let's end the search {{{
	if (lineNumber >= row):
	    break
	# }}}
	i += 1
    return nearestLineIndex
    # }}}


def getTags(bufferNumber, changedTick):
    # DOC {{{
    """Reads the tags for the specified buffer number. It does so by executing
    the CTAGS program and parsing its output. Returns tuple
    (taglinenumber[buffer], tags[buffer]).

    Parameters

	bufferNumber -- number of the current buffer

	changedTick -- ever increasing number used to tell if the buffer has
	    been modified since the last time
    """
    # }}}

    # CODE {{{
    global	CTAGS_PROGRAM, CTAGS_PARAMETERS
    global	TAGLINENUMBERS, TAGS, BUFFERTICKS


    # return immediately if there's no need to update the tags {{{
    if ((BUFFERTICKS.has_key(bufferNumber)) and (BUFFERTICKS[bufferNumber] == changedTick)):
	return (TAGLINENUMBERS[bufferNumber], TAGS[bufferNumber],)
    # }}}

    # read the tags and fill the global variables {{{
    currentBuffer = vim.current.buffer
    currentWindow = vim.current.window
    row, col = currentWindow.cursor

    # create a temporary file with the current content of the buffer {{{
    fileName = "/tmp/.%s.%u.ph" % (os.path.basename(currentBuffer.name), os.getpid(),)
    f = open(fileName, "w")

    for line in currentBuffer:
	f.write(line)
	f.write('\n')
    f.close()
    # }}}

    # run ctags on it {{{
    try:
	ctagsOutPut, ctagsInPut = popen2.popen4("%s %s" % (CTAGS_PROGRAM, CTAGS_PARAMETERS,))
	ctagsInPut.write(fileName + "\n")
	ctagsInPut.close()
    except:
	os.unlink(fileName)
	return
    # }}}

    # parse the ctags' output {{{
    tagLineNumbers = []
    tags = {}
    while 1:
	line = ctagsOutPut.readline()
        # if empty line has been read, it's the end of the file {{{
	if (line == ''):
	    break
        # }}}
        # if the line starts with !, then it's a comment line {{{
	if (line[0] == '!'):
	    continue
        # }}}
	
        # split the line into parts and parse the data {{{
        # the format is: [0]tagName [1]fileName [2]tagLine [3]tagType [4]tagLineNumber [[5]tagOwner]
	tagData = line.split('\t')
	name = tagData[0]
        # get the tag's indentation {{{
	start = 2
	j = 2
	while ((j < len(tagData[2])) and (tagData[2][j].isspace())):
	    if (tagData[2][j] == '\t'):
		start += 8
	    else:
		start += 1
	    j += 1
        # }}}
	type = tagData[3]
	line = int(tagData[4][5:])
	if (len(tagData) == 6):
	    owner = tagData[5].strip()
	else:
	    owner = None
        # }}}
	tagLineNumbers.append(line)
	tags[line] = (name, type, owner, start)
    ctagsOutPut.close()
    # }}}

    # clean up the now unnecessary stuff {{{
    os.unlink(fileName)
    # }}}

    # update the global variables {{{
    TAGS[bufferNumber] = tags
    TAGLINENUMBERS[bufferNumber] = tagLineNumbers
    BUFFERTICKS[bufferNumber] = changedTick
    # }}}
    # }}}

    return (TAGLINENUMBERS[bufferNumber], TAGS[bufferNumber],)
    # }}}


def findTag(bufferNumber, changedTick):
    # DOC {{{
    """Tries to find the best tag for the current cursor position.

    Parameters

	bufferNumber -- number of the current buffer

	changedTick -- ever increasing number used to tell if the buffer has
	    been modified since the last time
    """
    # }}}

    # CODE {{{
    try:
	# get the tags data for the current buffer
	tagLineNumbers, tags = getTags(bufferNumber, changedTick)

	# link to vim internal data {{{
	currentBuffer = vim.current.buffer
	currentWindow = vim.current.window
	row, col = currentWindow.cursor
	# }}}

	# get the index of the nearest line
	nearestLineIndex = getNearestLineIndex(row, tagLineNumbers)
	# if any line was found, try to find if the tag is appropriate {{{
	# (ie. the cursor can be below the last tag but on a code that has nothing
	# to do with the tag, because it's indented differently, in such case no
	# appropriate tag has been found.)
	if (nearestLineIndex > -1):
	    nearestLineNumber = tagLineNumbers[nearestLineIndex]
	    # walk through all the lines in range (nearestTagLine, cursorRow) {{{
	    for i in xrange(nearestLineNumber + 1, row):
		line = currentBuffer[i]
		# count the indentation of the line, if it's lower that the tag's, the found tag is wrong {{{
		if (len(line)):
                    # compute the indentation of the line {{{
		    lineStart = 0
		    j = 0
		    while ((j < len(line)) and (line[j].isspace())):
			if (line[j] == '\t'):
			    lineStart += 8
			else:
			    lineStart += 1
			j += 1
                    # if the line contains only spaces, it doesn't count {{{
                    if (j == len(line)):
                        continue
                    # }}}
                    # if the next character is # (python comment), this line doesn't count {{{
                    if (line[j] == '#'):
                        continue
                    # }}}
                    # }}}
                    # if the line's indentation starts before the nearest tag's one, the tag is wrong {{{
		    if (lineStart < tags[nearestLineNumber][3]):
			nearestLineNumber = -1
			break
                    # }}}
		# }}}
	    # }}}
	else:
	    nearestLineNumber = -1
	# }}}
	 
	# describe the cursor position (what tag it's in) {{{
	tagDescription = ""
	if (nearestLineNumber > -1):
	    tagInfo = tags[nearestLineNumber]
	    # use the owner if any exists {{{
	    if (tagInfo[2] != None):
		fullTagName = "%s.%s()" % (tagInfo[2].split(':')[1], tagInfo[0],)
	    # }}}
	    # otherwise use just the tag name {{{
	    else:
		fullTagName = tagInfo[0]
	    # }}}
	    tagDescription = "[in %s (%s)]" % (fullTagName, tagInfo[1],)
	# }}}

	# update the variable for the status line so it will be updated next time
	vim.command("let w:PHStatusLine=\"%s\"" % (tagDescription,))
    except:
        # spit out debugging information {{{
	ec, ei, tb = sys.exc_info()
	while (tb != None):
	    if (tb.tb_next == None):
		break
	    tb = tb.tb_next
	print "ERROR: %s %s %s:%u" % (ec.__name__, ei, tb.tb_frame.f_code.co_filename, tb.tb_lineno,)
	time.sleep(0.5)
        # }}}
    # }}}


def deleteTags(bufferNumber):
    # DOC {{{
    """Removes tags data for the specified buffer number.

    Parameters

        bufferNumber -- number of the buffer
    """
    # }}}

    # CODE {{{
    global TAGS, TAGLINENUMBERS, BUFFERTICKS
    
    try:
        del TAGS[bufferNumber]
        del TAGLINENUMBERS[bufferNumber]
        del BUFFERTICKS[bufferNumber]
    except:
        pass
    # }}}


EOS


function! PHCursorHold()
    " only python is supported {{{
    if (exists('b:current_syntax') && (b:current_syntax != 'python'))
	let w:PHStatusLine = ''
	return
    endif
    " }}}
    
    " call python function findTag() with the current buffer number and changed ticks
    execute 'python findTag(' . expand("<abuf>") . ', ' . b:changedtick . ')'
endfunction


function! PHBufferDelete()
    " call python function deleteTags() with the cur
    execute 'python deleteTags(' . expand("<abuf>") . ')'
endfunction



" autocommands binding
autocmd CursorHold * silent call PHCursorHold()
autocmd BufWinEnter * silent call PHCursorHold()
autocmd BufDelete * silent call PHBufferDelete()

" time that determines after how long time of no activity the CursorHold event
" is fired up
set updatetime=1000

" color of the current tag in the status line (bold cyan on black)
highlight User1 gui=bold guifg=cyan guibg=black
" color of the modified flag in the status line (bold black on red)
highlight User2 gui=bold guifg=black guibg=red
" the status line will be displayed for every window
set laststatus=2
" set the status variable for the current window
let w:PHStatusLine = ''
" set the status line to display some useful information
set stl=%-f%r\ %2*%m%*\ \ \ \ %1*%{w:PHStatusLine}%*%=[%l:%c]\ \ \ \ [buf\ %n]
