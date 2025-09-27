local type = type

local M = {}

---@alias DepStoreId Id
---@alias Deps table<Id, true>
---@alias DepStore table<Id, Deps>
---@type table<DepStoreId, DepStore>
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
			CacheMod.set(urgents, "Urgents")
		end
	end, 200)
end

M.on_vim_leave_pre = function()
	local CacheMod = require("witch-line.cache")
	local Component = require("witch-line.core.Component")

	for _, comp in pairs(Comps) do
		Component.remove_state_before_cache(comp)
	end
	CacheMod.set(Comps, "Comps")
	CacheMod.set(DepStore, "DepStore")
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

--- Iterate over all registered components.
--- @return fun(): Id, Component Iterator iterator over all components.
--- @return Component[] comps The list of all components.
M.iterate_comps = function()
	return pairs(Comps)
end

--- Get the component manager containing all registered components.
--- @return table<Id, Component> A proxy table to access components by their IDs.
M.get_comp_manager = function()
	-- return a proxy table to prevent direct access to Comps
	return setmetatable({}, {
		-- prevents a little bit for access raw comps
		__index = function(_, id)
			return Comps[id]
		end,
	})
end

--- Get a list of all registered components.
--- @return Component[] The list of all components.
M.get_list_comps = function()
	return vim.tbl_values(Comps)
end

--- Register a component with the component manager.
--- @param comp Component The component to register.
--- @param alt_id Id An alternative ID for the component if it does not have one.
--- @return Id The ID of the registered component.
M.register = function(comp, alt_id)
	local Component = require("witch-line.core.Component")
	local id = Component.valid_id(comp, alt_id)
	Comps[id] = comp
	return id
end


--- Check if a component with the given ID exists.
--- @param id NotNil The ID to check.
--- @return boolean exists True if the component exists, false otherwise.
M.is_existed = function(id)
	return Comps[id] ~= nil
end

--- Get the dependency store for a given ID, creating it if it does not exist.
--- @param id DepStoreId The ID to get the dependency store for.
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
--- @param id DepStoreId The ID of the dependency store to iterate over.
--- @generic T: table, K, V -- T is the type of the store, K is the type of the key, V is the type of the values
--- @return fun(table: table<K, V>, index?: K):K, V iterator An iterator function that returns the next key and value in the store.
--- @return T store  The dependency store for the given ID, or an empty table if none exist.
M.iterate_dep_store = function(id)
	local store = DepStore[id]
	return store and pairs(store) or function() end, store
end


--- Iterate over all components that depend on a given component ID in a specific dependency store.
--- @param dep_store_id DepStoreId The ID of the dependency store to search in.
--- @param id CompId The ID of the component to find dependencies for.
--- @return fun()|fun(): CompId, Component An iterator function that returns the next dependent ID and its component.
--- @return Deps|nil The dependencies map for the given ID, or nil if none exist.
M.iterate_dependencies = function(dep_store_id, id)
	assert(dep_store_id and id, "Both dep_store_id and ref_id must be provided")
	local store = DepStore[dep_store_id]
	local id_map = store and store[id]
	if not id_map then
		return function()
		end, nil
	end

	local dep_id = nil
	return function()
			repeat
				dep_id, _ = next(id_map, dep_id)
			until dep_id == nil or Comps[dep_id]
			return dep_id, Comps[dep_id]
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
--- @param ref CompId|CompId[] The ID or IDs that this component depends on.
--- @param store_id DepStoreId The ID of the dependency store to use.
--- @param ref_id_collector table<CompId, true>|nil Optional. A collector to track dependencies.
M.link_ref_field = function(comp, ref, store_id, ref_id_collector)
	local store = get_dep_store(store_id)

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

