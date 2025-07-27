local api = vim.api
local M = {}

local CacheMod = require("witch-line.cache")

local commands = {
	uncached = function()
		CacheMod.clear()
	end,

	inspect = {
		cache = function(...)
			return CacheMod.get()
		end,
		comps = function()
			require("witch-line.core.CompManager").inspect("comps")
		end,
		dep_store = function()
			require("witch-line.core.CompManager").inspect("dep_store")
		end,
		highlight = function()
			require("witch-line.utils.highlight").inspect()
		end,
		statusline = function()
			require("witch-line.core.statusline").inspect()
		end,
	},
}

---@diagnostic disable-next-line: unused-local
local function get_trie_completions(arg_lead, cmd_line, cursor_pos)
	local args = vim.split(cmd_line, "%s+")

	table.remove(args, 1) -- Remove the command name

	---@type table|function
	local node = commands
	for i = 1, #args - 1 do
		node = node[args[i]]
		if not node then
			return {}
		end
	end

	if type(node) ~= "table" then
		return {}
	end

	local completions = {}
	for key, _ in pairs(node) do
		if key:find("^" .. vim.pesc(arg_lead)) then
			completions[#completions + 1] = key
		end
	end
	return completions
end

api.nvim_create_user_command("WitchLine", function(a)
	local args = a.fargs
	if #args < 1 then
		return
	end

	local work = commands[args[1]]
	for i = 2, #args do
		work = work[args[i]]
	end

	if type(work) == "function" then
		work(a)
	end
end, {
	nargs = "*",
	complete = function(ArgLead, CmdLine, CursorPos)
		return get_trie_completions(ArgLead, CmdLine, CursorPos)
	end,
})
return M
