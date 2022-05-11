---------------------------------------------------------------------
--     This Lua5 module is Copyright (c) 2011, Peter J Billam      --
--                       www.pjb.com.au                            --
--                                                                 --
--  This module is free software; you can redistribute it and/or   --
--         modify it under the same terms as Lua5 itself.          --
---------------------------------------------------------------------

local M = {} -- public interface
M.Version     = '2.9' -- fix version number again
M.VersionDate = '27jan2021'

--[[
Alexander Adler suggests adding four Alternate-Interface functions:
https://tiswww.case.edu/php/chet/readline/readline.html#SEC41
void rl_callback_handler_install (const char *prompt, rl_vcpfunc_t *lhandler)
  Set up the terminal for readline I/O and display the initial expanded
  value of prompt. Save the value of lhandler to use as a handler function
  to call when a complete line of input has been entered. The handler
  function receives the text of the line as an argument. As with readline(),
  the handler function should free the line when it it finished with it.
void rl_callback_read_char (void)
void rl_callback_sigcleanup (void)
void rl_callback_handler_remove (void)
]]

if string.tonumber then tonumber = string.tonumber end  -- 5.4

-------------------- private utility functions -------------------
local function warn(str) io.stderr:write(str,'\n') end
local function die(str) io.stderr:write(str,'\n') ;  os.exit(1) end
local function qw(s)  -- t = qw[[ foo  bar  baz ]]
    local t = {} ; for x in s:gmatch("%S+") do t[#t+1] = x end ; return t
end
local function deepcopy(object)  -- http://lua-users.org/wiki/CopyTable
    local lookup_table = {}
    local function _copy(object)
        if type(object) ~= "table" then
            return object
        elseif lookup_table[object] then
            return lookup_table[object]
        end
        local new_table = {}
        lookup_table[object] = new_table
        for index, value in pairs(object) do
            new_table[_copy(index)] = _copy(value)
        end
        return setmetatable(new_table, getmetatable(object))
    end
    return _copy(object)
end
local function sorted_keys(t)
	local a = {}
	for k,v in pairs(t) do a[#a+1] = k end
	table.sort(a)
	return  a
end
local function touch(fn)
    local f=io.open(fn,'r') -- or check if posix.stat(path) returns non-nil
    if f then
		f:close(); return true
	else
    	f=io.open(fn,'w')
    	if f then
			f:write(""); f:close(); return true
		else
			return false
		end
	end
end
local function homedir(user)
	if not user and os.getenv('HOME') then return os.getenv('HOME') end
	local P = nil
    pcall(function() P = require 'posix' ; end )
    if type(P) == 'table' then  -- we have posix
		if not user then user = P.getpid('euid') end
		return P.getpasswd(user, 'dir') or '/tmp'
	end
	warn('readline: HOME not set and luaposix not installed; using /tmp')
	return '/tmp/'
end
local function tilde_expand(filename)
    if string.match(filename, '^~') then
        local user = string.match(filename, '^~(%a+)/')
        local home = homedir(user)
        filename = string.gsub(filename, '^~%a*', home)
    end
    return filename
end


---------------- from Lua Programming Gems p. 331 ----------------
local require, table = require, table -- save the used globals
local aux, prv = {}, {} -- auxiliary & private C function tables
local initialise = require 'C-readline'
initialise(aux, prv, M) -- initialise the C lib with aux,prv & module tables

------------------------ public functions ----------------------

prv.using_history()
local Option = {   -- the default options
	auto_add   = true,
	completion = true,
	histfile   = '~/.rl_lua_history',
	ignoredups = true,
	keeplines  = 500,
	minlength  = 2,
}
local PreviousLine = ''

function M.read_history ()
	local histfile = tilde_expand( Option['histfile'] )
	return prv.read_history ( histfile )
end

M.read_history( Option['histfile'] )
local OldHistoryLength = prv.history_length()
-- print('OldHistoryLength='..tostring(OldHistoryLength))

------------------------ public functions ----------------------


function M.set_options ( tbl )
	if tbl == nil then return end
	if type(tbl) ~= 'table' then
		die('set_options: argument must be a table, not '..type(tbl))
	end
	local old_options = deepcopy(Option)
	for k,v in pairs(tbl) do
		if k == 'completion' then
			if type(v) ~= 'boolean' then
				die('set_options: completion must be boolean, not '..type(v))
			end
			prv.tabcompletion ( v )
			Option[k] = v
		elseif k == 'histfile' then
			if v ~= Option['histfile'] then
				if type(v) ~= 'string' then
					die('set_options: histfile must be string, not '..type(v))
				end
				Option[k] = v
				prv.clear_history()
				local rc = M.read_history( Option['histfile'] )  -- 1.2
				OldHistoryLength = prv.history_length()  -- 3.1
			end
		elseif k == 'keeplines' or k == 'minlength' then
			if type(v) ~= 'number' then
				die('set_options: '..k..' must be number, not '..type(v))
			end
			Option[k] = v
		elseif k == 'ignoredups' or k == 'auto_add' then
			if type(v) ~= 'boolean' then
				die('set_options: '..k..' must be boolean, not '..type(v))
			end
			Option[k] = v
		else
			die('set_options: unrecognised option '..tostring(k))
		end
	end
	return old_options
end

function M.readline ( prompt )
	prompt = prompt or ''
	if type(prompt) ~= 'string' then
		die('readline: prompt must be a string, not '..type(prompt))
	end
	local line = prv.readline ( prompt )   -- might be nil if EOF...
	if line == nil then return nil end -- 1.8
	if Option['completion'] then
		line = string.gsub(line, ' $', '')  -- 1.3, 2.0
	end
	if Option['auto_add'] and line and line~=''
	  and string.len(line)>=Option['minlength'] then
		if line ~= PreviousLine or not Option['ignoredups'] then
			prv.add_history(line)
			PreviousLine = line
		end
	end
	return line
end

function M.add_history ( str )
	if type(str) ~= 'string' then
		die('add_history: str must be a string, not '..type(str))
	end
	return prv.add_history ( str )
end

function M.save_history ( )
	if type(Option['histfile']) ~= 'string' then
		die('save_history: histfile must be a string, not '
		  .. type(Option['histfile']))
	end
	if Option['histfile'] == '' then return end
	local histfile = tilde_expand( Option['histfile'] )
	if type(Option['keeplines']) ~= 'number' then
		die('save_history: keeplines must be a number, not '
		  .. type(Option['keeplines']))
	end
	local n = prv.history_length()
	if n > OldHistoryLength then
		touch(histfile)
		local rc = prv.append_history(n-OldHistoryLength, histfile)
		if rc ~= 0 then warn('append_history: '..prv.strerror(rc)) end
		rc = prv.history_truncate_file ( histfile, Option['keeplines'] )
		if rc ~= 0 then warn('history_truncate_file: '..prv.strerror(rc)) end
		-- reset OldHistoryLength in case it's used again ... er: 3.1?
		-- OldHistoryLength = n   -- is this useful ?
	end
	return
end

--[[
20220420
https://tiswww.cwru.edu/php/chet/readline/history.html#SEC15

Function: int read_history (const char *filename)
    Add the contents of filename to the history list, a line at a 
    time. If filename is NULL, then read from `~/.history'. Returns 0
    if successful, or errno if not.

Function: int read_history_range (const char *filename, int from, int to)
    Read a range of lines from filename, adding them to the history 
    list. Start reading at line from and end at to. If from is zero, start
    at the beginning. If to is less than from, then read until the end of
    the file. If filename is NULL, then read from `~/.history'. Returns 
    0 if successful, or errno if not.

Function: int write_history (const char *filename)
    Write the current history to filename, overwriting filename if 
    necessary. If filename is NULL, then write the history list to
    `~/.history'. Returns 0 on success, or errno on a read or write error.

Function: int append_history (int nelements, const char *filename)
    Append the last nelements of the history list to filename. If filename 
    is NULL, then append to `~/.history'. Returns 0 on success, or errno
    on a read or write error.

Function: int history_truncate_file (const char *filename, int nlines)
    Truncate the history file filename, leaving only the last nlines 
    lines. If filename is NULL, then `~/.history' is truncated. Returns
    0 on success, or errno on failure.

Seems something's going wrong with n-OldHistoryLength ...
]]


function M.strerror ( errnum )
	return prv.strerror(tonumber(errnum))
end

-------------------- The Alternate Interface -------------------
function M.handler_install(prompt, linehandlerfunction)
	prompt = prompt or ''
	if type(prompt) ~= 'string' then
		die('handler_install: prompt must be a string, not '..type(prompt))
	end
	if type(linehandlerfunction) ~= 'function' then
		die('handler_install: linehandlerfunction must be a function, not '..
		  type(linehandlerfunction))
	end
	prv.callback_handler_install(prompt, linehandlerfunction)
end

M.read_char = prv.callback_read_char
M.handler_remove = prv.callback_handler_remove
-- M.sigcleanup will be nil unless C-readline.c was
-- compiled with RL_VERSION_MAJOR = 7  or greater
M.sigcleanup = prv.callback_sigcleanup

-------------------- Custom Completion ------------------------
M.set_readline_name               = prv.set_readline_name
M.set_complete_function           = prv.set_complete_function
M.set_default_complete_function   = prv.set_default_complete_function
M.set_completion_append_character = prv.set_completion_append_character

function M.set_complete_list(a)
	if type(a) ~= 'table' then
		die('set_complete_list: arg must be a table, not '..type(a))
	end
    local completer_function = function(text, from, to)
        local incomplete = string.sub(text, from, to)
        local matches = {}
        for i,v in ipairs(a) do
            if incomplete == string.sub(v, 1, #incomplete) then
                matches[1 + #matches] = v
            end
        end
        return matches
    end
    M.set_complete_function(completer_function)
end


return M

--[[

=pod

=head1 NAME

C<readline> - a simple interface to the I<readline> and I<history> libraries

=head1 SYNOPSIS

 local RL = require 'readline'
 RL.set_options{ keeplines=1000, histfile='~/.synopsis_history' }

 -- the Standard Interface
 local str = RL.readline('Please enter some filename: ')
 local save_options = RL.set_options{ completion=false }
 str = RL.readline('Please type a line which can include Tabs: ')
 RL.set_options(save_options)
 str = RL.readline('Now tab-filename-completion is working again: ')
 ...

 -- the Alternate Interface
 local poll = require 'posix.poll'.poll
 local line = nil
 local linehandler = function (str)
    line = str
    RL.handler_remove()
    RL.add_history(str)
 end
 RL.handler_install("prompt> ", linehandler)
 local fds = {[0] = {events={IN={true}}}}
 while true do
    poll(fds, -1)
    if fds[0].revents.IN then
       RL.read_char()  -- only if there's something to be read
    else
       -- do some useful background task
    end
    if line then break end
 end
 print("got line: " .. line)

 -- Custom Completion
 local reserved_words = {
   'and', 'assert', 'break', 'do', 'else', 'elseif', 'end', 'false', 
   'for', 'function', 'if', 'ipairs', 'local', 'nil', 'not', 'pairs', 
   'print', 'require', 'return', 'then', 'tonumber',  'tostring',
   'true', 'type', 'while',
 }
 RL.set_complete_list(reserved_words)
 line = RL.readline('now it expands lua reserved words: ')

 ...
 RL.save_history() ; os.exit()

=head1 DESCRIPTION

This Lua module offers a simple calling interface
to the GNU Readline/History Library.

The function I<readline()> is a wrapper, which invokes the GNU
I<readline>, adds the line to the end of the History List,
and then returns the line.
Usually you call I<save_history()> before the program exits,
so that the History List is saved to the I<histfile>.

Various options can be changed using the I<set_options{}> function.

The user can configure the GNU Readline (e.g. I<vi> or I<emacs> keystrokes ?)
with their individual I<~/.inputrc> file,
see the I<INITIALIZATION FILE> section of I<man readline>.

By default, the GNU I<readline> library dialogues with the user
by reading from I<stdin> and writing to I<stdout>;
This fits badly with applications that want to
use I<stdin> and I<stdout> to input and output data.
Therefore, this Lua module dialogues with the user on the controlling-terminal
of the process (typically I</dev/tty>) as returned by I<ctermid()>.

=head1 STANDARD INTERFACE

=head3 RL.set_options{ histfile='~/.myapp_history', keeplines=100 }

Returns the old options, so they can be restored later.
The I<auto_add> option controls whether the line entered will be
added to the History List,
The default options are:

 auto_add   = true,
 histfile   = '~/.rl_lua_history',
 keeplines  = 500,
 completion = true,
 ignoredups = true,
 minlength  = 2,

Lines shorter than the I<minlength> option will not be put on the History List.
Tilde expansion is performed on the I<histfile> option.
The I<histfile> option must be a string, so don't set it to I<nil>,
if you want to avoid reading or writing your History List to the filesystem,
set I<histfile> to the empty string.
If you want no history behaviour (Up or Down arrows etc.) at all, then set

 set_options{ histfile='', auto_add=false, }

=head3 RL.readline( prompt )

Displays the I<prompt> and returns the text of the line the user enters.
A blank line returns the empty string.
If EOF is encountered while reading a line, and the line is empty,
I<nil> is returned;
if an EOF is read with a non-empty line, it is treated as a newline.

If the I<auto_add> option is I<true> (which is the default),
the line the user enters will be added to the History List,
unless it's shorter than I<minlength>,
or it's the same as the previous line and the I<ignoredups> option is set.

=head3 RL.save_history()

Normally, you should call this function before your program exits.
It saves the lines the user has entered onto the end of the I<histfile> file.
Then if necessary it truncates lines off the beginning of the I<histfile>
to confine it to I<keeplines> long.

=head3 RL.add_history( line )

Adds the I<line> to the History List.
You'll only need this function if you want to assume complete control
over the strings that get added, in which case you:

 RL.set_options{ auto_add=false, }

and then after calling I<readline(prompt)>
you can process the I<line> as you wish
and call I<add_history(line)> if appropriate.

=head1 ALTERNATE INTERFACE

Some applications need to interleave keyboard I/O with file, device,
or window system I/O, by using a main loop to select() on various file
descriptors.
With the Alernate Interface, readline can be invoked as a 'callback'
function from an event loop.
The Alternate Interface does not add to the history file, so you will
probably want to call RL.add_history(s) explicitly

=head3 RL.handler_install( prompt, linehandlerfunction )

This function sets up the terminal, installs a linehandler function
that will receive the text of the line as an argument, and displays the
string prompt.   A typical linehandler function might be:

  linehandler = function (str)
     RL.add_history(str)
     RL.handler_remove()
     line = str   -- line is a global, or an upvalue
  end

=head3 RL.read_char()

Whenever an application determines that keyboard input is available, it
should call read_char(), which will read the next character from the
current input source. If that character completes the line, read_char
will invoke the linehandler function installed by handler_install to
process the line. Before calling the linehandler function, the terminal
settings are reset to the values they had before calling
handler_install. If the linehandler function returns, and the line
handler remains installed, the terminal settings are modified for
Readline's use again. EOF is indicated by calling the linehandler
handler with a nil line.
Interface.

=head3 RL.handler_remove()

Restore the terminal to its initial state and remove the line handler.
You may call this function from within the linehandler as well as
independently. If the linehandler function does not exit the program,
this function should be called before the program exits to reset the
terminal settings.

=head1 CUSTOM COMPLETION

=head3 RL.set_complete_list( array_of_strings )

This function sets up custom completion of an array of strings.
For example, the I<array_of_strings> might be the dictionary-words of a
language, or the reserved words of a programming language.

=head3 RL.set_complete_function( completer_function )

This is the lower-level function on which set_complete_list() is
based. Its argument is a function which takes three arguments: the text
of the line as it stands, and the indexes from and to, which delimit the
segment of the text (for example, the word) which is to be completed.
This syntax is the same as I<string.sub(text, from, to)>
The I<completer_function> must return an array of the possible completions.
For example, the I<completer_function> of set_complete_list() is:

  local completer_function = function(text, from, to)
     local incomplete = string.sub(text, from, to)
     local matches = {}
     for i,v in ipairs(array_of_strings) do
        if incomplete == string.sub(v, 1, #incomplete) then
           matches[1 + #matches] = v
        end
     end
     return matches
  end

but the completer_function can also have more complex behaviour. Because
it knows the contents of the line so far, it could ask for a date in
format B<18 Aug 2018> and offer three different completions for the three
different fields.
Or if the line so far seems to be in Esperanto it could offer completions
in Esperanto, and so on.

By default, after every completion readline appends a space to the
string, so you can start the next word. You can change this space to
another character by calling set_completion_append_character(s),
which sets the append_character to the first byte of the string B<s>.
For example this sets it to the empty string:

  RL.set_completion_append_character('')

It only makes sense to call I<set_completion_append_character> from within
a completer_function.
After the completer_function has executed, the readline library resets
the append_character to the default space.

Setting the append_character to C<','> or C<':'> or C<'.'> or C<'-'> may not
behave as you expect when trying to tab-complete the following word,
because I<readline> treats those characters as being part of a 'word',
not as a delimiter between words.

=head1 INSTALLATION

This module is available as a LuaRock in
http://luarocks.org/modules/peterbillam
so you should be able to install it with the command:

 $ su
 Password:
 # luarocks install readline

or:

 # luarocks install http://www.pjb.com.au/comp/lua/readline-2.2-0.rockspec

It depends on the I<readline> library and its header-files;
for example on Debian you may need:

 # aptitude install libreadline6 libreadline6-dev

or on Centos you may need:

 # yum install readline-devel

=head1 CHANGES


 20210127 2.9 fix version number again
 20210106 2.8 add set_readline_name() and fix version number
 20200801 2.7 add 5.4
 20180924 2.2 add set_completion_append_character 
 20180912 2.1 C code stack-bug fix in handler_calls_completion_callback
 20180910 2.0 add set_complete_list and set_complete_function
 20180901 1.9 add handler_install read_char and handler_remove
 20151020 1.8 readline() returns nil correctly on EOF
 20150422 1.7 works with lua5.3
 20140608 1.5 switch pod and doc over to using moonrocks
 20140519 1.4 installs as readline not Readline under luarocks 2.1.2
 20131031 1.3 readline erases final space if tab-completion is used
 20131020 1.2 set_options{histfile='~/d'} expands the tilde
 20130921 1.1 uses ctermid() (usually /dev/tty) to dialogue with the user
 20130918 1.0 first working version 

=head1 AUTHOR

Peter Billam, 
http://www.pjb.com.au/comp/contact.html

Alexander Adler, of the University of Frankfurt, contributed the
Alternate Interface functions.

=head1 SEE ALSO

=over 3

 man readline
 http://www.gnu.org/s/readline
 https://tiswww.case.edu/php/chet/readline/readline.html
 https://tiswww.case.edu/php/chet/readline/readline.html#SEC41
 https://tiswww.case.edu/php/chet/readline/readline.html#SEC45
 /usr/share/readline/inputrc
 ~/.inputrc
 http://lua-users.org/wiki/CompleteWithReadline
 http://luaposix.github.io/luaposix
 http://www.pjb.com.au
 http://www.pjb.com.au/comp/index.html#lua

=back

=cut
]]