--- Recursively look up a value in a component and its references.
--- If the value is a function, it will be called with the component and any additional arguments.
--- The result will be cached in the session store to avoid redundant computations.
--- @param comp Component The component to start the lookup from.
--- @param key string The key to look for in the component.
--- @param session_id SessionId The ID of the process to use for this retrieval.
--- @param seen table<Id, boolean> A table to keep track of already seen values to avoid infinite recursion.
--- @param ... any Additional arguments to pass to the value function.
--- @return any value The value of the component for the given key, or nil if not found.
--- @return Component ref_comp The component that provides the value, or nil if not found.
--- @note
--- The difference between this function and `lookup_inherited_value` is that this function
--- will call functions and cache the result in the session store, while `lookup_inherited_value`
--- will only look for static values without calling functions or caching.	
local function lookup_ref_value(comp, key, session_id, seen, ...)
	local id, value = comp.id, comp[key]

	local store = require("witch-line.core.Session").get_store(session_id, key, {})
	if store[id] then
		return store[id], comp
	elseif value then
		if type(value) == "function" then
			value = value(comp, ..., session_id)
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
--- This function checks the `context` field of the component, which can be a static value or a function.
--- If it is a function, it will be called with the component.
--- The result will be cached in the session store to avoid redundant computations.
--- If the context is not found in the component, it will look up the reference chain.
--- @param comp Component The component to get the context for.
--- @param session_id SessionId The ID of the process to use for this retrieval.
--- @param static any Optional. If true, the context will be retrieved from the static value.
--- @return any context The context of the component.
--- @return Component inherited The component that provides the context, or nil if not found.
M.get_context = function(comp, session_id, static)
	return lookup_ref_value(comp, "context", session_id, {}, static)
end


--- Get the style for a component.
--- This function checks the `style` field of the component, which can be a static value
--- or a function. If it is a function, it will be called with the component and the provided context.
--- The result will be cached in the session store to avoid redundant computations.
--- If the style is not found in the component, it will look up the reference chain.
--- @param comp Component The component to get the style for.
--- @param session_id SessionId The ID of the process to use for this retrieval.
--- @param ctx any The context to pass to the component's style function.
--- @param static any Optional. If true, the static value will be used for the style.
--- @return vim.api.keyset.highlight|nil style The style of the component.
--- @return Component inherited The component that provides the style, or nil if not found.
M.get_style = function(comp, session_id, ctx, static, ...)
	return lookup_ref_value(comp, "style", session_id, {}, ctx, static, ...)
end

--- Check if a component should be displayed.
--- This function checks the `should_display` field of the component, which can be a boolean or a function.
--- If it is a function, it will be called with the component and the provided context.
--- The result will be cached in the session store to avoid redundant computations.
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
--- Check if a component should be displayed.
--- This function checks the `should_display` field of the component, which can be a boolean or a function.
--- If it is a function, it will be called with the component and the provided context.
--- The result will be cached in the session store to avoid redundant computations.
--- @param comp Component The component to check.
--- @param session_id SessionId The ID of the process to use for this check.
--- @param ctx any The context to pass to the component's should_display function.
--- @param static any Optional. If true, the static value will be used for the check.
--- @return boolean displayed True if the component should be displayed, false otherwise.
--- @return Component inherited The component that provides the should_display value, or nil if not found.
M.get_min_screen_width = function(comp, session_id, ctx, static)
	local min_width, last_comp = lookup_ref_value(comp, "min_screen_width", session_id, {}, ctx, static)
	return min_width, last_comp
end

--- Recursively look up a static value in a component and its references.
--- If the value is found, it is returned along with the component that provides it.
--- This function does not call functions or cache results; it only looks for static values.
--- @param comp Component The component to start the lookup from.
--- @param key string The key to look for in the component.
--- @param seen table<Id, boolean> A table to keep track of already seen values to avoid infinite recursion.
--- @return any value The static value of the component.
--- @return Component inheritted The component that provides the static value
--- @note
--- The difference between this function and `lookup_ref_value` is that this function
--- will only look for static values without calling functions or caching, while `lookup_ref_value`
--- will call functions and cache the result in the session store.
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

--- Get the value of the static field for a component.
--- This function looks up the `static` field in the component and its references.
--- It does not call functions or cache results; it only looks for static values.
--- If the static value is not found in the component, it will look up the reference chain.
--- If the reference is not found, it will return nil.
--- @param comp Component The component to get the static value for.
--- @return any value The static value of the component.
--- @return Component|nil inherited The component that provides the static value.
function M.get_static(comp)
	return lookup_inherited_value(comp, "static", {})
end

--- Inspect the current state of the component manager.
--- @param key "dep_store"|"comps" The key to inspect.
function M.inspect(key)
	local notifier = require("witch-line.utils.notifier")
	if key == "dep_store" then
		notifier.info(
			"Inspecting DepStore\n" .. vim.inspect(DepStore or {})
		)
	else
		notifier.info(
			"Inspecting Comps\n" .. vim.inspect(Comps or {})
		)
	end
end

return M
