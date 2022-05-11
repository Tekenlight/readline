#! /usr/local/bin/lua
local RL = require 'readline'
local poll = require 'posix.poll'.poll
-- local TC = require 'testcases'
-- luarocks install http://pjb.com.au/comp/lua/testcases-0.1-0.rockspec

--------------------------- infrastructure -----------------------
local eps = .000000001
function equal(x, y)  -- unused here
    if #x ~= #y then return false end
    local i; for i in pairs(x) do
        if math.abs(x[i]-y[i]) > eps then return false end
    end
    return true
end
-- use Test::Simple tests => 6;
local Test = 73 ; local i_test = 0; local Failed = 0;
function ok(b,s)
    i_test = i_test + 1
    if b then
        io.write('ok '..i_test..' - '..s.."\n")
		return true
    else
        io.write('not ok '..i_test..' - '..s.."\n")
        Failed = Failed + 1
		return false
    end
end

local function qw(s)  -- t = qw([[ foo  bar  baz ]])
    local t = {}
	for x in s:gmatch("([-%s]+)") do t[#t+1] = x end
	return t
end

local function uname_minus_s()
    local pipe = assert(io.popen('uname -s'))
    local uname_output = pipe:read('*all')
    pipe:close()
    return string.gsub(uname_output, '%s$', '')
end

-- strict.lua    checks uses of undeclared global variables
-- All global variables must be 'declared' through a regular assignment
-- (even assigning nil will do) in a main chunk before being used
-- anywhere or assigned to inside a function.
local mt = getmetatable(_G)
if mt == nil then
  mt = {}
  setmetatable(_G, mt)
end
mt.__declared = {}
mt.__newindex = function (t, n, v)
  if not mt.__declared[n] then
    local w = debug.getinfo(2, "S").what
    if w ~= "main" and w ~= "C" then
      error("assign to undeclared variable '"..n.."'", 2)
    end
    mt.__declared[n] = true
  end
  rawset(t, n, v)
end
mt.__index = function (t, n)
  if not mt.__declared[n] and debug.getinfo(2, "S").what ~= "C" then
    error("variable '"..n.."' is not declared", 2)
  end
  return rawget(t, n)
end

----------------------- here we go... -------------------------

print('Testing readline.lua '..RL.Version..', '..RL.VersionDate..
 ' on '..uname_minus_s())

if not ok(type(RL) == 'table', 'type of RL is table') then
	print('type was '..type(RL))
end

RL.set_completion_append_character('')
RL.set_completion_append_character(' ')
RL.set_completion_append_character('X')

-- for k,v in pairs(RL) do print(k,tostring(v)) end
local filename = '/tmp/test_rl_history'
os.remove(filename)
RL.set_options{histfile=filename , ignoredups=false}

print('About to test the Alternative Interface ...')
local s0 = nil
RL.handler_install("Tab-completion should work: ", function(s)
	s0 = s
	RL.handler_remove()
end)
local fds = {[0] = {events={IN={true}}}}
while true do
    poll(fds, -1)
    if fds[0].revents.IN then -- read only if there's something to be read
        RL.read_char()
    else
        -- do some useful background task
    end
    if s0 then break end   -- don't add to the history this time...
end

print('About to test the standard interface ...')
print('Please make all answers longer than two characters !')
local s1 = RL.readline('Please enter something: ')
if not ok(type(s1)=='string', "readline returned "..s1) then
	print('xc='..tostring(xc)..' xv='..tostring(xv))
end
local s2 = RL.readline('this time Up-arrow should work: ')
local s3 = RL.readline('enter a filename and test Tab-completion: ')
local save = RL.set_options{completion=false}
local s4 = RL.readline('now Tab-completion should be disabled: ')
RL.set_options(save)
local s5 = RL.readline('now it should be re-enabled :-) ')
RL.set_options{auto_add=false}
local s6 = RL.readline('this answer should not get added into the history: ')
RL.set_options(save)
local s7 = RL.readline('now it should be re-enabled :-) ')

print('About to test the Alternative Interface again ...')
line = nil
local linehandler = function(s)
    RL.handler_remove()
    RL.add_history(s)
    line = s
end
RL.handler_install("Please enter something: ", linehandler)
fds = {[0] = {events={IN={true}}}}
while true do
    poll(fds, -1)
    if fds[0].revents.IN then -- read only if there's something to be read
        RL.read_char()
    else
        -- do some useful background task
    end
    if line then s8 = line ; break end
end

local reserved_words = {
  'and', 'assert', 'break', 'do', 'else', 'elseif', 'end',
  'false', 'for', 'function', 'if', 'ipairs(',
  'io.flush(', 'io.input(', 'io.lines(', 'io.open(', 'io.output(',
  'io.popen(', 'io.read(', 'io.seek(', 'io.setvbuf(', 'io.stderr',
  'io.stdin', 'io.stdout', 'io.tmpfile(', 'io.write(',
  'local',
  'math.asin(', 'math.ceil(', 'math.cos(', 'math.deg(', 'math.floor(',
  'math.huge(', 'math.max(', 'math.maxinteger(', 'math.mod(', 'math.rad(',
  'math.random(', 'math.randomseed(', 'math.sin(', 'math.tan(',
  'math.tointeger(', 'math.type(', 'math.ult(',
  'nil', 'not', 'print', 'require', 'return',
  'os.clock(', 'os.date(', 'os.difftime(', 'os.execute(', 'os.exit(',
  'os.getenv(', 'os.remove(', 'os.rename(', 'os.time(',
  'string.byte(', 'string.char(', 'string.dump(', 'string.find(',
  'string.format(', 'string.gmatch(', 'string.gsub(', 'string.len(',
  'string.lower(', 'string.match(', 'string.pack(', 'string.rep(',
  'string.sub(', 'string.unpack(', 'string.unpack(', 'string.upper(',
  'table.concat(', 'table.insert(', 'table.move(', 'table.pack(',
  'table.remove(', 'table.sort(', 'table.unpack(',
  'then', 'tostring(', 'tonumber(', 'true', 'type', 'while', 'pairs(', 'print',
}
RL.set_complete_list(reserved_words)
local s9 = RL.readline('now it expands lua reserved words: ')

line = nil
RL.handler_install("the same but with the Alternate Interface: ", linehandler)
-- fds = {[0] = {events={IN={true}}}}
-- RL.set_complete_list(reserved_words)
while true do
    poll(fds, -1)
    if fds[0].revents.IN then -- read only if there's something to be read
        RL.read_char()
    else
        -- do some useful background task
    end
    if line then sA = line ; break end
end
-- print (sA)

-- print(type(TC.empty_the_stack))
--[[
local comp_func = function ()
	TC.empty_the_stack()
	return {'gloop'}
end
RL.set_complete_function(comp_func)
local sB = RL.readline("now the complete_function empties the stack: ")
local reg = debug.getregistry()
for k,v in pairs(reg) do print(k,v) end

comp_func = function ()
	TC.dump_the_stack('dummy-string', nil, 42)
	return {'gleep'}
end
RL.set_complete_function(comp_func)
local sC = RL.readline("now the complete_function dumps the stack: ")
]]

comp_func_2 = function ()
	RL.set_completion_append_character('')
	return {'glurp'}
end
RL.set_complete_function(comp_func_2)
local sD = RL.readline("now the completion_append_character is \\0: ")

comp_func_3 = function ()
	return {'glork'}
end
RL.set_complete_function(comp_func_3)
local sD = RL.readline("the completion_append_character is ' ' again: ")

RL.save_history()

print('Now checking the saved histfile:')
local F = assert(io.open(filename))
local lines = {}
for line in F:lines() do lines[#lines+1] = line end
F:close()
-- os.remove(filename)
if not ok(lines[1] == s1, 'line 1 was '..s1) then
	print('lines[1]='..tostring(lines[1])..' s1='..tostring(s1))
end
if not ok(lines[2] == s2, 'line 2 was '..s2) then
	print('lines[2]='..tostring(lines[2])..' s2='..tostring(s2))
end
if not ok(lines[3] == s3, 'line 3 was '..s3) then
	print('lines[3]='..tostring(lines[3])..' s3='..tostring(s3))
end
if not ok(lines[4] == s4, 'line 4 was '..s4) then
	print('lines[4]='..tostring(lines[4])..' s4='..tostring(s4))
end
if not ok(lines[5] == s5, 'line 5 was '..s5) then
	print('lines[5]='..tostring(lines[5])..' s5='..tostring(s5))
end
if not ok(lines[6] == s7, 'line 6 was '..s7) then
	print('lines[6]='..tostring(lines[6])..' s7='..tostring(s7))
end
if not ok(lines[7] == s8, 'line 7 was '..s8) then
	print('lines[7]='..tostring(lines[7])..' s8='..tostring(s8))
end
if not ok(lines[8] == s9, 'line 8 was '..s9) then
	print('lines[8]="'..tostring(lines[8])..'" s9="'..tostring(s9)..'"')
end
if not ok(lines[9] == sA, 'line 9 was '..sA) then
	print('lines[9]="'..tostring(lines[9])..'" sA="'..tostring(sA)..'"')
end
--[[
if not ok(lines[10] == sB, 'line 10 was '..sB) then
	print('lines[10]="'..tostring(lines[10])..'" sB="'..tostring(sB)..'"')
end
if not ok(lines[11] == sC, 'line 11 was '..sC) then
	print('lines[11]="'..tostring(lines[11])..'" sC="'..tostring(sC)..'"')
end
]]
if Failed == 0 then
	print('Passed all '..i_test..' tests :-)')
else
	print('Failed '..Failed..' tests out of '..i_test)
end


os.exit()
