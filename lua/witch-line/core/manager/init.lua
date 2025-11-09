local type = type
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
	local before_comps, before_dep_store, before_pending_inits, before_urgents =
		Comps, DepGraphRegistry, InitializePendingIds, EmergencyIds

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
	end,
		id_map
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
M.link_dependency = function(comp, ref, dep_graph_kind)
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

-- local inherit = function(comp, field, seen)
-- 	-- Collect inheritance chain upward
-- 	local merged_val = comp[field]
-- 	local inherit_id = comp.inherit
-- 	while inherit_id and not seen[inherit_id] do
-- 		local parent = Comps[inherit_id]
-- 		if not parent then
-- 			break
-- 		end
-- 		local parent_val = parent[field]
-- 		if parent_val ~= nil then
-- 			if merged_val == nil then
-- 				merged_val = parent_val
-- 			elseif type(parent_val) == "table" and type(merged_val) == "table" then
-- 				merged_val = vim.tbl_deep_extend("keep", merged_val, parent_val)
-- 			else
-- 				break -- difference type
-- 			end
-- 		end
-- 		inherit_id = parent.inherit
-- 	end

-- 	return merged_val, comp
-- end

-- do
-- 	local inherited_cache = {}
-- 	--- Recursively look up a static value in a component and its references.
-- 	--- If the value is found, it is returned along with the component that provides it.
-- 	--- This function does not call functions or cache results; it only looks for static values.
-- 	--- @param comp Component The component to start the lookup from.
-- 	--- @param key string The key to look for in the component.
-- 	--- @param seen table<CompId, boolean> A table to keep track of already seen values to avoid infinite recursion.
-- 	--- @return any value The static value of the component.
-- 	--- @return Component inheritted The component that provides the static value
-- 	--- @note
-- 	--- The difference between this function and `lookup_ref_value` is that this function
-- 	--- will only look for static values without calling functions or caching, while `lookup_ref_value`
-- 	--- will call functions and cache the result in the session store.
-- 	M.lookup_plain_value = function(comp, key, seen)
-- 		-- Fast path: direct field hit
-- 		local value = comp[key]
-- 		if value ~= nil then
-- 			return value, comp
-- 		end

-- 		-- Handle references
-- 		local origin_id = comp.id
-- 		local ref_id = origin_id

-- 		---@cast ref_id CompId
-- 		repeat
-- 			-- Check cache
-- 			local cached_entry = inherited_cache[ref_id]
-- 			value = cached_entry and cached_entry[key]
-- 			if value then
-- 				return value, comp
-- 			end
-- 			seen[ref_id] = true

-- 			-- Resolve reference
-- 			local ref = comp.ref
-- 			ref_id = type(ref) == "table" and ref[key] or comp.inherit
-- 			if not ref_id or seen[ref_id] then
-- 				return nil, comp
-- 			end

-- 			-- Resolve referenced component
-- 			local ref_comp = Comps[ref_id]
-- 			if not ref_comp then
-- 				return nil, comp
-- 			end

-- 			-- Direct value lookup on referenced component
-- 			value = ref_comp[key]
-- 			if value ~= nil then
-- 				---@cast origin_id CompId
-- 				inherited_cache[origin_id] = { [key] = value }
-- 				return value, comp
-- 			end

-- 			-- Continue up the reference chain
-- 			comp = ref_comp
-- 		until false

-- 		return nil, comp
-- 	end
-- end

-- --- Recursively look up a value in a component and its references.
-- --- If the value is a function, it will be called with the component and any additional arguments.
-- --- The result will be cached in the session store to avoid redundant computations.
-- --- @param comp Component The component to start the lookup from.
-- --- @param key string The key to look for in the component.
-- --- @param sid SessionId The ID of the process to use for this retrieval.
-- --- @param seen table<Id, boolean> A table to keep track of already seen values to avoid infinite recursion.
-- --- @param ... any Additional arguments to pass to the value function.
-- --- @return any value The value of the component for the given key, or nil if not found.
-- --- @return Component ref_comp The component that provides the value, or nil if not found.
-- --- @note
-- --- The difference between this function and `lookup_inherited_value` is that this function
-- --- will call functions and cache the result in the session store, while `lookup_inherited_value`
-- --- will only look for static values without calling functions or caching.
-- M.lookup_dynamic_value = function(comp, key, sid, seen, ...)
-- 	local id, value, ref, ref_comp = comp.id, nil, nil, nil
-- 	---@cast id CompId
-- 	local cache = get_session_store(sid, key)

