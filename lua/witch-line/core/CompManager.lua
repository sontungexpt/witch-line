type = type

local M = {}

---@alias DepGraphId Id
---@alias DepMap table<CompId, true>
---@alias DepGraph table<CompId, DepMap>
---@type table<DepGraphId, DepGraph>
local DepGraphMap = {
	-- [store_id] = {
	--    [comp_id] = {
	--      -- [comp_id] = true, -- this component depends on comp_id
	--   }
	-- }
	--
}


---@type table<CompId, ManagedComponent>
local Comps = {
	--[id] = {}
}


--- @type CompId[]
local InitializePendingIds = {}

--- Queue the `init` method of a component to be called in the next render cycle.
--- @param id CompId The ID of the component to initialize.
M.queue_initialization = function(id)
	InitializePendingIds[#InitializePendingIds + 1] = id
end

--- Iterate over the queue of components pending initialization (FIFO).
--- @return fun(): CompId|nil, Component iterator A function that returns the next component ID in the queue
M.iter_pending_init_components = function()
	local index = 0
	return function()
		index = index + 1
		local id = InitializePendingIds[index]
		if not id then
			return nil
		end
		return id, Comps[id]
	end
end

--- @type CompId[]
local EmergencyIds = {}

--- Get the list of component IDs marked as urgent.
--- @return CompId[] The list of component IDs marked as urgent.
M.get_emergency_ids = function()
	return EmergencyIds
end

--- Mark a component as urgent to be updated in the next render cycle.
--- @param id CompId The ID of the component to mark as urgent.
M.mark_emergency = function(id)
	EmergencyIds[#EmergencyIds + 1] = id
end

--- Iterate over the queue of urgent components (FIFO).
--- @return fun(): CompId|, Component iterator A function that returns the next component ID in the queue
M.iter_emergency_components = function()
	local index = 0
	return function()
		index = index + 1
		local id = EmergencyIds[index]
		if not id then
			return nil
		end
		return id, Comps[id]
	end
end


--- The function to be called before Vim exits.
--- @param CacheDataAccessor Cache.DataAccessor The cache module to use for saving the stores.
M.on_vim_leave_pre = function(CacheDataAccessor)
	local Component = require("witch-line.core.Component")
	for _, comp in pairs(Comps) do
		Component.remove_state_before_cache(comp)
	end
	CacheDataAccessor.set("Comps", Comps)
	CacheDataAccessor.set("DepGraph", DepGraphMap)
	CacheDataAccessor.set("Urgents", EmergencyIds)
	CacheDataAccessor.set("PendingInit", InitializePendingIds)
end

--- Load the cache for components and dependency stores.
--- @param CacheDataAccessor Cache.DataAccessor The cache module to use for loading the stores.
--- @return function undo Function to restore the previous state of Comps and DepGraph.
M.load_cache = function(CacheDataAccessor)
	local before_comps,
	before_dep_store,
	before_pending_inits,
	before_urgents =
		Comps,
		DepGraphMap,
		InitializePendingIds,
		EmergencyIds


	Comps = CacheDataAccessor.get("Comps") or Comps
	DepGraphMap = CacheDataAccessor.get("DepGraph") or DepGraphMap
	InitializePendingIds = CacheDataAccessor.get("PendingInit") or InitializePendingIds
	EmergencyIds = CacheDataAccessor.get("Urgents") or EmergencyIds
	return function()
		Comps = before_comps
		DepGraphMap = before_dep_store
		InitializePendingIds = before_pending_inits
		EmergencyIds = before_urgents
	end
end

--- Iterate over all registered components.
--- @return fun(): CompId, ManagedComponent iterator Iterator over all components.
--- @return ManagedComponent[] comps The list of all components.
M.iterate_comps = function()
	return pairs(Comps)
end


--- Get a list of all registered components.
--- @return ManagedComponent[] The list of all components.
M.get_list_comps = function()
	return vim.tbl_values(Comps)
end

--- Register a component with the component manager.
--- @param comp Component The component to register.
--- @return CompId The ID of the registered component.
M.register = function(comp)
	local id = require("witch-line.core.Component").valid_id(comp)
	Comps[id] = comp
	return id
end


--- Check if a component with the given ID exists.
--- @param id CompId ID to check.
--- @return boolean existed True if the component exists, false otherwise.
M.is_existed = function(id)
	return Comps[id] ~= nil
end

--- Get the dependency store for a given ID, creating it if it does not exist.
--- @param id DepGraphId The ID to get the dependency store for.
--- @param raw boolean|nil If true, return the raw store without creating it if it doesn't exist.
--- @return DepGraph depstore The dependency store for the given ID.
local get_dependency_graph = function(id, raw)
	local id_type = type(id)
	assert(id_type == "number" or id_type == "string", "id must be a number or string, got: " .. id_type)

	local dep_store = DepGraphMap[id]
	if raw then
		return dep_store
	end

	if not dep_store then
		dep_store = {}
		DepGraphMap[id] = dep_store
	end
	return dep_store
end
M.get_dependency_graph = get_dependency_graph

--- A iterator to loop all key, value in the depstore has id
--- @param id DepGraphId The ID of the dependency store to iterate over.
--- @return fun()|fun(): CompId, DepMap An iterator function that returns the next ID and its dependencies.
--- @return DepGraph|nil The dependency store for the given ID, or nil if it doesn't exist.
M.iterate_dependency_map = function(id)
	local store = DepGraphMap[id]
	return store and pairs(store) or function() end, store
end

--- Iterate over all dependency stores.
--- @return fun()|fun(): DepGraphId, DepGraph iterator An iterator function that returns
--- @return table<DepGraphId, DepGraph> dep_graph_map The dependency graph map.
M.iterate_dependency_graph = function()
	return pairs(DepGraphMap)
end

--- Iterate over all components that depend on a given component ID in a specific dependency store.
--- Must sure that all components are registered before call this function including dependencies components.
--- @param dep_graph_id DepGraphId The ID of the dependency store to search in.
--- @param comp_id CompId The ID of the component to find dependencies for.
--- @return fun()|fun(): CompId, Component An iterator function that returns the next dependent ID and its component.
--- @return DepMap|nil The dependencies map for the given ID, or nil if none exist.
M.iterate_dependents = function(dep_graph_id, comp_id)
	assert(dep_graph_id and comp_id, "Both dep_graph_id and ref_id must be provided")
	local store = DepGraphMap[dep_graph_id]
	local id_map = store and store[comp_id]
	if not id_map then
		return function() end, nil
	end
	local curr_id = nil
	return function()
		curr_id = next(id_map, curr_id)
		if curr_id then
			return curr_id, Comps[curr_id]
		end
	end, id_map
end

--- Iterate over all dependency IDs that a given component ID depends on in a specific dependency store
--- @param comp_id CompId The ID of the component to find dependencies for
--- @return fun()|fun(): CompId|nil An iterator function that returns the next dependent ID
M.iterate_all_dependency_ids = function(comp_id)
	assert(comp_id, "comp id must be provided")

	local deps = {}
	for _, graph in pairs(DepGraphMap) do
		for dep_id, map in pairs(graph) do
			if map[comp_id] then
				deps[dep_id] = true
			end
		end
	end

	local id = nil
	return function()
		id = next(deps, id)
		return id
	end
end




--- Add a dependency for a component.
--- @param comp Component The component to add the dependency for.
--- @param ref_id CompId|CompId[] The ID or IDs that this component depends on.
--- @param store_id DepGraphId The ID of the dependency store to use.
M.link_ref_field = function(comp, ref_id, store_id)
	local store = get_dependency_graph(store_id)

	if type(ref_id) ~= "table" then
		ref_id = { ref_id }
	end

	local id = comp.id
	for i = 1, #ref_id do
		local ref_id_i = ref_id[i]
		local deps = store[ref_id_i] or {}
		---@diagnostic disable-next-line: need-check-nil
		deps[id] = true
		store[ref_id_i] = deps
	end
end

--- Remove a dependency store by its ID.
--- @param id DepGraphId The ID of the dependency store to remove.
M.remove_dep_store = function(id)
	DepGraphMap[id] = nil
end

--- Remove all dependency stores.
M.remove_all_dep_store = function()
	DepGraphMap = {}
end

--- Clear all dependencies for a given ID in the dependency store.
--- @param id DepGraphId The ID of the dependency store to clear.
M.clear_dep_store = function(id)
	DepGraphMap[id] = {}
end



--- Get a component by its ID.
--- @param id CompId The ID of the component to retrieve.
--- @return Component|nil comp The component with the given ID, or nil if not found.
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
			local args = { ... }
			table.insert(args, session_id)
			value = value(comp, unpack(args))
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
--- @param static any The `static` field value of the component from this component or its references.
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
--- @param ctx any The `context` field value of the component from this component or its references.
--- @param static any The `static` field value of the component from this component or its references.
--- @return vim.api.keyset.highlight|nil style The style of the component.
--- @return Component inherited The component that provides the style, or nil if not found.
M.get_style = function(comp, session_id, ctx, static)
	return lookup_ref_value(comp, "style", session_id, {}, ctx, static)
end


--- Recursively look up a static value in a component and its references.
--- If the value is found, it is returned along with the component that provides it.
--- This function does not call functions or cache results; it only looks for static values.
--- @param comp Component The component to start the lookup from.
--- @param key string The key to look for in the component.
--- @param seen table<CompId, boolean> A table to keep track of already seen values to avoid infinite recursion.
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
M.get_static = function(comp)
	return lookup_inherited_value(comp, "static", {})
end

--- Inspect the current state of the component manager.
--- @param target "dep_store"|"comps"|nil The key to inspect.
M.inspect = function(target)
	local notifier = require("witch-line.utils.notifier")
	if target == "dep_store" then
		notifier.info(
			"Inspecting DepGraph\n" .. vim.inspect(DepGraphMap or {})
		)
	elseif target == "comps" then
		notifier.info(
			"Inspecting Comps\n" .. vim.inspect(Comps or {})
		)
	else
		notifier.info(
			"Inspecting dep_store and comps: \n" .. vim.inspect({
				DepGraph = DepGraphMap or {},
				Comps = Comps or {},
			})
		)
	end
end

return M
