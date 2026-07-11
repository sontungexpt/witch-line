local Session = require("witch-line.core.session")
local Statusline = require("witch-line.engine.statusline")
local Update = require("witch-line.engine.update")
local DepGraphKind = require("witch-line.core.registry").DepGraphKind

local DEFAULT_KINDS = {
    DepGraphKind.Event,
    DepGraphKind.Timer,
}

local M = {}


local function finish_render(eager)
    if eager then
        Statusline.render()
    else
        Statusline.render_debounce()
    end
end


function M.update_ids(ids, dep_graph_kind, eager, event_info)
    Session.with_session(function(session)
        if event_info then
            session:set("EventInfo", event_info)
        end

        Update.update_comp_by_ids(
            ids,
            session,
            dep_graph_kind or DEFAULT_KINDS
        )
    end)

    finish_render(eager)
end

function M.update_comp(comp, eager, dep_graph_kind, seen)
    Session.with_session(function(session)
        Update.update_comp(
            comp,
            session,
            dep_graph_kind or DEFAULT_KINDS,
            seen
        )
    end)

    finish_render(eager)
end

return M
