#!/usr/bin/env lua
local unistd = require('posix.unistd')
local wait = require('posix.sys.wait')
local stdlib = require('posix.stdlib')
local utsname = require('posix.sys.utsname')


local debug = false


if arg[1] == '-h' or arg[1] == '--help' then
	print("bunsh: the bun shell")
	print("Options:")
	print("  -h, --help\t\tShow this screen and exit")
	print("  -d, --debug\t\tPrint debug information after each command")
	os.exit(0)
elseif arg[1] == '-d' or arg[1] == '--debug' then
	debug= true
end


local environ = {}
local aliases = {}


-- builtins
function exec(command, args)
	print(unistd.execp(command, args))
end

function echo(command, args)
	if not command then print() return end
	local str = command
	for argument = 1, #args do
		str = str.." "..args[argument]
	end
	print(str)
end

function exit(command)
	local icom = tonumber(command)
	if not icom then os.exit(0) else os.exit(icom) end
end


function alias(command, args)
	if not command then
		for k, v in pairs(aliases) do print(k.."="..v) end
	else
		local str = args[1]
		for i = 2, #args do str = str.." "..args[i] end
		aliases[command] = str
	end
end


function env(command, args)
	if not command then
		for k, v in pairs(stdlib.getenv()) do
			print(k.."="..v)
		end
	else
		local pid = unistd.fork()
		if pid == 0 then
			unistd.execp(command, args)
		else
			wait.wait(pid)
		end
	end
end


function cd(command)
	local chd = command
	if not chd then chd = environ["HOME"] end
	local a, b, c = unistd.chdir(chd)
	if b then print(b) else stdlib.setenv("PWD", unistd.getcwd(), true) end
end
-- builtins dict
local builtins = {
	["exec"] = exec,
	["echo"] = echo,
	["exit"] = exit,
	["alias"]= alias,
	["env"]  = env,
	["cd"]   = cd
}


-- input parsing
function getcommand(input)
	local index = input:match('() ')
	return input:sub(1, index - 1)
end


function getargs(input)
	local space = input:match('() ')
	local argstr = input:sub(space + 1)

	local retargs = {}

	while space do
		space = argstr:match('() ')
		if not space then
			table.insert(retargs, argstr)
			break
		end
		table.insert(retargs, argstr:sub(1, space - 1))
		argstr = argstr:sub(space + 1)
	end

	return retargs
end


-- return the index of the first pipe in args
function findpipe(args)
	for i = 1, #args do
		if args[i] == '|' then return i end
	end
end


-- get user / home directory info
local passwd = io.open('/etc/passwd')
local euid = unistd.geteuid()

for line in passwd:lines() do
	local split = {}
	for segment in line:gmatch('([^:]+)') do
		table.insert(split, segment)
	end
	if tonumber(split[3]) == euid then
		environ["HOME"] = split[6]
		environ["USER"] = split[1]
		environ["PWD"]  = environ["HOME"]
	end
end
passwd:close()


local host = io.open("/etc/hostname")
if host then
	environ["HOST"] = host:read()
	host:close()
else
	environ["HOST"] = utsname.uname().nodename
end

for k, v in pairs(environ) do stdlib.setenv(k, v, true) end
unistd.chdir(environ["PWD"])

local cmd_exit = 0

while true do
	local cwd = unistd.getcwd()
	if cwd:sub(1, #environ["HOME"]) == environ["HOME"] then
		cwd = "~"..cwd:sub(#environ["HOME"] + 1)
	end
	local prompt = "\27[32m"..environ["USER"].."\27[0m".."@"..environ["HOST"].." ".."\27[32m"..cwd.."\27[0m"
	if cmd_exit ~= 0 then prompt = prompt..' \27[31m['..cmd_exit..']\27[0m' end
	prompt = prompt..' > '
	io.write(prompt)
	local input = io.read()

	-- break on EOF
	if not input then break end

	local command = ""
	local args = {}

	-- get command and arguments
	local space_index = input:match('^.*() ')
	if not space_index then
		command = input
	else
		command = getcommand(input)
		args = getargs(input)
	end

	-- handle builtin commands
	if builtins[command] then
		local new_args = {}
		for i = 2, #args do table.insert(new_args, args[i]) end
		builtins[command](args[1], new_args)
		goto continue
	-- handle aliased commands
	elseif aliases[command] then
		local alias = aliases[command]
		local space = alias:match('() ')
		-- alias has no args
		if not space then
			command = alias
		else
			-- preserve previous arguments
			local arg_table = args

			command = getcommand(alias)
			args = getargs(alias)
	
			-- append previous arguments
			for i = 1, #arg_table do
				table.insert(args, arg_table[i])
			end
		end
	end

	-- convert a command with pipes into multiple commands
	--parse_pipe(command, args)

---[[
	-- execute command
	local pid = unistd.fork()
	if pid == 0 then
		local a, b, c = unistd.execp(command, args)
		print(b)
		os.exit(0)
	else
		cmd_exit = select(3, wait.wait(pid))
	end
--]]
	
	if debug then
		print("command: "..command)
		print("args:")
		for k, v in pairs(args) do
			print(k..". "..v)
		end
	end
	::continue::
end

