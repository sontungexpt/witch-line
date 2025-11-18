local M = {}

--- Module
local Manager = require("witch-line.core.manager")
local Cache = require("witch-line.cache")
local Statusline = require("witch-line.core.statusline")
local Event = require("witch-line.core.manager.event")
local Timer = require("witch-line.core.manager.timer")
local Highlight = require("witch-line.core.highlight")

local FALLBACK_KEY = "\0fallback\0"

local COMMANDS = {
	clear_cache = function()
		Cache.clear(true)
	end,

	inspect = {
		cache_data = Cache.inspect,
		event_store = Event.inspect,
		timer_store = Timer.inspect,
		comp_manager = {
			comps = Manager.inspect,
			dep_store = Manager.inspect,
		},
		highlight = {
			rgb24bit = Highlight.inspect,
			styles = Highlight.inspect,
		},
		statusline = Statusline.inspect,
	},
}

--- Retrieves completions for a given command line.
---@diagnostic disable-next-line: unused-local
local function get_trie_completions(arg_lead, cmd_line, cursor_pos)
	local args = vim.split(cmd_line, "%s+")

	table.remove(args, 1) -- Remove the command name

	---@type table|function
	local node = COMMANDS
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
	table.sort(completions)
	return completions
end

vim.api.nvim_create_user_command("WitchLine", function(a)
	local args = a.fargs
	if #args < 1 then
		return
	end

	local arg = args[1]
	local work = COMMANDS[arg]
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
	complete = get_trie_completions,
	-- complete = function(ArgLead, CmdLine, CursorPos)
	-- 	return get_trie_completions(ArgLead, CmdLine, CursorPos)
	-- end,
})
return M
