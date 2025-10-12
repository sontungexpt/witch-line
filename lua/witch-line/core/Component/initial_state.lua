local initial_context = {}
local M = {}

--- Save the initial context of a component
--- @param comp Component The component to save the context for
--- @note This should be called when the component is created
--- @note The context is deep-copied to avoid mutations
M.save_initial_context = function(comp)
  local id = comp.id
  local ctx = comp.context
  if type(ctx) == "table" then
    ctx = vim.deepcopy(ctx)
  end
  initial_context[id] = ctx
end

--- Restore the initial context of a component
--- @param comp Component The component to restore the context for
--- @note This should be called when exit vim and the component is prepared to cache
M.restore_initial_context = function(comp)
  local id = comp.id
  local ctx = initial_context[id]
  if ctx then
    if type(ctx) == "table" then
      ctx = vim.deepcopy(ctx)
    end
    rawset(comp, "context", ctx)
  end
end


return M