-- 	-- Do as least one loop
-- 	repeat
-- 		if cache then
-- 			value = cache[id]
-- 			if value then
-- 				return value, comp
-- 			end
-- 		end

-- 		-- Fast path: direct value or function field
-- 		value = comp[key]
-- 		if value then
-- 			if type(value) == "function" then
-- 				value = value(comp, sid, ...)
-- 			end

-- 			if cache then
-- 				cache[id] = value
-- 			else
-- 				cache = new_session_store(sid, key, { [id] = value })
-- 			end
-- 			return value, comp
-- 		end

-- 		seen[id] = true

-- 		--- Provides fallback inheritance via `comp.inherit` when `ref` is not a table.
-- 		--- This enables function-based field inheritance without recalculating values.
-- 		--- Example:
-- 		--- ```lua
-- 		--- local Base = { id = "base", context = function() return { foo = "bar" } end }
-- 		--- local Child = { id = "child", inherit = "base", context = nil }
-- 		--- ```
-- 		--- `Child` will inherit the evaluated context from `Base`, avoiding repeated computation.
-- 		ref = comp.ref
-- 		id = (type(ref) == "table" and ref[key]) or comp.inherit
-- 		if not id or seen[id] then
-- 			return nil, comp
-- 		end

-- 		ref_comp = Comps[id]
-- 		if not ref_comp then
-- 			return nil, comp
-- 		end
-- 		comp = ref_comp
-- 	until false -- until not comp -- never happens because of the return above

-- 	return nil, comp
-- end

--- Inspect the current state of the component manager.
--- @param target "dep_store"|"comps"|nil The key to inspect.
M.inspect = function(target)
	local notifier = require("witch-line.utils.notifier")
	if target == "dep_store" then
		notifier.info("Inspecting DepGraph\n" .. vim.inspect(DepGraphRegistry or {}))
	elseif target == "comps" then
		notifier.info("Inspecting Comps\n" .. vim.inspect(Comps or {}))
	else
		notifier.info("Inspecting dep_store and comps: \n" .. vim.inspect({
			DepGraph = DepGraphRegistry or {},
			Comps = Comps or {},
		}))
	end
end

