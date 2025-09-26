local type = type

local M = {}

---@alias DepStore table<Id, table<Id, true>>
---@type table<Id, DepStore>
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

M.cache_ugent_comps = function(urgents)
	assert(type(urgents) == "table" and vim.isarray(urgents), "Urgents must be a table")
	local CacheMod = require("witch-line.cache")

	-- cache the value loaded in fast events
	vim.defer_fn(function()
		local map = {}
		for _, id in ipairs(urgents) do
			map[id] = true
		end

		for id, comp in pairs(Comps) do
			if comp._hidden == false and not map[id] then
				urgents[#urgents + 1] = id
			end
		end
		-- error(vim.inspect(urgents))

		if next(urgents) then
			CacheMod.cache(urgents, "Urgents")
		end
	end, 200)
end

M.on_vim_leave_pre = function()
	local CacheMod = require("witch-line.cache")
	local Component = require("witch-line.core.Component")

	for _, comp in pairs(Comps) do
		Component.remove_state_before_cache(comp)
	end
	CacheMod.cache(Comps, "Comps")
	CacheMod.cache(DepStore, "DepStore")
end

--- Load the cache for components and dependency stores.
--- @param Cache Cache The cache to load.
--- @return function undo Function to restore the previous state of Comps and DepStore.
M.load_cache = function(Cache)
	local before_comps = Comps
	local before_dep_store = DepStore

	Comps = Cache.get("Comps") or Comps
	DepStore = Cache.get("DepStore") or DepStore

	return function()
		Comps = before_comps
		DepStore = before_dep_store
	end
end

--- @return fun(): Id, Component Iterator iterator over all components.
--- @return Component[] comps The list of all components.
M.iterate_comps = function()
	return pairs(Comps)
end

--- Get the component manager.
--- @return table The component manager containing all registered components.
M.get_comps_map = function()
	return setmetatable({}, {
		-- prevents a little bit for access raw comps
		__index = function(_, id)
			return Comps[id]
		end,
	})
end

--- Get a list of all components.
--- @return Component[] The list of all components.
M.get_comps_list = function()
	return vim.tbl_values(Comps)
end

---- Register a component with the component manager.
--- @param comp Component The component to register.
--- @param alt_id Id Optional. An alternative ID for the component if it does not have one.
--- @return Id The ID of the registered component.
M.register = function(comp, alt_id)
	local Component = require("witch-line.core.Component")
	local id = Component.valid_id(comp, alt_id)
	Comps[id] = comp
	return id
end

---- Register a component with the component manager.
--- @param id Id The component to register.
M.id_exists = function(id)
	return Comps[id] ~= nil
end

--- Get the dependency store for a given ID.
--- @param id Id The ID to get the dependency store for.
--- @return DepStore The dependency store for the given ID.
local get_dep_store = function(id)
	local id_type = type(id)
	assert(id_type == "number" or id_type == "string", "id must be a number or string, got: " .. id_type)

	local dep_store = DepStore[id]
	if not dep_store then
		dep_store = {}
		DepStore[id] = dep_store
	end
	return dep_store
end
M.get_dep_store = get_dep_store

--- A iterator to loop all key, value in the depstore has id
--- @param id NotNil id of the depstore
--- @generic T: table, K, V
--- @return fun(table: table<K, V>, index?: K):K, V iterator
--- @return T store the store with id
M.iter_dep_store = function(id)
	local store = DepStore[id]
	return store and pairs(store) or function() end, store
end

--- Iterate over all dependents of a given component ID.
--- @param ds_id NotNil The ID of the dependency store to iterate over.
--- @param id NotNil The ID of the component to find dependents for.
--- @return fun()|fun(): Id, Component An iterator function that returns the next dependent ID and its component.
--- @return table<Id, true>|nil id_map The map of IDs that depend on the given component ID, or nil if none exist.
M.iter_dependents = function(ds_id, id)
	assert(ds_id and id, "Both ds_id and ref_id must be provided")
	local store = DepStore[ds_id]
	local id_map = store and store[id]
	if not id_map then
		return function() end, nil
	end

	local key = nil
	return function()
			repeat
				key, _ = next(id_map, key)
			until key == nil or Comps[key]
			return key, Comps[key]
		end,
		id_map
end

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
--- @param ref_id_collector table<Id, true>|nil Optional. A collector to track dependencies.
local function link_ref_field(comp, ref, store, ref_id_collector)
	if type(ref) ~= "table" then
		ref = { ref }
	end

	local id = comp.id
	for i = 1, #ref do
		local ref_id = ref[i]
		if ref_id_collector then
			ref_id_collector[ref_id] = true
		end

		local deps = store[ref_id] or {}
		---@diagnostic disable-next-line: need-check-nil
		deps[id] = true
		store[ref_id] = deps
	end
end
M.link_ref_field = link_ref_field

--- Link a component to an event or another component by its ID.
--- @param comp Component The component to link.
--- @param on Id|Id[] The event or component ID that this component depends on.
--- @param id NotNil The ID of the component to link.
--- @param ref_id_collector table<Id, true>|nil Optional. A collector to track dependencies.
M.link_ref_field_in_store_id = function(comp, on, id, ref_id_collector)
	link_ref_field(comp, on, get_dep_store(id), ref_id_collector)
end

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
M.get_style = function(comp, session_id, ctx, static, ...)
	return lookup_ref_value(comp, "style", session_id, {}, ctx, static, ...)
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

--- Inspect the component manager or dependency store.
--- @param key "dep_store"|"comps" The key to inspect.
function M.inspect(key)
	if key == "dep_store" then
		vim.notify(vim.inspect(DepStore or {}))
	else
		vim.notify(vim.inspect(Comps or {}))
	end
end

return M
