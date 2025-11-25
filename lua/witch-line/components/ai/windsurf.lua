local Id = require("witch-line.constant.id").Id

local SHARED_ICON = {
	idle = "󰚩",
	error = "󱚡",
	completions = "󱜙",
	waiting = { "󱇷    ", "󱇷   ", "󱇷  ", "󱇷 ", "󱇷" },
	-- waiting = { "󰚩", "󱇷", "󰚩", "󱇷",  },
	unauthorized = "󱚟",
	disabled = "󱚧",
}

---@type DefaultComponent
local WindSurf = {
	id = Id["windsurf"],
	_plug_provided = true,
	static = {
		icon = SHARED_ICON,
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
					if
						vim.bo.buftype ~= "prompt" and require("codeium.virtual_text").status().state == "waiting"
					then
						timer = timer or (vim.uv or vim.loop).new_timer()
						local static = self.static
						--- @cast static {icon: table, fps: number}
						if timer then
							timer:start(
								0,
								math.floor(1000 / static.fps),
								vim.schedule_wrap(function()
									-- need to render immediately for animation
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

				-- Update the component immediately
				refresh_component_graph(self)
			end,
		})
	end,

	update = function(self, sid)
		local icon = self.static.icon
		local ctx = self.context
		--- @cast ctx { progress_idx: integer }

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

---@type DefaultComponent
local Neocodeium = {
	id = Id["windsurf.neocodeium"],
	_plug_provided = true,
	-- NeoCodeiumServerConnected, NeoCodeiumServerStopped
	events = "User NeoCodeiumDisabled, NeoCodeiumBufDisabled, NeoCodeiumEnabled, NeoCodeiumBufEnabled, NeoCodeiumServerConnected, NeoCodeiumServerStopped, NeoCodeiumLabelUpdated",
	static = {
		icon = SHARED_ICON,
		fps = 3, -- should be 3 - 5
	},
	context = {
		progress_idx = 0,
		timer = nil,
	},
	update = function(self, sid)
		local ctx, static = self.context, self.static

		--- @cast static {icon: table, fps: number}
		--- @cast ctx { timer?: uv.uv_timer_t, timer_running?: boolean, progress_idx: integer,  }

		local icon, timer = static.icon, ctx.timer
		local event = require("witch-line.core.manager.hook").use_event_info(self, sid)

		-- event nil when component triggered by self animation not by autocmd
		if event then
			if
				event.match == "NeoCodeiumLabelUpdated"
				and vim.bo.buftype ~= "prompt"
				and event.data == " * "
			then
				if not ctx.timer_running then
					timer = timer or (vim.uv or vim.loop).new_timer()
					if timer then
						timer:start(
							0,
							math.floor(1000 / static.fps),
							vim.schedule_wrap(function()
								-- need to render immediately for animation
								require("witch-line.core.handler").refresh_component_graph(self, true)
							end)
						)
						ctx.timer_running = true
						ctx.timer = timer
					end
				end
			elseif timer then
				timer:stop()
				ctx.timer_running = false
			end
		end

		local status, server_status = require("neocodeium").get_status()
		local result = icon.idle
		if server_status ~= 0 then
			-- server_status
			-- 0 - Server is on (running)
			-- 1 - Connecting to the server (not working status)
			-- 2 - Server is off (stopped)
			result = icon.disabled
		elseif status ~= 0 then
			-- status
			-- 0 - Enabled
			-- 1 - Globally disabled with `:NeoCodeium disable`, `:NeoCodeium toggle` or with `setup.enabled = false`
			-- 2 - Buffer is disabled with `:NeoCodeium disable_buffer`
			-- 3 - Buffer is disableld when it's filetype is matching `setup.filetypes = { some_filetyps = false }`
			-- 4 - Buffer is disabled when `setup.filter` returns `false` for the current buffer
			-- 5 - Buffer has wrong encoding (windsurf can accept only UTF-8 and LATIN-1 encodings)
			-- 6 - Buffer is of special type `:help 'buftype'`
			result = icon.disabled
		elseif ctx.timer_running then -- animation running
			local progress_idx = ctx.progress_idx
			progress_idx = progress_idx < #icon.waiting and progress_idx + 1 or 1
			ctx.progress_idx = progress_idx
			return icon.waiting[progress_idx]
		elseif event and event.match == "NeoCodeiumLabelUpdated" then
			if event.data == " 0 " or event.data == "   " then
				result = icon.idle
			else
				result = icon.completions .. " " .. event.data:match("^%s*(.-)%s*$")
			end
		end
		ctx.progress_idx = 0
		return result
	end,
}

return {
	windsurf = WindSurf,
	neocodeium = Neocodeium,
}
