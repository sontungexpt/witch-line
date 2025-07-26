local M = {}

M.setup = function(user_configs)
	local uv = vim.uv or vim.loop
	local api = vim.api
	local locked = true
	local CacheMod = require("witch-line.cache")

	local cache_mods = {
		"witch-line.core.handler",
		"witch-line.core.statusline",
		"witch-line.core.CompManager",
		"witch-line.utils.highlight",
	}

	-- CacheMod.read_async(function(data)
	-- 	error(vim.inspect(data or nil))
	-- 	locked = false

	-- 	for _, mod in ipairs(cache_mods) do
	-- 		require(mod).load_cache(data)
	-- 	end

	-- 	-- if CacheMod.has_cached() then
	-- 	-- 	-- error(vim.inspect(data or nil))
	-- 	-- 	-- error(vim.inspect(data or nil))
	-- 	-- end
	-- end)
	local struct = CacheMod.read()
	for _, mod in ipairs(cache_mods) do
		require(mod).load_cache()
	end

	local configs = require("witch-line.config").set_user_config(user_configs)
	vim.api.nvim_create_autocmd("VimLeavePre", {
		callback = function()
			-- if CacheMod.has_cached() then
			-- 	return
			-- end
			for _, mod in ipairs(cache_mods) do
				require(mod).cache()
			end
			CacheMod.save()
		end,
	})

	-- local timer = uv.new_timer()
	-- if timer then
	-- 	timer:start(
	-- 		0,
	-- 		100,
	-- 		vim.schedule_wrap(function()
	-- 			if not locked then
	-- 				require("witch-line.core.handler").setup(configs)
	-- 				timer:stop()
	-- 				timer:close()
	-- 				timer = nil
	-- 			end
	-- 		end)
	-- 	)
	-- end

	require("witch-line.core.handler").setup(configs)

	local options = {
		uncached = function()
			CacheMod.clear()
		end,

		inspect = {
			cache = function(...)
				return CacheMod.get()
			end,
			comps = function(...)
				require("witch-line.core.CompManager").inspect(...)
			end,
		},
	}

	local function get_node(words)
		local node = options

		for _, word in ipairs(words) do
			node = node[word]
			if not node then
				return {}
			end
		end

		return node
	end

	local function get_trie_completions(arg_lead, cmd_line, cursor_pos)
		local args = vim.split(cmd_line, "%s+")
		table.remove(args, 1) -- Remove the command name

		if cmd_line:sub(#cmd_line, #cmd_line) ~= "" then
			table.insert(args, "")
		end

		local node = get_node(vim.list_slice(args, 1, #args - 1))

		if type(node) ~= "table" then
			return {}
		end

		local completions = {}
		for key, _ in pairs(node) do
			if key:find("^" .. vim.pesc(arg_lead)) then
				table.insert(completions, key)
			end
		end
		return completions
	end

	api.nvim_create_user_command("WitchLine", function(a)
		local args = a.fargs
		if #args < 1 then
			return
		end

		local work = options[args[1]]
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
end

return M
