local bo = vim.bo
local request_update = function(comp, eager)
    local eng = package.loaded["witch-line.engine"]
    if eng then eng.request_update_comp_graph(comp, eager) end
end

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
    update = function(self, session)
        local icon = self.config.icon
        local event = session:get("EventInfo")
        event = event and event[self.id]

        if event and event.match == "NeoCodeiumLabelUpdated" then
            if bo.buftype ~= "prompt" and event.data == " * " then
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

return Neocodeium
