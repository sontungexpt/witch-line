local api = vim.api
local M = {}
local FALLBACK_KEY = "\0fallback\0"

local commands = {
	clear_cache = function()
		require("witch-line.cache").clear()
	end,

	inspect = {
		cache_data = function()
			require("witch-line.cache").inspect()
		end,
		event_store = function()
			require("witch-line.core.manager.event").inspect()
		end,
		comp_manager = {
			comps = function()
				require("witch-line.core.manager").inspect("comps")
			end,
			dep_store = function()
				require("witch-line.core.manager").inspect("dep_store")
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
			flexible_priority_sorted = function()
				require("witch-line.core.statusline").inspect("flexible_priority_sorted")
			end,
			values = function()
				require("witch-line.core.statusline").inspect("statusline")
			end,
			[FALLBACK_KEY] = function()
				require("witch-line.core.statusline").inspect("statusline")
			end,
		},
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
		if key ~= FALLBACK_KEY and key:find("^" .. vim.pesc(arg_lead)) then
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
	elseif type(work) == "table" then
		local fallback = work[FALLBACK_KEY]
		if type(fallback) == "function" then
			fallback(arg, a)
		else
			require("witch-line.utils.notifier").error("WitchLine: Incomplete command. Subcommand required.")
		end
	end
end, {
	nargs = "*",
	complete = function(ArgLead, CmdLine, CursorPos)
		return get_trie_completions(ArgLead, CmdLine, CursorPos)
	end,
})
return M
