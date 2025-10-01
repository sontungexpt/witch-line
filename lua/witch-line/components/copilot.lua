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
	init = function(self, static)
		local nvim_exec_autocmds = vim.api.nvim_exec_autocmds
		local get_option = vim.api.nvim_get_option_value
		local timer = vim.uv.new_timer()
		if not timer then
			require("witch-line.utils.notifier").error("Cannot create timer for Copilot component")
			return
		end

		local curr_inprogress_index = 0
		local icon = self.static.icon
		local status = ""
		vim.api.nvim_create_autocmd("InsertEnter", {
			once = true,
			desc = "Init copilot status",
			callback = function()
				local cp_api_ok, cp_api = pcall(require, "copilot.api")
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
									nvim_exec_autocmds("User", {
										pattern = "WLCopilotLoad",
										modeline = false,
									})
								end)
							)
							return
						end
						timer:stop()
						nvim_exec_autocmds("User", {
							pattern = "WLCopilotLoad",
							modeline = false,
						})
					end))
				end
			end,
		})

		self.static.get_icon = function()
			if status == "inprogress" then
				curr_inprogress_index = curr_inprogress_index < #icon.inprogress and curr_inprogress_index + 1 or 1
				return icon.inprogress[curr_inprogress_index]
			else
				curr_inprogress_index = 0
				return icon[status] or status or ""
			end
		end

		self.static.check_status = function()
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
	end,

	update = function(self, ctx, static)
		if package.loaded["copilot"] then
			static.check_status()
		end
		return static.get_icon()
	end,
}

return Copilot
