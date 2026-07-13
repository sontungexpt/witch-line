local request_update = function(comp, eager)
    require("witch-line.engine.request").update_comp(comp, eager)
end

---@type DefaultComponent
local Codeium = {
    id = "wl.codeium",
    ___builtin = true,
    config = {
        fps = 4,
        icon = {
            idle = "󰚩",
            error = "󱚡",
            completions = "󱜙",
            waiting = {
                "󱇷   ",
                " 󱇷  ",
                "  󱇷 ",
                "   󱇷",
            },
            unauthorized = "󱚟",
            disabled = "󱚧",
        },
    },
    init = function(self, _)
        local interval = math.floor(1000 / self.config.fps)

        vim.api.nvim_create_autocmd("InsertEnter", {
            callback = function()
                vim.schedule(function()
                    local vt = package.loaded["codeium.virtual_text"]
                    if vt then
                        local timer
                        local anim_cb = vim.schedule_wrap(function()
                            request_update(self, true)
                        end)
                        vt.set_statusbar_refresh(function()
                            local s = vt.status()
                            if vim.bo.buftype ~= "prompt" and s and s.state == "waiting" then
                                timer = timer or vim.uv.new_timer()
                                if timer then
                                    timer:start(0, interval, anim_cb)
                                end
                                return
                            elseif timer then
                                timer:stop()
                            end
                            request_update(self)
                        end)
                        return true
                    end
                    request_update(self)
                end)
            end,
        })
    end,

    update = function(self, _)
        local icon = self.config.icon
        local api = require("codeium.api")
        if api then
            local err = api.check_status().api_key_error
            if err then
                if err:find("Auth") then
                    return icon.unauthorized
                end
                return icon.error
            end
        end

        local vt = package.loaded["codeium.virtual_text"]
        local status = vt and vt.status()
        if not status then
            return icon.disabled
        end

        if status.state == "waiting" then
            local frame = math.floor(vim.uv.now() * self.config.fps / 1000) % #icon.waiting + 1
            return icon.waiting[frame]
        end

        if status.state == "idle" then
            return icon.idle
        elseif status.state == "completions" and status.total > 0 then
            return icon.completions .. " " .. string.format("%d/%d", status.current, status.total)
        end
        return icon.disabled
    end,
}

return Codeium
