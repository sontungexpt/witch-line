local type, rawget = type, rawget
local Session = require("witch-line.core.Session")
local get_session_store, new_session_store = Session.get_store, Session.new_store

local M = {}

--- @enum DepGraphKind
M.DepGraphKind = {
	Visible = 1,
	Event = 2,
	Timer = 3,
}

---@alias DepSet table<CompId, true>
---@alias DepGraphMap table<CompId, DepSet>
---@type table<DepGraphKind, DepGraphMap>
local DepGraphRegistry = {
  -- [GraphKind.Display] = {
	--   [comp_id] = {
	--     [dep_comp_id] = true, -- comp_id depends on dep_comp_id
	--   }
	-- }
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
		Component.format_state_before_cache(comp)
	end
	CacheDataAccessor.set("Comps", Comps)
	CacheDataAccessor.set("DepGraph", DepGraphRegistry)
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
		DepGraphRegistry,
		InitializePendingIds,
		EmergencyIds


	Comps = CacheDataAccessor.get("Comps") or Comps
	DepGraphRegistry = CacheDataAccessor.get("DepGraph") or DepGraphRegistry
	InitializePendingIds = CacheDataAccessor.get("PendingInit") or InitializePendingIds
	EmergencyIds = CacheDataAccessor.get("Urgents") or EmergencyIds
	return function()
		Comps = before_comps
		DepGraphRegistry = before_dep_store
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
	local id = require("witch-line.core.Component").setup(comp)
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
--- @param kind DepGraphKind The ID to get the dependency store for.
--- @param raw boolean|nil If true, return the raw store without creating it if it doesn't exist.
--- @return DepGraphMap depstore The dependency store for the given ID.
local get_dependency_graph = function(kind, raw)
	local id_type = type(kind)
	assert(id_type == "number" or id_type == "string", "id must be a number or string, got: " .. id_type)

	local dep_store = DepGraphRegistry[kind]
	if raw then
		return dep_store
	end

	if not dep_store then
		dep_store = {}
		DepGraphRegistry[kind] = dep_store
	end
	return dep_store
end
M.get_dependency_graph = get_dependency_graph

--- A iterator to loop all key, value in the depstore has id
--- @param id DepGraphKind The ID of the dependency store to iterate over.
--- @return fun()|fun(): CompId, DepSet An iterator function that returns the next ID and its dependencies.
--- @return DepGraphMap|nil The dependency store for the given ID, or nil if it doesn't exist.
M.iterate_dependency_map = function(id)
	local store = DepGraphRegistry[id]
	return store and pairs(store) or function() end, store
end

--- Iterate over all dependency stores.
--- @return fun()|fun(): DepGraphKind, DepGraphMap iterator An iterator function that returns
--- @return table<DepGraphKind, DepGraphMap> dep_graph_map The dependency graph map.
M.iterate_dependency_graph = function()
	return pairs(DepGraphRegistry)
end

--- Iterate over all components that depend on a given component ID in a specific dependency store.
--- Must sure that all components are registered before call this function including dependencies components.
--- @param dep_graph_kind DepGraphKind The ID of the dependency store to search in.
--- @param comp_id CompId The ID of the component to find dependencies for.
--- @return fun()|fun(): CompId, Component An iterator function that returns the next dependent ID and its component.
--- @return DepSet|nil The dependencies map for the given ID, or nil if none exist.
M.iterate_dependents = function(dep_graph_kind, comp_id)
	assert(dep_graph_kind and comp_id, "Both dep_graph_id and ref_id must be provided")
	local store = DepGraphRegistry[dep_graph_kind]
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
	for _, graph in pairs(DepGraphRegistry) do
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
--- @param ref CompId|CompId[] The ID or IDs that this component depends on.
--- @param dep_graph_kind DepGraphKind The ID of the dependency store to use.
M.link_ref_field = function(comp, ref, dep_graph_kind)
	local store = get_dependency_graph(dep_graph_kind)
	local id = comp.id
  --- @cast id CompId Id never nil

	if type(ref) ~= "table" then
		ref = { ref }
	end
	for i = 1, #ref do
		local r = ref[i]
		local dependents = store[r] or {}
		dependents[id] = true
		store[r] = dependents
	end
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
--- @param sid SessionId The ID of the process to use for this retrieval.
--- @param seen table<Id, boolean> A table to keep track of already seen values to avoid infinite recursion.
--- @param ... any Additional arguments to pass to the value function.
--- @return any value The value of the component for the given key, or nil if not found.
--- @return Component ref_comp The component that provides the value, or nil if not found.
--- @note
--- The difference between this function and `lookup_inherited_value` is that this function
--- will call functions and cache the result in the session store, while `lookup_inherited_value`
--- will only look for static values without calling functions or caching.
M.lookup_ref_value = function(comp, key, sid, seen, ...)
  -- local store = get_session_store(sid, key)
  local id = comp.id
  ---@cast id CompId
  -- local cached
  local value, ref, ref_comp

  -- Do as least one loop
  repeat
    value = rawget(comp, key)
    if value ~= nil then
      if type(value) == "function" then
        value = value(comp, sid, ...)
      end
      --- @cast id CompId
      -- if not store then
      --   store = new_session_store(sid, key, { [id] = value })
      -- else
      --   store[id] = value
      -- end
      return value, comp
    end
    seen[id] = true

    -- NOTE: Remove cache temporately because of inheritance problems
    -- Problem Detail: (Use the detail example for understand easily)
    -- If a child reference to a `context`
    -- and `context` call a `use_static` hook
    -- Both of child and parent has `static` field (means the child is ovveride `static` from parent)
    -- So the cache was invalid because it may be use the static of the parent instead of using the static field of the child
    -- So we need to find the new solution here
    -- Idea is creating a profile that manage if the child is ovveride field or not and if the `context` is using the hook or not
    -- Consider is it's worth or not
    --
    -- if store then
    --   cached = store[id]
    --   if cached ~= nil then
    --     return cached, comp
    --   end
    -- end


    --- Provides fallback inheritance via `comp.inherit` when `ref` is not a table.
    --- This enables function-based field inheritance without recalculating values.
    --- Example:
    --- ```lua
    --- local Base = { id = "base", context = function() return { foo = "bar" } end }
    --- local Child = { id = "child", inherit = "base", context = nil }
    --- ```
    --- `Child` will inherit the evaluated context from `Base`, avoiding repeated computation.
    ref = comp.ref
    id = (type(ref) == "table" and ref[key]) or comp.inherit
    if not id or seen[id] then
      return nil, comp
    end

    ref_comp = Comps[id]
    if not ref_comp then
      return nil, comp
    end
    comp = ref_comp
  until false -- until not comp -- never happens because of the return above

  return nil, comp
end


do
  local inheritted_cache = {}
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
  M.lookup_inherited_value = function(comp, key, seen)
    local id = comp.id
    local ref_id = id -- The id of the component contains the value
    local cache, val, ref, ref_comp
    repeat
      ---@cast ref_id CompId
      val = comp[key]
      if val ~= nil then
        ---@cast id CompId
        if id ~= ref_id then -- Only cache value if the component inherit value from other component
          inheritted_cache[id] = { [key] = val }
        end
        return val, comp
      end
      seen[ref_id] = true

      -- Check cache before lookup parent
      cache = inheritted_cache[ref_id]
      val = cache and cache[key]
      if val then
        return val, comp
      end

      ref = comp.ref
      ref_id = type(ref) == "table" and ref[key] or nil
      if not ref_id or seen[ref_id] then
        return nil, comp
      end

      ref_comp = Comps[ref_id]
      if not ref_comp then
        return nil, comp
      end
      comp = ref_comp
    until false -- until not comp -- never happens because of the return above

    return nil, comp
  end
end


--- Inspect the current state of the component manager.
--- @param target "dep_store"|"comps"|nil The key to inspect.
M.inspect = function(target)
	local notifier = require("witch-line.utils.notifier")
	if target == "dep_store" then
		notifier.info(
			"Inspecting DepGraph\n" .. vim.inspect(DepGraphRegistry or {})
		)
	elseif target == "comps" then
		notifier.info(
			"Inspecting Comps\n" .. vim.inspect(Comps or {})
		)
	else
		notifier.info(
			"Inspecting dep_store and comps: \n" .. vim.inspect({
				DepGraph = DepGraphRegistry or {},
				Comps = Comps or {},
			})
		)
	end
end

return M
