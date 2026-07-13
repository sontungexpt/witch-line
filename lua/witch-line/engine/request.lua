local M = {}

--- Request an update for multiple component IDs.
function M.update_ids(ids, dep_graph_kind, eager, event_info)
    require("witch-line.engine.scheduler").update_ids(ids, dep_graph_kind, eager, event_info)
end

--- Request an update for a single component.
function M.update_comp(comp, eager, dep_graph_kind, seen)
    require("witch-line.engine.scheduler").update_comp(comp, eager, dep_graph_kind, seen)
end

return M
