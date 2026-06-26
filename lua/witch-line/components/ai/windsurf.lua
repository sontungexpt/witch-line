local progress_idx = 0

---@type DefaultComponent
local WindSurf = {
	id = "windsurf",
	_plug_provided = true,
	static = {
		fps = 3,
		icons = {
			idle = "󰚩",
			error = "󱚡",
			completions = "󱜙",
			waiting = { "󱇷    ", "󱇷   ", "󱇷  ", "󱇷 ", "󱇷" },
			unauthorized = "󱚟",
			disabled = "󱚧",
		},
	},
	init = function(self, _)
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
					if
						vim.bo.buftype ~= "prompt" and require("codeium.virtual_text").status().state == "waiting"
					then
						timer = timer or (vim.uv or vim.loop).new_timer()
						if timer then
							timer:start(
								0,
								math.floor(1000 / self.static.fps),
								vim.schedule_wrap(function()
									refresh_component_graph(self, true)
								end)
							)
						end
						return
					elseif timer then
						timer:stop()
					end
					refresh_component_graph(self)
				end)

				refresh_component_graph(self)
			end,
		})
	end,

	update = function(self, _)
		local icon = self.static.icons

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
			progress_idx = progress_idx < #icon.waiting and progress_idx + 1 or 1
			return icon.waiting[progress_idx]
		elseif status.state == "idle" then
			progress_idx = 0
			return icon.idle
		elseif status.state == "completions" and status.total > 0 then
			progress_idx = 0
			return icon.completions .. " " .. string.format("%d/%d", status.current, status.total)
		end
		return icon.disabled
	end,
}

local neocodeium_progress_idx = 0
local neocodeium_timer
local neocodeium_timer_running = false

---@type DefaultComponent
local Neocodeium = {
	id = "windsurf.neocodeium",
	_plug_provided = true,
	events = "User NeoCodeiumDisabled, NeoCodeiumBufDisabled, NeoCodeiumEnabled, NeoCodeiumBufEnabled, NeoCodeiumServerConnected, NeoCodeiumServerStopped, NeoCodeiumLabelUpdated",
	static = {
		fps = 3,
		icons = {
			idle = "󰚩",
			error = "󱚡",
			completions = "󱜙",
			waiting = { "󱇷    ", "󱇷   ", "󱇷  ", "󱇷 ", "󱇷" },
			unauthorized = "󱚟",
			disabled = "󱚧",
		},
	},
	update = function(self, ctx)
		local icon = self.static.icons
		local timer = neocodeium_timer
		local event = ctx and ctx.session:get("EventInfo")
		event = event and event[self.id]

		if event then
			if
				event.match == "NeoCodeiumLabelUpdated"
				and vim.bo.buftype ~= "prompt"
				and event.data == " * "
			then
				if not neocodeium_timer_running then
					timer = timer or (vim.uv or vim.loop).new_timer()
					if timer then
						timer:start(
							0,
							math.floor(1000 / self.static.fps),
							vim.schedule_wrap(function()
								require("witch-line.core.handler").refresh_component_graph(self, true)
							end)
						)
						neocodeium_timer_running = true
						neocodeium_timer = timer
					end
				end
			elseif timer then
				timer:stop()
				neocodeium_timer_running = false
			end
		end

		local status, server_status = require("neocodeium").get_status()
		local result = icon.idle
		if server_status ~= 0 then
			result = icon.disabled
		elseif status ~= 0 then
			result = icon.disabled
		elseif neocodeium_timer_running then
			neocodeium_progress_idx = neocodeium_progress_idx < #icon.waiting and neocodeium_progress_idx + 1 or 1
			return icon.waiting[neocodeium_progress_idx]
		elseif event and event.match == "NeoCodeiumLabelUpdated" then
			if event.data == " 0 " or event.data == "   " then
				result = icon.idle
			else
				result = icon.completions .. " " .. event.data:match("^%s*(.-)%s*$")
			end
		end
		neocodeium_progress_idx = 0
		return result
	end,
}

return {
	windsurf = WindSurf,
	neocodeium = Neocodeium,
}
