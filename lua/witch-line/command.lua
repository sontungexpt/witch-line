local api = vim.api
local M = {}

local commands = {
	uncached = function()
		require("witch-line.cache").clear()
	end,

	inspect = {
		cache_data = function(...)
			require("witch-line.cache").inspect()
		end,
		comp_manager = {
			comps = function()
				require("witch-line.core.CompManager").inspect("comps")
			end,
			dep_store = function()
				require("witch-line.core.CompManager").inspect("dep_store")
			end,
		},
		highlight = {
			rgb24bit = function()
				require("witch-line.core.highlight").inspect("rgb24bit")
			end,
			styles = function()
				require("witch-line.core.highlight").inspect("styles")
			end,
		},
		statusline = {
			values = function()
				require("witch-line.core.statusline").inspect()
			end,
			frozens = function()
				require("witch-line.core.statusline").inspect("frozens")
			end,
			flexible_priority_sorted = function()
				require("witch-line.core.statusline").inspect("flexible_priority_sorted")
			end,
			idx_hl_map = function()
				require("witch-line.core.statusline").inspect("idx_hl_map")
			end,
		},
		event_store = function()
			require("witch-line.core.handler.event").inspect()
		end
	},
}

--- Retrieves completions for a given command line.
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

	local arg = args[1]
	local work = commands[arg]
	for i = 2, #args do
		arg = args[i]
		work = work[arg]
	end

	if type(work) == "function" then
		work(arg, a)
	end
end, {
	nargs = "*",
	complete = function(ArgLead, CmdLine, CursorPos)
		return get_trie_completions(ArgLead, CmdLine, CursorPos)
	end,
})
return M