do
	local raw_cache = {}
	--- Find the raw value of a key from a component, considering inheritance and reference chains.
	--- The function recursively searches through:
	---   1. Local field
	---   2. Inherited parent (via `inherit`)
	---   3. Referenced component(s) (via `ref`)
	---
	--- Results are cached per-origin to avoid redundant lookups.
	---
	--- @param comp ManagedComponent     The current component being inspected
	--- @param key string                The key name to look up
	--- @param seen table<CompId, boolean>   Tracks visited components to prevent infinite recursion
	--- @return nil|{[1]: any, [2]: ManagedComponent, [3]: ManagedComponent|nil} result  The found raw value (static or unevaluated function), the origin component where it is defined, and the final component in the inheritance/reference chain (if any)
	local function find_raw_value(comp, key, seen)
		local cid = comp.id
		if seen[cid] then
			return nil
		end
		seen[cid] = true
		-- Cache raw values by origin to prevent duplicate recursion
		local key_cache = raw_cache[key]
		local result = key_cache and key_cache[cid]
		if result then
			return result
		end

		-- Local value
		local v = comp[key]
		if v ~= nil then
			result = { v, comp }
			if key_cache then
				key_cache[cid] = result
			else
				raw_cache[key] = { [cid] = result }
			end
			return result
		end

		-- 2️⃣ Inherit from parent
		local inherit_id = comp.inherit
		if inherit_id then
			local parent = Comps[inherit_id]
			if parent then
				result = find_raw_value(parent, key, seen)
				if result ~= nil then
					if key_cache then
						key_cache[cid] = result
					else
						raw_cache[key] = { [cid] = result }
					end
					return result
				end
			end
		end

		-- 3️⃣ Reference chain lookup
		local ref = comp.ref
		if type(ref) == "table" then
			local ref_id = ref[key]
			if ref_id then
				local ref_comp = Comps[ref_id]
				if ref_comp then
					result = find_raw_value(ref_comp, key, seen)
					if result ~= nil then
						-- Keep the lastest ref
						result[3] = result[3] or ref_comp
						if key_cache then
							key_cache[cid] = result
						else
							raw_cache[key] = { [cid] = result }
						end
						return result
					end
				end
			end
		end

		return result
	end

	--- Perform a plain lookup for a key within a component hierarchy.
	--- This function retrieves the *raw* value of a key by recursively
	--- traversing inheritance (`inherit`) and reference (`ref`) chains,
	--- without evaluating function-type values.
	---
	--- Essentially, this is a non-dynamic version of `lookup_dynamic_value`,
	--- useful when you only need to know the original source of a value
	--- rather than its evaluated result.
	---
	--- @param comp ManagedComponent            Component to start the lookup from
	--- @param key string                       The key name to look up
	--- @param seen table<CompId, boolean>|nil  Optional recursion guard
	--- @return nil|{ [1]: any, [2]: ManagedComponent, [3]: ManagedComponent|nil } result  The raw value, its source component, and (if applicable) the final referenced component
	M.lookup_plain_value = function(comp, key, seen)
		return find_raw_value(comp, key, seen or {})
	end

	--- Resolve a key’s final value dynamically through inheritance and references.
	--- This function uses `find_raw_value` to find the source, then evaluates it
	--- if the value is a function.
	---
	--- @param comp ManagedComponent  Component to start the lookup from
	--- @param key string             The key name to resolve
	--- @param sid SessionId          Session ID for caching evaluated results
	--- @param seen table|nil         Optional set to prevent recursion
	--- @param ... any                Additional arguments passed to function-type values
	--- @return nil|{[1]: any, [2]: ManagedComponent, [3]: ManagedComponent|nil, [4]: true|nil} result  The found raw value (static or unevaluated function), the origin component where it is defined, and the final component in the inheritance/reference chain (if any), and true if function
	M.lookup_dynamic_value = function(comp, key, sid, seen, ...)
		local cid = comp.id
		-- Cache evaluated (resolved) value
		local cache = get_session_store(sid, key)
		local result = cache and cache[cid]
		if result then
			return result
		end

		result = find_raw_value(comp, key, seen or {})
		if result == nil then
			return nil
		end

		local value = result[1]
		if type(value) == "function" then
			local ctx_comp = result[3] or comp
			-- For inherited functions, use the origin component as context;
			-- for reference/local ones, use the provider component.
			value = value(ctx_comp, sid, ...)
			result = { value, result[2], ctx_comp, true }
		end

		-- Cache final evaluated value for this session
		if cache then
			cache[cid] = result
		else
			new_session_store(sid, key, { [cid] = result })
		end

		---@diagnostic disable-next-line: return-type-mismatch
		return result
	end
end

--- Merge the full inheritance chain of a component dynamically.
--- It resolves all parents recursively and merges their values
--- using dynamic lookups (`hfind_raw`) for correctness with refs and inheritance.
---
--- @param comp ManagedComponent The component to resolve inheritance for.
--- @return table merged The dynamically merged table result.
--- @return boolean had_func The dynamically merged table result.
function M.inherit(comp, key, sid, merge)
	local merged = {}
	local chain, n = {}, 0
	local pid = comp.inherit
	while pid do
		local c = Comps[pid]
		n = n + 1
		chain[n] = c
		pid = c.inherit
	end


local val, had_func = nil, false

	local r M.lookup_dynamic_value(comp, key, sid)
if r then
val, had_func =  r[1], r[4] or false
end

	for i = 1, n do
		local p = M.lookup_dynamic_value(chain[i], key, sid)
		if p then
			val = merge(val, p[1])
			had_func = had_func or p[4] or false
		end
	end

	return merged, had_func
end
return M
