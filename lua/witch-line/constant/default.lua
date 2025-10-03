---@type CombinedComponent
return {
	"mode",
	"file.name",
	"file.icon",
	"file.modifier",

	"git.branch",
	"git.diff.added",
	"git.diff.removed",
	"git.diff.modified",

	"%=",


	"lsp.clients",
	"copilot",

	"diagnostic.error",
	"diagnostic.warn",
	"diagnostic.info",


	"indent",
	"encoding",
	"cursor.pos",
	"cursor.progress",

	-- 	{
	-- 		name = "git-branch",
	-- 		user_event = "GitSignsUpdate",
	-- 		configs = {
	-- 			icon = "",
	-- 		},
	-- 		styles = { fg = colors.pink },
	-- 		update = function(configs, context)
	-- 			local branch = ""
	-- 			local git_dir = fn.finddir(".git", ".;")
	-- 			if git_dir ~= "" then
	-- 				local head_file = io.open(git_dir .. "/HEAD", "r")
	-- 				if head_file then
	-- 					local content = head_file:read("*all")
	-- 					head_file:close()
	-- 					-- branch name  or commit hash
	-- 					branch = content:match("ref: refs/heads/(.-)%s*$") or content:sub(1, 7) or ""
	-- 				end
	-- 			end
	-- 			return branch ~= "" and configs.icon .. " " .. branch or ""
	-- 		end,
	-- 		condition = function()
	-- 			return api.nvim_buf_get_option(0, "buflisted")
	-- 		end,
	-- 	},
	-- 	{
	-- 		name = "git-diff",
	-- 		event = "BufWritePost",
	-- 		user_event = "GitSignsUpdate",
	-- 		configs = {
	-- 			added = "",
	-- 			changed = "",
	-- 			removed = "",
	-- 		},
	-- 		{
	-- 			styles = { fg = "DiffAdd" },
	-- 			update = function(configs)
	-- 				local git_status = vim.b.gitsigns_status_dict
	-- 				return git_status.added and git_status.added > 0 and configs.added .. " " .. git_status.added
	-- 					or ""
	-- 			end,
	-- 		},
	-- 		{
	-- 			styles = { fg = "DiffChange" },
	-- 			update = function(configs)
	-- 				local git_status = vim.b.gitsigns_status_dict
	-- 				return git_status.changed
	-- 						and git_status.changed > 0
	-- 						and configs.changed .. " " .. git_status.changed
	-- 					or ""
	-- 			end,
	-- 		},
	-- 		{
	-- 			styles = { fg = "DiffDelete" },
	-- 			update = function(configs)
	-- 				local git_status = vim.b.gitsigns_status_dict
	-- 				return git_status.removed
	-- 						and git_status.removed > 0
	-- 						and configs.removed .. " " .. git_status.removed
	-- 					or ""
	-- 			end,
	-- 		},
	-- 		condition = function()
	-- 			return vim.b.gitsigns_status_dict ~= nil and vim.o.columns > 70
	-- 		end,
	-- 	},
	-- },

	-- "%=",
	-- {
	-- 	styles = {
	-- 		fg = "DiagnosticHint",
	-- 	},
	-- 	update = function(configs)
	-- 		local count = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.HINT })
	-- 		return count > 0 and configs.HINT .. " " .. count or ""
	-- 	end,
	-- },

	--
}
