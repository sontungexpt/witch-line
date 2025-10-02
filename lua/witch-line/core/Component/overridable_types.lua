local SF  = {
    "string",
    "function"
}
local FT  = {
    "function",
    "table"
}
local ANY = {
    "number",
    "string",
    "boolean",
    "table",
    "function",
    "thread",
    "userdata"
}
return {
    padding = { "number", "table" },
    static = ANY,
    timing = { "boolean", "number" },
    lazy = { "boolean" },
    style = FT,
    min_screen_width = { "number" },
    hide = { "function", "boolean" },
    left_style = FT,
    left = SF,
    right_style = FT,
    right = SF,
}
