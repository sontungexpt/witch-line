local type, rawset = type, rawset
local CacheMod = require("witch-line.cache")
local Id = require("witch-line.constant.id")

local M = {}

---@alias DepStore table<Id, table<Id, true>>
---
---@type table<NotNil, DepStore>
local DepStore = {
	-- [store_id] = {
	--    [comp_id] = {
	--      -- [comp_id] = true, -- this component depends on comp_id
	--   }
	-- }
	--
}

---@type table<Id, Component>
local Comps = {
	--[id] = {}
}

M.cache = function()
	CacheMod.cache(Comps, "Comps")
	CacheMod.cache(DepStore, "DepStore")
end

M.load_cache = function()
	Comps = CacheMod.get().Comps or Comps
	DepStore = CacheMod.get().DepStore or DepStore
end

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
	local id_type = type(id)
	if (id_type == "number" and Id[id] ~= nil) or id_type ~= "string" then
		id = tostring(id)
	end
	Comps[id] = comp
	rawset(comp, "id", id) -- Ensure the component has an ID field
	return id
end

--- Register a component with the component manager without checking for an ID.
--- @param comp Component The component to register.
--- @return Id|nil The ID of the registered component.
M.fast_register = function(comp)
	local id = comp.id
	local type_id = type(id)
	if type_id ~= "number" and type_id ~= "string" then
		error("Component must have a valid ID")
		return nil
	end

	Comps[id] = comp
	return id
end

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
--- @param ref Id|Id[] The event or component ID that this component depends on.
--- @param store DepStore Optional. The store to add the dependency to. Defaults to EventRefs.
local function link_ref_field(comp, ref, store)
	if type(ref) == "table" then
		local id = comp.id
		for i = 1, #ref do
			local on_i = ref[i]
			local deps = store[on_i] or {}
			---@diagnostic disable-next-line: need-check-nil
			deps[id] = true
			store[on_i] = deps
		end
		return
	end

	local deps = store[ref] or {}
	deps[comp.id] = true
	store[ref] = deps
end
M.link_ref_field = link_ref_field

--- Link a component to an event or another component by its ID.
--- @param comp Component The component to link.
--- @param on Id|Id[] The event or component ID that this component depends on.
--- @param id NotNil The ID of the component to link.
local function link_dep_by_id(comp, on, id)
	link_ref_field(comp, on, get_dep_store(id))
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

--- Check if a given ID is a valid component ID.
--- @param id NotNil The ID to check.
--- @return boolean valid True if the ID is valid, false otherwise.
M.is_id = function(id)
	return Comps[id] ~= nil
end

--- Get a component by its ID.
--- @param id Id The ID of the component to retrieve.
--- @return Component|nil The component with the given ID, or nil if not found.
M.get_comp = function(id)
	return id and Comps[id]
end

--- Recursively get a value from a component.
--- @param comp Component The component to get the value from.
--- @param key string The key to look for in the component.
--- @param session_id SessionId The ID of the process to use for this retrieval.
--- @param seen table<string, boolean> A table to keep track of already seen values to avoid infinite recursion.
--- @param ... any Additional arguments to pass to the value function.
--- @return any value The value retrieved from the component.
--- @return Component last_ref_comp The component that provided the value, or nil if not found.
local function lookup_ref_value(comp, key, session_id, seen, ...)
	local id, value = comp.id, comp[key]
	local store = require("witch-line.core.Session").get_store(session_id, key, {})
	if store[id] then
		return store[id], comp
	elseif value then
		if type(value) == "function" then
			value = value(comp, ...)
		end
		store[id] = value
		return value, comp
	end
	local ref = comp.ref
	if type(ref) ~= "table" then
		return nil, comp
	end

	local ref_id = ref[key]
	if not ref_id or seen[ref_id] then
		return nil, comp
	end
	local ref_comp = Comps[ref_id]
	if ref_comp then
		return lookup_ref_value(ref_comp, key, session_id, seen, ...)
	end
	return nil, comp
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
--- @param ctx any The context to pass to the component's style function.
--- @param static any Optional. If true, the static value will be used for the style.
--- @return vim.api.keyset.highlight|nil style The style of the component.
--- @return Component inherited The component that provides the style, or nil if not found.
M.get_style = function(comp, session_id, ctx, static)
	return lookup_ref_value(comp, "style", session_id, {}, ctx, static)
end

--- Check if a component should be displayed.
--- @param comp Component The component to check.
--- @param session_id SessionId The ID of the process to use for this check.
--- @param ctx any The context to pass to the component's should_display function.
--- @param static any Optional. If true, the static value will be used for the check.
--- @return boolean displayed True if the component should be displayed, false otherwise.
--- @return Component inherited The component that provides the should_display value, or nil if not found.
M.should_hidden = function(comp, session_id, ctx, static)
	local displayed, last_comp = lookup_ref_value(comp, "should_display", session_id, {}, ctx, static)
	return displayed == true, last_comp
end

--- Get the static value for a component by recursively checking its dependencies.
--- @param comp Component The component to get the static value for.
--- @param key string The key to look for in the component.
--- @param seen table<Id, boolean> A table to keep track of already seen values to avoid infinite recursion.
--- @return NotString value The static value of the component.
--- @return Component inherited The component that provides the static value.
local function lookup_inherited_value(comp, key, seen)
	local static = comp[key]
	if static then
		return static, comp
	end

	local ref = comp.ref
	if type(ref) ~= "table" then
		return nil, comp
	end

	static = ref[key]
	if not static then
		return nil, comp
	end

	local ref_comp = Comps[static]
	if ref_comp and not seen[static] then
		return lookup_inherited_value(ref_comp, key, seen)
	end
	return nil, comp
end

M.lookup_inherited_value = lookup_inherited_value

--- Get the static value for a component.
--- @param comp Component The component to get the static value for.
--- @return NotString value The static value of the component.
--- @return Component|nil inherited The component that provides the static value.
function M.get_static(comp)
	return lookup_inherited_value(comp, "static", {})
end

function M.inspect(key)
	if key == "Dep" then
		vim.notify("DepStore: " .. vim.inspect(DepStore))
		return
	end
	vim.notify("Comps: " .. vim.inspect(Comps))
end

return M
