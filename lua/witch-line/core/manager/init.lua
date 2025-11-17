local type = type
local Component = require("witch-line.core.Component")
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
local ManagedComps = {}

--- @type CompId[]
local InitializePendingIds = {}

--- Queue the `init` method of a component to be called in the next render cycle.
--- @param id CompId The ID of the component to initialize.
M.queue_initialization = function(id)
	InitializePendingIds[#InitializePendingIds + 1] = id
end

--- Iterate over the queue of components pending initialization (FIFO).
--- @return fun(): CompId|nil, ManagedComponent iterator A function that returns the next component ID in the queue
M.iter_pending_init_components = function()
	local index = 0
	return function()
		index = index + 1
		local id = InitializePendingIds[index]
		if not id then
			return nil
		end
		return id, ManagedComps[id]
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
--- @return fun(): CompId|, ManagedComponent iterator A function that returns the next component ID in the queue
M.iter_emergency_components = function()
	local index = 0
	return function()
		index = index + 1
		local id = EmergencyIds[index]
		if not id then
			return nil
		end
		return id, ManagedComps[id]
	end
end

--- The function to be called before Vim exits.
--- @param CacheDataAccessor Cache.DataAccessor The cache module to use for saving the stores.
M.on_vim_leave_pre = function(CacheDataAccessor)
	for _, comp in pairs(ManagedComps) do
		Component.format_state_before_cache(comp)
		require("witch-line.utils.persist").serialize_function(comp)
	end
	CacheDataAccessor.set("CachedComps", ManagedComps)
	CacheDataAccessor.set("DepGraph", DepGraphRegistry)
	CacheDataAccessor.set("Urgents", EmergencyIds)
	CacheDataAccessor.set("PendingInit", InitializePendingIds)
end

--- Load the cache for components and dependency stores.
--- @param CacheDataAccessor Cache.DataAccessor The cache module to use for loading the stores.
--- @return function undo Function to restore the previous state of Comps and DepGraph.
M.load_cache = function(CacheDataAccessor)
	local before_dep_store, before_pending_inits, before_urgents = DepGraphRegistry, InitializePendingIds, EmergencyIds
	local CachedComps = CacheDataAccessor.get("CachedComps")

	local Persist = require("witch-line.utils.persist")
	if CachedComps then
		setmetatable(ManagedComps, {
			__index = function(t, k)
				local comp = CachedComps[k]
				if not comp then
					return nil
				end
				comp = Persist.deserialize_function(comp)
				t[k] = comp
				return comp
			end,
		})
	end

	DepGraphRegistry = CacheDataAccessor.get("DepGraph") or DepGraphRegistry
	InitializePendingIds = CacheDataAccessor.get("PendingInit") or InitializePendingIds
	EmergencyIds = CacheDataAccessor.get("Urgents") or EmergencyIds
	return function()
		ManagedComps = {}
		DepGraphRegistry = before_dep_store
		InitializePendingIds = before_pending_inits
		EmergencyIds = before_urgents
	end
end

--- Iterate over all registered components.
--- @return fun(): CompId, ManagedComponent iterator Iterator over all components.
--- @return ManagedComponent[] comps The list of all components.
M.iterate_comps = function()
	return pairs(ManagedComps)
end

--- Get a list of all registered components.
--- @return ManagedComponent[] The list of all components.
M.get_list_comps = function()
	return vim.tbl_values(ManagedComps)
end

--- Register a component with the component manager.
--- @param comp ManagedComponent The component to register.
--- @return ManagedComponent comp The registered component.
M.register = function(comp)
	local id = Component.setup(comp)
	local managed = ManagedComps[id]
	if managed then
		return managed
	end
	ManagedComps[id] = comp
	return comp
end

--- Check if a component with the given ID exists.
--- @param id CompId ID to check.
--- @return boolean existed True if the component exists, false otherwise.
M.is_existed = function(id)
	return ManagedComps[id] ~= nil
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
--- @return fun()|fun(): CompId, ManagedComponent An iterator function that returns the next dependent ID and its component.
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
			return curr_id, ManagedComps[curr_id]
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
--- @param comp ManagedComponent The component to add the dependency for.
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
--- @return ManagedComponent|nil comp The component with the given ID, or nil if not found.
M.get_comp = function(id)
	return id and ManagedComps[id]
end

--- Inspect the current state of the component manager.
--- @param target "dep_store"|"comps"|nil The key to inspect.
M.inspect = function(target)
	local notifier = require("witch-line.utils.notifier")
	if target == "dep_store" then
		notifier.info("Inspecting DepGraph\n" .. vim.inspect(DepGraphRegistry or {}))
	elseif target == "comps" then
		notifier.info("Inspecting Comps\n" .. vim.inspect(ManagedComps or {}))
	else
		notifier.info("Inspecting dep_store and comps: \n" .. vim.inspect({
			DepGraph = DepGraphRegistry or {},
			Comps = ManagedComps or {},
		}))
	end
end

do
	local VIM_NIL = vim.NIL
	--- @type table<string, table<CompId, vim.NIL|{[1]: any, [2]: ManagedComponent, [3]: ManagedComponent|nil}>>
	local raw_cache = {}

	--- Internal recursive lookup for a raw (unevaluated) key value within a component.
	---
	--- This function performs a deep search across:
	---   1. The component's own fields.
	---   2. Its inheritance chain (`inherit`).
	---   3. Its reference chain (`ref`).
	---
	--- It stops at the first non-nil value found, returning the value along
	--- with information about where it came from.
	---
	--- Results are cached per `(key, component.id)` to avoid redundant recursion.
	--- Nil results are represented using `vim.NIL` to distinguish between
	--- “not yet cached” and “cached as nil”.
	---
	--- @param comp ManagedComponent                The component currently being inspected.
	--- @param key string                           The key name to look up.
	--- @param seen table<CompId, boolean>          Tracks visited components to prevent infinite recursion.
	--- @return vim.NIL|{[1]: any, [2]: ManagedComponent, [3]: ManagedComponent|nil} result
	---   • `[1]` — The raw value found (static or unevaluated function).
	---   • `[2]` — The origin component where the value is defined.
	---   • `[3]` — The deepest referencecomponent, or nil if not found.
	local function find_raw_value(comp, key, seen)
		local cid = comp.id
		if seen[cid] then
			return VIM_NIL
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

		-- Inherit from parent
		local inherit_id = comp.inherit
		if inherit_id then
			local parent = ManagedComps[inherit_id]
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

		-- Reference chain lookup
		local ref = comp.ref
		if type(ref) == "table" then
			local ref_id = ref[key]
			if ref_id then
				local ref_comp = ManagedComps[ref_id]
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

		if key_cache then
			key_cache[cid] = VIM_NIL
		else
			raw_cache[key] = { [cid] = VIM_NIL }
		end
		return VIM_NIL
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
	--- @param seen table<CompId, boolean>|nil  Optional recursionl guard
	--- @return nil|any raw_value The raw value found (static or unevaluated function).
	--- @return nil|ManagedComponent origin The origin component where the value is defined.
	--- @return nil|ManagedComponent drc The deepest reference component, or nil if not found.
	M.lookup_plain_value = function(comp, key, seen)
		local result = find_raw_value(comp, key, seen or {})
		if result == VIM_NIL then
			return nil, nil, nil
		end
		return result[1], result[2], result[3]
	end

	--- Retrieve only the context component for a given key.
	---
	--- This returns the *final component* in the inheritance or reference chain
	--- where the key’s value originated — useful for context-based evaluation.
	---
	--- @param comp ManagedComponent            The component to start lookup from.
	--- @param key string                       The key name to look up.
	--- @param seen table<CompId, boolean>|nil  Optional recursion guard.
	--- @return ManagedComponent|nil context    The deepest referencecomponent, or nil if not found.
	M.deepest_reference_component = function(comp, key, seen)
		local r = find_raw_value(comp, key, seen or {})
		return r ~= VIM_NIL and r[3] or nil
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
	--- @return nil|any raw_value The raw value found (static or unevaluated function).
	--- @return nil|ManagedComponent origin The origin component where the value is defined.
	--- @return nil|ManagedComponent drc The deepest reference component, or nil if not found.
	--- @return boolean dynamic True if raw_value is function.
	M.lookup_dynamic_value = function(comp, key, sid, seen, ...)
		local cid = comp.id
		if seen and seen[cid] then
			return nil, nil, nil, false
		end
		-- Cache evaluated (resolved) value
		local cache = get_session_store(sid, key)
		---@cast cache table<CompId, {[1]: any, [2]: ManagedComponent, [3]: ManagedComponent|nil, [4]: boolean|nil}>
		local result = cache and cache[cid]
		if result then
			return result[1], result[2], result[3], result[4] or false
		end

		---@diagnostic disable-next-line: cast-local-type
		result = find_raw_value(comp, key, seen or {})
		if result == VIM_NIL then
			return nil, nil, nil, false
		end

		local value, origin, drc = result[1], result[2], result[3]
		local dynamic = type(value) == "function"
		if dynamic then
			-- For inherited functions, use the origin component as context;
			-- for reference/local ones, use the provider component.
			local ctx_comp = drc or comp
			if Component.should_pass_sid(key) then
				value = value(ctx_comp, sid, ...)
			else
				value = value(ctx_comp, ...)
			end
			result = { value, origin, drc, dynamic }
		end

		-- Cache final evaluated value for this session
		if cache then
			---@cast result {[1]: any, [2]: ManagedComponent, [3]: ManagedComponent|nil, [4]: boolean|nil}>
			cache[cid] = result
		else
			new_session_store(sid, key, { [cid] = result })
		end

		return value, origin, drc, dynamic
	end
end

do
	--- @type table<string, table<CompId, {[1]: any,[2]: integer}>>
	local inherited_cache = {}
	local lookup_plain_value, lookup_dynamic_value = M.lookup_plain_value, M.lookup_dynamic_value

	--- Resolve and merge inherited values for a given component key (static version).
	---
	--- This function performs a **static inheritance resolution**, meaning it only
	--- processes plain (non-function) values and does not depend on runtime or session state.
	---
	--- ### Behavior
	--- - The function starts from the given component (`comp`) and traverses upward
	---   through its `inherit` chain.
	--- - For each level, it retrieves the raw stored value for the specified `key`
	---   (without evaluating functions) and merges them using the provided
	---   `merge(a, b)` function.
	--- - If `self_val` is provided, it **replaces** the component’s own value
	---   for `key` — i.e., it is treated as the value of the current component
	---   before merging with its ancestors.
	---
	--- ### Caching Strategy
	--- - Results are cached per-component and per-key in `inherited_cache` to avoid
	---   redundant traversal.
	--- - Cached results are always static and independent of runtime/session data.
	---
	--- ### Notes
	--- - This is the static counterpart of `M.dynamic_inherit()`.
	--- - Suitable for configuration-style data that is fixed at definition time
	---   and does not depend on session context or function evaluation.
	---
	--- @param comp ManagedComponent The component whose key should be resolved.
	--- @param key string The key name to resolve and merge.
	--- @param merge fun(a: any, b: any, chain_size: integer): any Function used to combine two values (`a` and `b`) in inheritance order.
	--- - `a`          → the previously merged value (or the component’s own value at first)
	--- - `b`          → the parent component’s value being merged
	--- - `chain_size` → the total number of parents in the inheritance chain
	--- Must return the merged result.
	--- @param self_val any|nil Optional value to replace the component’s own key before merging.
	--- @return any val The final merged (static) result.
	--- @return integer chain_size The total number of parents in the inheritance chain
	function M.plain_inherit(comp, key, merge, self_val)
		local cid = comp.id

		local key_cache
		-- We nerver cache in this case so no need to check cache
		if not self_val then
			key_cache = inherited_cache[key]
			local cached = key_cache and key_cache[cid]
			if cached then
				return cached[1], cached[2]
			end
		end

		local seen = {}
		local val = self_val or lookup_plain_value(comp, key, seen)
		local chain, n, pid, pval = {}, 0, comp.inherit, nil
		while pid do
			local c = ManagedComps[pid]
			if not c then
				break
			end
			pval = lookup_plain_value(c, key, seen)
			if pval then
				n = n + 1
				chain[n] = pval
			end
			pid = c.inherit
		end

		for i = 1, n do
			val = merge(val, chain[i], n)
		end

		if not self_val then -- this is always change so never cache
			if key_cache then
				key_cache[cid] = { val, n }
			else
				inherited_cache[key] = { [cid] = { val, n } }
			end
		end

		return val, n
	end

	--- Resolve and merge inherited values for a given component key (dynamic version).
	---
	--- This function performs a **dynamic inheritance resolution**, meaning it can evaluate
	--- function-type values and use session-specific data (`sid`). It walks through the entire
	--- `inherit` chain of the component, retrieving and merging values from parent components
	--- using a provided `merge` function.
	---
	--- ### Behavior
	--- - The function starts from the current component and traverses its entire `inherit` hierarchy.
	--- - For each level, it calls `M.lookup_dynamic_value()` to retrieve the resolved (and possibly
	---   evaluated) value for the given key.
	--- - If `self_val` is provided, it **replaces** the component’s own value
	---   for `key` — i.e., it is treated as the value of the current component
	---   before merging with its ancestors.
	--- - All values are merged progressively using the provided `merge(a, b)` function, in
	---   **inheritance order** (child → parent → ...).
	---
	--- ### Caching Strategy
	--- - **Static results** (non-function, context-independent) are stored globally in `inherited_cache`.
	--- - **Dynamic results** (function-derived, session-dependent) are cached per-session using
	---   `get_session_store()` / `new_session_store()`.
	--- - This ensures efficient reuse between calls and avoids unnecessary recomputation.
	---
	--- ### Notes
	--- - A value is considered **dynamic** if any value in the inheritance chain is derived
	---   from a function or requires session-based evaluation.
	--- - Returns both the final merged result and a boolean indicating whether the value
	---   depends on runtime/session context.
	--- - The optional `initial_val` is used **instead of** the value resolved from the component itself.
	---
	--- @param comp ManagedComponent The component whose key should be resolved.
	--- @param key string The key name to resolve and merge.
	--- @param merge fun(a: any, b: any, chain_size: integer): any Function used to combine two values (`a` and `b`) in inheritance order.
	--- - `a`          → the previously merged value (or the component’s own value at first)
	--- - `b`          → the parent component’s value being merged
	--- - `chain_size` → the total number of parents in the inheritance chain
	--- Must return the merged result.
	--- @param self_val any|nil Optional value to replace the component’s own key before merging.
	--- @return any val The final merged (static) result.
	--- @return boolean dynamic Whether the result is dynamic (true if function-evaluated or session-based).
	--- @return integer chain_size The total number of parents in the inheritance chain
	function M.dynamic_inherit(comp, key, sid, merge, self_val)
		local cid = comp.id
		local key_cache

		--- We never cache in this case so no need to check cache
		if not self_val then
			key_cache = inherited_cache[key]
			local cached = key_cache and key_cache[cid]

			if cached then
				return cached[1], false, cached[2]
			end
		end

		local DYNAMIC_CAHCED_KEY = "inherited" .. key
		local dynamic_key_cache = get_session_store(sid, DYNAMIC_CAHCED_KEY)
		---@cast dynamic_key_cache table<CompId, {[1]: any, [2]: integer}>
		local cached = dynamic_key_cache and dynamic_key_cache[cid]
		if cached then
			return cached[1], false, cached[2]
		end
		local val, dynamic, seen = self_val, false, {}
		if not val then
			val, _, _, dynamic = lookup_dynamic_value(comp, key, sid, seen)
		end

		local chain, n, pid, pval, pdynamic = {}, 0, comp.inherit, nil, false
		while pid do
			local c = ManagedComps[pid]
			if not c then
				break
			end
			pval, _, _, pdynamic = lookup_dynamic_value(c, key, sid, seen)
			if pval then
				n = n + 1
				chain[n] = pval
				dynamic = dynamic or pdynamic
			end
			pid = c.inherit
		end

		for i = 1, n do
			val = merge(val, chain[i], n)
		end

		cached = { val, n }
		if dynamic then
			-- Cache final evaluated value for this session
			if dynamic_key_cache then
				dynamic_key_cache[cid] = cached
			else
				new_session_store(sid, DYNAMIC_CAHCED_KEY, { [cid] = cached })
			end
		elseif not self_val then -- this is always change so never cache
			if key_cache then
				key_cache[cid] = cached
			else
				inherited_cache[key] = { [cid] = cached }
			end
		end

		return val, dynamic or false, n
	end
end

return M
