local initial_context = {}
local M = {}

M.save_initial_context = function(comp)
  local id = comp.id
  local ctx = comp.context
  if type(ctx) == "table" then
    ctx = vim.deepcopy(ctx)
  end
  initial_context[id] = ctx
end

M.restore_initial_context = function(comp)
  local id = comp.id
  local ctx = initial_context[id]
  if ctx then
    if type(ctx) == "table" then
      ctx = vim.deepcopy(ctx)
    end
    comp.context = ctx
  end
end


return M
