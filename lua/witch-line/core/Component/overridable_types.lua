-- Common reusable type sets
local TYPE_STRING_FN = { "string", "function" }
local TYPE_FN_TABLE  = { "function", "table" }
local TYPE_BOOL_NUM  = { "boolean", "number" }
local TYPE_ANY       = { "number", "string", "boolean", "table", "function" }
local TYPE_BOOL_FN   = { "boolean", "function" }
local TYPE_NUMBER_FN = { "number", "function" }


return {
    padding = { "number", "table" },
    static = TYPE_ANY,
    timing = TYPE_BOOL_NUM,
    lazy = "boolean",
    style = TYPE_FN_TABLE,
    min_screen_width = TYPE_NUMBER_FN,
    hide = TYPE_BOOL_FN,
    left_style = TYPE_FN_TABLE,
    right_style = TYPE_FN_TABLE,
    left = TYPE_STRING_FN,
    right = TYPE_STRING_FN,
    flexible = "number",
}
