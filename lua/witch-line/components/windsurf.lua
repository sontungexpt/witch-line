local Id = require("witch-line.constant.id").Id

---@type DefaultComponent
local WindSurf = {
	id = Id["windsurf"],
	_plug_provided = true,
	static = {
		icon = {
			idle = "󰚩",
			error = "󱚡",
			completions = "󱜙",
			waiting = { "󱇷    ", "󱇷   ", "󱇷  ", "󱇷 ", "󱇷" },
			-- waiting = { "󰚩", "󱇷", "󰚩", "󱇷",  },
			unauthorized = "󱚟",
			disabled = "󱚧",
		},
		fps = 3, -- should be 3 - 5
	},
	context = {
		progress_idx = 0,
	},
	init = function(self, sid)
		vim.api.nvim_create_autocmd("InsertEnter", {
			once = true,
			callback = function()
				local ok, virtual_text = pcall(require, "codeium.virtual_text")
				if not ok then
					return true
				end
				local timer
				local refresh_component_graph = require("witch-line.core.handler").refresh_component_graph
				virtual_text.set_statusbar_refresh(function()
					if vim.bo.buftype ~= "prompt" and require("codeium.virtual_text").status().state == "waiting" then
						timer = timer or (vim.uv or vim.loop).new_timer()
						local static = self.static
						--- @cast static {icon: table, fps: number}
						if timer then
							timer:start(
								0,
								math.floor(1000 / static.fps),
								vim.schedule_wrap(function()
									refresh_component_graph(self)
								end)
							)
						end
						return
					elseif timer then
						timer:stop()
					end
					refresh_component_graph(self)
				end)

				-- Update the component immediately
				refresh_component_graph(self)
			end,
		})
	end,

	update = function(self, sid)
		local icon = self.static.icon
		local ctx = self.context
		--- @cast ctx {status : string, progress_idx: integer, is_enabled: fun(): boolean}

		local server_status = require("codeium.api").check_status()
		local api_key_error = server_status.api_key_error
		if api_key_error ~= nil then
			if api_key_error:find("Auth") then
				return icon.unauthorized
			end
			return icon.error
		end

		local status = require("codeium.virtual_text").status()
		if status.state == "waiting" then
			local progress_idx = ctx.progress_idx
			progress_idx = progress_idx < #icon.waiting and progress_idx + 1 or 1
			ctx.progress_idx = progress_idx
			return icon.waiting[progress_idx]
		elseif status.state == "idle" then
			-- Output was cleared, for example when leaving insert mode
			ctx.progress_idx = 0
			return icon.idle
		elseif status.state == "completions" and status.total > 0 then
			ctx.progress_idx = 0
			return icon.completions .. " " .. string.format("%d/%d", status.current, status.total)
		end
		return icon.disabled
	end,
}

return WindSurf
