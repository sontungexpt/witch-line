
---@type integer|nil
local fps
---@type string
local status = ""
---@type integer
local progress_idx = 0
---@type uv.uv_timer_t|nil
local timer
---@type fun(): boolean|nil
local is_enabled

---@type DefaultComponent
local Copilot = {
    id = "copilot",
    _plug_provided = true,
    static = {
        fps = 3,
        icons = {
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
        local lazy_require = require("witch-line.utils.lazy_require")
        local refresh_component_graph = require("witch-line.core.handler").refresh_component_graph
        local cp_api = lazy_require("copilot.api")
        local cp_client = lazy_require("copilot.client")

        is_enabled = function()
            return not cp_client.is_disabled() and cp_client.buf_is_attached(vim.api.nvim_get_current_buf())
        end

        local check_status = function()
            local client = cp_client.get()
            if not client then
                status = "NoCLient"
            else
                cp_api.check_status(client, {}, function(cperr, cpstatus)
                    if cperr then
                        status = "Error"
                    elseif cpstatus.status == "OK" then
                        status = "Normal"
                    else
                        status = cpstatus.status
                    end
                end)
            end
        end

        vim.api.nvim_create_autocmd("LspAttach", {
            pattern = "copilot",
            once = true,
            callback = function()
                check_status()
                require("copilot.status").register_status_notification_handler(function(data)
                    if vim.bo.buftype == "prompt" then return end

                    local new_status = data.status
                    if new_status == "InProgress" then
                        status = "InProgress"
                        timer = timer or (vim.uv or vim.loop).new_timer()
                        if timer then
                            timer:start(0, math.floor(1000 / self.static.fps), vim.schedule_wrap(function()
                                refresh_component_graph(self, true)
                            end))
                        end
                        return
                    elseif new_status == "" then
                        new_status = "Error"
                    end
                    status = new_status

                    if timer then timer:stop() end
                    refresh_component_graph(self)
                end)
            end,
        })
    end,
    update = function(self, _)
        local icons = self.static.icons
        if not is_enabled or not is_enabled() then
            progress_idx = 0
            return icons.Disabled
        elseif status == "InProgress" then
            progress_idx = progress_idx < #icons.InProgress and progress_idx + 1 or 1
            return icons.InProgress[progress_idx]
        else
            progress_idx = 0
            return icons[status] or status or ""
        end
    end,
}

return Copilot
