--- Backward-compatible wrapper.
--- Functionality has been split into:
---   runtime/evaluator.lua  (value phase)
---   runtime/style.lua      (style phase)
---
--- This module re-exports everything from both for external compatibility.
local M = {}

-- Re-export SepStyle enum from style module
local StyleAPI = require("witch-line.runtime.style")
M.SepStyle = StyleAPI.SepStyle

-- Re-export evaluator functions
local Evaluator = require("witch-line.runtime.evaluator")
M.pre_update = Evaluator.pre_update
M.post_update = Evaluator.post_update
M.hidden = Evaluator.hidden
M.evaluate = Evaluator.evaluate
M.theme_aware = Evaluator.theme_aware

-- Re-export style functions
M.style = StyleAPI.resolve_main_style
M.side_style = StyleAPI.resolve_side_style
M.side = StyleAPI.resolve_side_value
M.convert_sep_style = StyleAPI.convert_sep_style

-- Legacy: hl_name_field is a utility, kept here for compat
M.hl_name_field = function(side)
    return side == "left" and "___left_hl_name" or "___right_hl_name"
end

return M
