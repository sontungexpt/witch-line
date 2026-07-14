local bo = vim.bo

-- Spinner timer used while NeoCodeium is generating completions.
local neo_timer

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

        -- NeoCodeium emits " * " while it is generating a completion.
        -- Start a timer that periodically requests updates so the spinner
        -- animation advances without waiting for new events.
        if event and event.match == "NeoCodeiumLabelUpdated" then
            if bo.buftype ~= "prompt" and event.data == " * " then
                neo_timer = neo_timer or assert(vim.uv.new_timer())

                if not neo_timer:is_active() then
                    neo_timer:start(
                        0,
                        math.floor(1000 / self.config.fps),
                        vim.schedule_wrap(function()
                            require("witch-line.engine.scheduler").update_comp(self, true)
                        end)
                    )
                end
                -- Stop animating once NeoCodeium finishes generating.
            elseif neo_timer then
                neo_timer:stop()
            end
        end

        local status, server_status = require("neocodeium").get_status()
        if server_status ~= 0 or status ~= 0 then
            return icon.disabled
        end

        -- While the timer is active, display the animated spinner.
        if neo_timer and neo_timer:is_active() then
            local frame = math.floor(vim.uv.now() * self.config.fps / 1000) % #icon.waiting + 1
            return icon.waiting[frame]
        end

        -- After generation completes, show the number of available
        -- completions if NeoCodeium reports one.
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
