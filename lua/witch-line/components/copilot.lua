local Id = require("witch-line.constant.id").Id

---@type DefaultComponent
local Copilot = {
	id = Id["copilot"],
	name = "copilot",
	_plug_provided = true,
	user_events = { "WLCopilotLoad" },
	static = {
		icon = {
			normal = "",
			error = "",
			warning = "",
			inprogress = { "", "󰪞", "󰪟", "󰪠", "󰪢", "󰪣", "󰪤", "󰪥" },
		},
		fps = 3, -- should be 3 - 5
	},
  context = {},
	init = function(self, ctx, static)
		local get_option = vim.api.nvim_get_option_value
    local refresh_component_graph = require("witch-line.core.handler").refresh_component_graph
		local timer = (vim.uv or vim.loop).new_timer()
		local curr_inprogress_index = 0
		local icon = static.icon
		local status = ""

		local check_status = function()
			local cp_client_ok, cp_client = pcall(require, "copilot.client")
			if not cp_client_ok then
				status = "error"
				require("sttusline.util.notify").error("Cannot load copilot.client")
				return
			end

			local copilot_client = cp_client.get()
			if not copilot_client then
				status = "error"
				return
			end

			local cp_api_ok, cp_api = pcall(require, "copilot.api")
			if not cp_api_ok then
				status = "error"
				require("sttusline.util.notify").error("Cannot load copilot.api")
				return
			end

			cp_api.check_status(copilot_client, {}, function(cserr, status_copilot)
				if cserr or not status_copilot.user or status_copilot.status ~= "OK" then
					status = "error"
					return
				end
			end)
		end
		vim.api.nvim_create_autocmd("InsertEnter", {
			once = true,
			desc = "Init copilot status",
			callback = function()
				local cp_api_ok, cp_api = pcall(require, "copilot.status")
				if cp_api_ok then
					cp_api.register_status_notification_handler(vim.schedule_wrap(function(data)
						-- don't need to get status when in TelescopePrompt
						if get_option("buftype", { buf = 0 }) == "prompt" then
							return
          end

						status = string.lower(data.status or "")

						if status == "inprogress" then
							timer:start(
								0,
								math.floor(1000 / self.static.fps),
								vim.schedule_wrap(function()
                  refresh_component_graph(self)
									-- nvim_exec_autocmds("User", {
									-- 	pattern = "WLCopilotLoad",
									-- 	modeline = false,
									-- })
								end)
							)
							return
						end
						timer:stop()
            refresh_component_graph(self)
						-- nvim_exec_autocmds("User", {
						-- 	pattern = "WLCopilotLoad",
						-- 	modeline = false,
						-- })
					end))

          check_status()
				end
			end,
		})
		ctx.get_icon = function()
			if status == "inprogress" then
				curr_inprogress_index = curr_inprogress_index < #icon.inprogress and curr_inprogress_index + 1 or 1
				return icon.inprogress[curr_inprogress_index]
			else
				curr_inprogress_index = 0
				return icon[status] or status or ""
			end
		end

	end,

	update = function(self, ctx, static, session_id)
		return ctx.get_icon()
	end,
}

return Copilot
