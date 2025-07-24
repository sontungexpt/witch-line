local type, rawset = type, rawset

local M = {}

---@type table<Id, Component>
local Comps = {}

--- Get the component manager.
--- @return table The component manager containing all registered components.
M.get_comps = function()
	return setmetatable({}, {
		-- prevents a little bit for access raw comps
		__index = function(_, id)
			return Comps[id] or rawget(Comps, id)
		end,
	})
end

---- Register a component with the component manager.
--- @param comp Component The component to register.
--- @param alt_id Id Optional. An alternative ID for the component if it does not have one.
--- @return Id The ID of the registered component.
M.register = function(comp, alt_id)
	local id = comp.id or alt_id
	Comps[id] = comp
	rawset(comp, "id", id) -- Ensure the component has an ID field
	return id
end

---@alias DepStore table<Id, table<Id, true>>
---@type table<NotNil, DepStore>
local DepStore = {
	-- [id] = {}
}

--- Get the dependency store for a given ID.
--- @param id NotNil The ID to get the dependency store for.
--- @return DepStore The dependency store for the given ID.
local get_dep_store = function(id)
	local dep_store = DepStore[id]
	if not dep_store then
		dep_store = {}
		DepStore[id] = dep_store
	end
	return dep_store
end
M.get_dep_store = get_dep_store

--- Get the raw dependency store for a given ID.
--- @param id NotNil The ID to get the raw dependency store for.
--- @return DepStore The raw dependency store for the given ID.
M.get_raw_dep_store = function(id)
	return DepStore[id]
end

M.get_dep_store = get_dep_store

--- Add a dependency for a component.
--- @param comp Component The component to add the dependency for.
--- @param on Id The event or component ID that this component depends on.
--- @param store DepStore Optional. The store to add the dependency to. Defaults to EventRefs.
local function link_dep(comp, on, store)
	local deps = store[on] or {}
	deps[comp.id] = true
	store[on] = deps
end
M.link_dep = link_dep

local function link_dep_by_id(comp, on, id)
	link_dep(comp, on, get_dep_store(id))
end
M.link_dep_by_id = link_dep_by_id

M.remove_dep_store = function(id)
	DepStore[id] = nil
end

M.clear_dep_store_by_id = function(id)
	DepStore[id] = {}
end

M.clear_dep_stores = function()
	DepStore = {}
end

---@type table<function, Id>
local FuncIdMap = {
	-- [function() end] = defined_id, -- Placeholder for empty function
}

--- Generate a unique ID for a component.--- @param id Id The ID to use for the component.--- @return Idas_id = function(id)
--- @param id Id The ID to use for the component.
--- @return Id The generated ID for the component.
local function as_id(id)
	local fun_id = function() end
	FuncIdMap[fun_id] = id
	return fun_id
end
--- Check if a given ID is a valid component ID.
--- @param id NotNil The ID to check.
--- @return boolean valid True if the ID is valid, false otherwise.
local is_id = function(id)
	return Comps[id] ~= nil or FuncIdMap[id] ~= nil
end

---Check if a given ID is a function ID
---@param id NotNil The ID to check.
local is_fun_id = function(id)
	return FuncIdMap[id] ~= nil
end

M.Id = {
	as_id = as_id,
	is_id = is_id,
	is_fun_id = is_fun_id,
}

--- Get a component by its ID.
--- @param id Id The ID of the component to retrieve.
--- @return Component|nil The component with the given ID, or nil if not found.
local get_comp_by_id = function(id)
	if id == nil then
		return nil
	end
	local comp = Comps[id]
	if comp then
		return comp
	elseif type(id) == "function" then
		id = FuncIdMap[id]
		return id and Comps[id]
	end
	return nil
end
M.get_comp_by_id = get_comp_by_id

--- Recursively get a value from a component.
--- @param comp Component The component to get the value from.
--- @param key string The key to look for in the component.
--- @param session_id SessionId The ID of the process to use for this retrieval.
--- @param seen table<string, boolean> A table to keep track of already seen values to avoid infinite recursion.
--- @param ... any Additional arguments to pass to the value function.
--- @return any value The value retrieved from the component.
--- @return Component last_ref_comp The component that provided the value, or nil if not found.
local function lookup_ref_value(comp, key, session_id, seen, ...)
	local value = comp[key]

	local ref_comp = get_comp_by_id(value)
	if ref_comp and not seen[value] then
		seen[value] = true
		local store = require("witch-line.core.Session").get_or_init(session_id, key, {})
		if store[value] then
			return store[value], value
		end

		local ref_value = ref_comp[key]
		local ref_comp2 = get_comp_by_id(ref_value)
		if ref_comp2 and not seen[ref_value] then
			return lookup_ref_value(ref_comp2, key, session_id, seen, ...)
		elseif type(ref_value) == "function" then
			ref_value = value(ref_comp, ...)
		end
		seen[value] = ref_value
		return ref_value, ref_comp
	elseif type(value) == "function" then
		value = value(comp, ...)
	end
	return value, comp
end
M.lookup_ref_value = lookup_ref_value

--- Get the context for a component.
--- @param comp Component The component to get the context for.
--- @param session_id SessionId The ID of the process to use for this retrieval.
--- @param static any Optional. If true, the context will be retrieved from the static value.
--- @return any context The context of the component.
--- @return Component inherited The component that provides the context, or nil if not found.
M.get_context = function(comp, session_id, static)
	return lookup_ref_value(comp, "context", session_id, {}, static)
end

--- Get the style for a component.
--- @param comp Component The component to get the context for.
--- @param session_id SessionId The ID of the process to use for this retrieval.
--- @param ... any Additional arguments to pass to the style function.
--- @return vim.api.keyset.highlight|nil style The style of the component.
--- @return Component inherited The component that provides the style, or nil if not found.
M.get_style = function(comp, session_id, ...)
	return lookup_ref_value(comp, "style", session_id, {}, ...)
end

--- Check if a component should be displayed.
--- @param comp Component The component to check.
--- @param session_id SessionId The ID of the process to use for this check.
--- @param ctx any The context to pass to the component's should_display function.
--- @param static any Optional. If true, the static value will be used for the check.
--- @return boolean displayed True if the component should be displayed, false otherwise.
--- @return Component inherited The component that provides the should_display value, or nil if not found.
M.should_display = function(comp, session_id, ctx, static)
	local displayed, last_comp = lookup_ref_value(comp, "should_display", session_id, {}, ctx, static)
	return displayed ~= false, last_comp
end

--- Get the static value for a component by recursively checking its dependencies.
--- @param comp Component The component to get the static value for.
--- @param key string The key to look for in the component.
--- @return NotString value The static value of the component.
--- @return Component inherited The component that provides the static value.
local function lookup_inherited_value(comp, key)
	if not comp then
		error("Component is nil or not found in CompIdMap")
	end

	local static = comp[key]
	local last_ref_comp, ref_comp = comp, get_comp_by_id(static)
	while ref_comp do
		last_ref_comp = ref_comp
		static = ref_comp[key]
		ref_comp = get_comp_by_id(static)
	end
	return static, last_ref_comp
end

M.lookup_inherited_value = lookup_inherited_value

--- Get the static value for a component.
--- @param comp Component The component to get the static value for.
--- @return NotString value The static value of the component.
--- @return Component|nil inherited The component that provides the static value.
function M.get_static(comp)
	return lookup_inherited_value(comp, "static")
end

return M
