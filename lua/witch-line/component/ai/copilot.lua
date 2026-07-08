local status = ""
local progress_idx = 0
local timer
local is_enabled
local uv = vim.uv or vim.loop

local request_update = function(comp, eager)
    local eng = package.loaded["witch-line.engine"]
    if eng then eng.request_update_comp_graph(comp, eager) end
end

local Copilot = {
    id = "wl.copilot",
    ___builtin = true,
    config = {
        fps = 3,
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
    },
    init = function(self, _)
        local ok_api, api = pcall(require, "copilot.api")
        local ok_client, client = pcall(require, "copilot.client")
        if not ok_api or not ok_client then return end

        local progress_len = #self.config.icon.InProgress
        local interval = math.floor(1000 / self.config.fps)
        self.___progress_len = progress_len

        is_enabled = function()
            return not client.is_disabled() and client.buf_is_attached(vim.api.nvim_get_current_buf())
        end

        local anim_cb = vim.schedule_wrap(function()
            request_update(self, true)
        end)

        vim.api.nvim_create_autocmd("LspAttach", {
            pattern = "copilot",
            once = true,
            callback = function()
                local client_obj = client.get()
                if client_obj then
                    api.check_status(client_obj, {}, function(err, cpstatus)
                        if err then
                            status = "Error"
                        elseif cpstatus.status == "OK" then
                            status = "Normal"
                        else
                            status = cpstatus.status
                        end
                    end)
                else
                    status = "NoCLient"
                end

                local ok_stat, handlers = pcall(require, "copilot.status")
                if ok_stat then
                    handlers.register_status_notification_handler(function(data)
                        if vim.bo.buftype == "prompt" then return end

                        local new_status = data.status
                        if new_status == "InProgress" then
                            status = "InProgress"
                            if not timer then timer = uv.new_timer() end
                            if timer then timer:start(0, interval, anim_cb) end
                            return
                        end

                        status = new_status == "" and "Error" or new_status
                        if timer then timer:stop() end
                        request_update(self)
                    end)
                end
            end,
        })
    end,
    update = function(self, _)
        if not is_enabled or not is_enabled() then
            progress_idx = 0
            return self.config.icon.Disabled
        end
        if status == "InProgress" then
            progress_idx = progress_idx % self.___progress_len + 1
            return self.config.icon.InProgress[progress_idx]
        end
        progress_idx = 0
        local icon = self.config.icon[status]
        return icon or status or ""
    end,
}

return Copilot
