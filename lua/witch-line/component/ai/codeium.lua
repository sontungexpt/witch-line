local request_update = function(comp, eager)
    local eng = package.loaded["witch-line.engine"]
    if eng then eng.request_update_comp_graph(comp, eager) end
end

local ICON = {
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
}

---@type DefaultComponent
local Codeium = {
    id = "wl.codeium",
    ___builtin = true,
    config = {
        fps = 4,
        icon = ICON,
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

local neo_timer
local neo_running = false

---@type DefaultComponent
local Neocodeium = {
    id = "wl.codeium.neocodeium",
    ___builtin = true,
    events =
    "User NeoCodeiumLabelUpdated,NeoCodeiumServerStopped,NeoCodeiumServerConnected,NeoCodeiumBufEnabled,NeoCodeiumEnabled,NeoCodeiumBufDisabled,NeoCodeiumDisabled",
    config = {
        fps = 4,
        icon = ICON,
    },
    update = function(self, session)
        local icon = self.config.icon
        local event = session.get("EventInfo")
        event = event and event[self.id]

        if event and event.match == "NeoCodeiumLabelUpdated" then
            if vim.bo.buftype ~= "prompt" and event.data == " * " then
                if not neo_running then
                    neo_timer = neo_timer or vim.uv.new_timer()
                    if neo_timer then
                        neo_timer:start(0, math.floor(1000 / self.config.fps), vim.schedule_wrap(function()
                            request_update(self, true)
                        end))
                        neo_running = true
                    end
                end
            elseif neo_timer then
                neo_timer:stop()
                neo_running = false
            end
        end

        local status, server_status = require("neocodeium").get_status()
        if server_status ~= 0 or status ~= 0 then
            return icon.disabled
        end

        if neo_running then
            local frame = math.floor(vim.uv.now() * self.config.fps / 1000) % #icon.waiting + 1
            return icon.waiting[frame]
        end

        if event and event.match == "NeoCodeiumLabelUpdated" then
            local d = event.data
            if d ~= " 0 " and d ~= "   " then
                return icon.completions .. "  " .. d:match("^%s*(.-)%s*$")
            end
        end

        return icon.idle
    end,
}

return {
    codeium = Codeium,
    neocodeium = Neocodeium,
}
