local Id = require("witch-line.constant.id").Id

---@type DefaultComponent
local Copilot = {
	id = Id["copilot"],
	name = "copilot",
	_plug_provided = true,
	static = {
		icon = {
			Normal = "",
			Error = "",
			Warning = "",
			InProgress = { "", "󰪞", "󰪟", "󰪠", "󰪢", "󰪣", "󰪤", "󰪥" },
			NoCLient = "",
			NotAuthorized = "",
			NoTelemetryConsent = "",
			Disabled = "",
		},
		fps = 3, -- should be 3 - 5
	},
	context = {
		status = "", -- "Normal", "Warning", "InProgress", "NoClient", "NotAuthorized", "NoTelemetryConsent", "Error"
		progress_idx = 0,
	},
	init = function(self, session_id)
		local lazy_require = require("witch-line.utils.lazy_require")
		local refresh_component_graph = require("witch-line.core.handler").refresh_component_graph
		local cp_api = lazy_require("copilot.api")
		local cp_client = lazy_require("copilot.client")

		local static = self.static
		--- @cast static {icon: table, fps: number}
		local ctx = require("witch-line.core.manager.hook").use_context(self, session_id)

		local timer

		ctx.is_enabled = function()
			return not cp_client.is_disabled() and cp_client.buf_is_attached(vim.api.nvim_get_current_buf())
		end

		local check_status = function()
			local client = cp_client.get()
			if not client then
				ctx.status = "NoCLient"
			else
				cp_api.check_status(client, {}, function(cperr, cpstatus)
					if cperr then
						ctx.status = "Error"
					-- 'OK'|'NotAuthorized'|'NoTelemetryConsent'
					elseif cpstatus.status == "OK" then
						ctx.status = "Normal"
					else
						ctx.status = cpstatus.status
					end
				end)
			end
		end

		vim.api.nvim_create_autocmd("LspAttach", {
			pattern = "copilot",
			once = true,
			callback = function()
				check_status()
				refresh_component_graph(self)
				require("copilot.status").register_status_notification_handler(function(data)
					if vim.bo.buftype == "prompt" then
						return
					end -- skip prompt buffer

					--- "Normal", "Warning", "InProgress", ""
					local status = data.status
					if status == "InProgress" then
						ctx.status = "InProgress"
						timer = timer or (vim.uv or vim.loop).new_timer()
						timer:start(
							0,
							math.floor(1000 / static.fps),
							vim.schedule_wrap(function()
								refresh_component_graph(self)
							end)
						)
						return
					elseif status == "" then
						status = "Error"
					end
					ctx.status = status

					if timer then
						timer:stop()
					end
					refresh_component_graph(self)
				end)
			end,
		})
	end,

	update = function(self, session_id)
		local ctx = require("witch-line.core.manager.hook").use_context(self, session_id)
		--- @cast ctx {status : string, progress_idx: integer, is_enabled: fun(): boolean}
		local status = ctx.status
		local icon = self.static.icon
		local progress_idx = ctx.progress_idx

		if not ctx.is_enabled() then
			progress_idx = 0
			return icon.Disabled
		elseif status == "InProgress" then
			progress_idx = progress_idx < #icon.InProgress and progress_idx + 1 or 1
			return icon.InProgress[progress_idx]
		else
			progress_idx = 0
			return icon[status] or status or ""
		end
	end,
}

return Copilot
