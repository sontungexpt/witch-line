local Id = require("witch-line.constant.id").Id

---@type DefaultComponent
local WindSurf = {
	id = Id["windsurf"],
	_plug_provided = true,
	static = {
		-- local server_status_symbols = {
		--       [0] = "󰣺 ", -- Connected
		--       [1] = "󰣻 ", -- Connection Error
		--       [2] = "󰣽 ", -- Disconnected
		--     }

		--     local status_symbols = {
		--       [0] = "󰚩 ", -- Enabled
		--       [1] = "󱚧 ", -- Disabled Globally
		--       [3] = "󱚢 ", -- Disabled for Buffer filetype
		--       [5] = "󱚠 ", -- Disabled for Buffer encoding
		--       [2] = "󱙻 ", -- Disabled for Buffer (catch-all)
		--     }
		icon = {
			idle = "󰚩",
			erorr = "󱚧",
			warning = "",
			waiting = { "", "󰪞", "󰪟", "󰪠", "󰪢", "󰪣", "󰪤", "󰪥" },
			unauthorized = "󱙻",
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
									require("witch-line.core.handler").refresh_component_graph(self)
								end)
							)
						end
						return
					elseif timer then
						timer:stop()
					end
					require("witch-line.core.handler").refresh_component_graph(self)
				end)
			end,
		})
	end,

	update = function(self, sid)
		local icon = self.static.icon
		local ctx = self.context
		--- @cast ctx {status : string, progress_idx: integer, is_enabled: fun(): boolean}

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
			return string.format("%d/%d", status.current, status.total)
		end
		return icon.disabled
	end,
}

return WindSurf
