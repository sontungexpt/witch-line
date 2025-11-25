local type, next = type, next

-- Common reusable type sets
local TYPE_STRING_FN = { "string", "function" }
local TYPE_FN_TABLE = { "function", "table" }
local TYPE_BOOL_NUM = { "boolean", "number" }
local TYPE_ANY = { "number", "string", "boolean", "table", "function" }
local TYPE_BOOL_FN = { "boolean", "function" }
local TYPE_NUMBER_FN = { "number", "function" }

local OVERRIDEABLE_TYPE_MAP = {
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
	auto_theme = TYPE_BOOL_FN,
}

local M = {}
--- Recursively overrides the values of a component with the values from another component.
--- If the types of the values are different, the value from the original component is kept.
--- If the values are not tables, the value from the new component is used.
--- If both values are tables, the function is called recursively on the tables.
--- If one of the tables is empty, the other table is used.
--- If both tables are empty, the original table is kept.
--- If both values are lists, the value from the new component is used.
--- @param to any the original component value
--- @param from any the new component value
--- @param skip_type_check boolean|nil if true, skips the type check and always overrides
--- @return any value the overridden component value
local function overrides_component_value(to, from, skip_type_check)
	if to == nil then
		return from
	elseif from == nil then
		return to
	end

	local to_type, from_type = type(to), type(from)

	if not skip_type_check and to_type ~= from_type then
		return to
	elseif from_type ~= "table" then
		return from
		-- both are table from here
	elseif next(to) == nil then
		return from
	elseif next(from) == nil then
		return to
	elseif vim.islist(to) and vim.islist(from) then
		return from
	end

	for k, v in pairs(from) do
		to[k] = overrides_component_value(to[k], v, skip_type_check)
	end
	return to
end

--- Creates a custom statistic component, which can be used to display custom statistics in the status line.
--- @param comp DefaultComponent the component to create the statistic for
--- @param override table|nil a table of overrides for the component, can be used to set custom fields or values
--- @return Component stat_comp the statistic component with the necessary fields set
M.override = function(comp, override)
	if type(override) ~= "table" then
		return comp
	end

	if override.style then
		comp._use_returned_style = false
	end

	if override.style or override.left_style or override.right_style then
		comp.auto_theme = false
	end

	for k, v in pairs(override) do
		local accepts = OVERRIDEABLE_TYPE_MAP[k]
		if accepts then
			local type_v = type(v)
			if
				type(accepts) == "table" and vim.list_contains(accepts, type_v)
				or accepts == type_v -- single type
			then
				if type_v == "table" then
					rawset(comp, k, overrides_component_value(comp[k], v, true))
				else
					rawset(comp, k, v)
				end
			end
		end
	end

	return comp
end
return M
