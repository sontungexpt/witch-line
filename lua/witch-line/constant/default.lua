---@type CombinedComponent
return {
	"mode",
	{
		[0] = "file.name",
		padding = { left = 1, right = 0 },
	},
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

	{
		id = "test",
		win_individual = true,
		lazy = false,
		update = function(self, sid)
			local filetype = vim.bo.filetype
			if filetype == "NvimTree" then
				return "nvim_tree"
			end
			return "test"
		end,
	},
}
