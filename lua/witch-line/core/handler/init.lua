local vim, type, ipairs, rawset, require = vim, type, ipairs, rawset, require

local Timer = require("witch-line.core.handler.timer")
local Event = require("witch-line.core.handler.event")
local Statusline = require("witch-line.core.statusline")
local CompManager = require("witch-line.core.CompManager")
local Component = require("witch-line.core.Component")

local M = {}

---@enum DepStoreKey
local DepStoreKey = {
	Display = 1,
	Event = 2,
	Timer = 4,
}

M.DepStoreKey = DepStoreKey


--- Clear the value of a component in the statusline.
--- @param comp Component The component to clear.
local hide_component = function(comp)
	local indices = comp._indices
	-- A abstract component may be not have _indices key
	if not indices then
		return
	end

	Statusline.hide_segment(indices)
	rawset(comp, "_hidden", true) -- Mark as hidden
end


--- Update the style of a component if necessary.
--- @param comp Component The component to update.
--- @param style CompStyle|nil The new style to apply. If nil, the style will be fetched from the component's configuration.
--- @param session_id SessionId The ID of the process to use for this update.
--- @param ctx table The context for evaluating the component.
--- @param static table The static data for evaluating the component.
local function update_component_style(comp, style, session_id, ctx, static)
  --- Update style
  local style_updated, ref_comp = false, comp
  if style then
    style_updated = Component.update_style(comp, style, ref_comp, true)
  else
    style, ref_comp = CompManager.get_style(comp, session_id, ctx, static)
    if style then
      style_updated = Component.update_style(comp, style, ref_comp)
    end
  end
  local indices = comp._indices
  --- @cast indices number[]
  Statusline.set_value_highlight(indices, comp._hl_name, style_updated)

  Statusline.set_side_value_highlight(
    indices, -1, comp._left_hl_name,
    Component.update_side_style(comp, "left", style, style_updated, session_id, ctx, static)
  )

  Statusline.set_side_value_highlight(
    indices, 1, comp._right_hl_name,
    Component.update_side_style(comp, "right", style, style_updated, session_id, ctx, static)
  )
end

--- Update a component and its value in the statusline.
--- @param comp Component The component to update.
--- @param session_id SessionId The ID of the process to use for this update.
--- @return string|nil updated_value  If string and non-empty then the component is visible and updated, if empty string then the component is hidden, if nil then the component is abstract and not rendered directly.
local function update_component(comp, session_id)
	-- It's just a abstract component then no need to really update
	if comp.inherit and not Component.has_parent(comp) then
		local parent = CompManager.get_comp(comp.inherit)
		if parent then
			Component.inherit_parent(comp, parent)
		end
	end

	local static = CompManager.get_static(comp)
	local ctx = CompManager.get_context(comp, session_id, static)

	Component.emit_pre_update(comp, session_id, ctx, static)

	--- This part is manage by DepStoreKey.Display so we don't need to reference to the field of other component
	local min_screen_width = Component.min_screen_width(comp, session_id, ctx, static)
	local hidden = min_screen_width and vim.o.columns < min_screen_width
		or Component.hidden(comp, session_id, ctx, static)

	local value, style = "", nil

	if hidden then
		hide_component(comp)
	else
		value, style = Component.evaluate(comp, session_id, ctx, static)
		if value == "" then
			hide_component(comp)
		else
			local indices = comp._indices

			-- A abstract component may be not have _indices key
			if indices then
        update_component_style(comp, style, session_id, ctx, static)

        --- Update value
				Statusline.set_value(indices, value)

        local left, right = comp.left, comp.right
        if type(left) == "function" then
          Statusline.set_side_value(
            indices, -1,
            Component.resolve_side_fn(comp, left, session_id, ctx, static)
          )
        end
        if type(right) == "function" then
          Statusline.set_side_value(
            indices, 1,
            Component.resolve_side_fn(comp, right, session_id, ctx, static)
          )
        end

        if comp.on_click then
          local click_handler = Component.register_click_handler(comp)
          if click_handler ~= "" then
            Statusline.bulk_set_click_handler(indices, click_handler)
          end
        end

				rawset(comp, "_hidden", false) -- Reset hidden state
			end
		end
	end

	Component.emit_post_update(comp, session_id, ctx, static)
	return value
end
M.update_component = update_component

--- Update a component and its dependencies.
--- @param comp Component The component to update.
--- @param session_id SessionId The ID of the process to use for this update.
--- @param dep_store_ids DepGraphId|DepGraphId[]|nil Optional. The store to use for dependencies. Defaults to { EventStore.Timer, EventStore.Event}
--- @param seen table<CompId, true>|nil Optional. A table to keep track of already seen components to avoid infinite recursion.
function M.update_comp_graph(comp, session_id, dep_store_ids, seen)
	dep_store_ids = dep_store_ids or {
		DepStoreKey.Event,
		DepStoreKey.Timer,
	}
	seen = seen or {}

	local id = comp.id
	if seen[id] then
		return -- Avoid infinite recursion
	end

	-- Always non nil
	---@cast id CompId
	seen[id] = true

	local updated_value = update_component(comp, session_id)

	--- Check if component is loaded and should be render and affect to dependents
	--- If it's not load. It's just the abstract component and we don't care about updated value of it. The function update is just call for update something for abstract component
	if comp._loaded and updated_value == "" then
		for dep_id, dep_comp in CompManager.iterate_dependents(DepStoreKey.Display, id) do
			seen[dep_id] = true
			hide_component(dep_comp)
		end
	end

	if type(dep_store_ids) ~= "table" then
		dep_store_ids = { dep_store_ids }
	end
	for _, ds_id in ipairs(dep_store_ids) do
		for dep_id, dep_comp in CompManager.iterate_dependents(ds_id, id) do
			if not seen[dep_id] then
				M.update_comp_graph(dep_comp, session_id, dep_store_ids, seen)
			end
		end
	end
end

--- Refresh a component and its dependencies in the next session.
--- @param comp Component The component to refresh.
--- @param dep_store_ids DepGraphId|DepGraphId[]|nil Optional. The store to use for dependencies. Defaults to { EventStore.Event, EventStore.Timer }
--- @param seen table<CompId, true>|nil Optional. A table to keep track of already seen components to avoid infinite recursion. Defaults to an empty table.
M.refresh_component_graph = function(comp, dep_store_ids, seen)
	require("witch-line.core.Session").run_once(function(session_id)
		M.update_comp_graph(comp, session_id, dep_store_ids, seen)
		Statusline.render()
	end)
end


--- Update multiple components by their IDs.
--- @param ids CompId[] The IDs of the components to update.
--- @param session_id SessionId The ID of the process to use for this update.
--- @param dep_store_ids DepGraphId|DepGraphId[]|nil Optional. The store to use for dependencies. Defaults to { EventStore.Event, EventStore.Timer}
--- @param seen table<CompId, true>|nil Optional. A table to keep track of already seen components to avoid infinite recursion.
M.update_comp_graph_by_ids = function(ids, session_id, dep_store_ids, seen)
	seen = seen or {}
	for _, id in ipairs(ids) do
		if not seen[id] then
			local comp = CompManager.get_comp(id)
			if comp then
				M.update_comp_graph(comp, session_id, dep_store_ids, seen)
			end
		end
	end
end

--- Link dependencies for a component based on its ref and inherit fields.
--- @param comp Component The component to link dependencies for.
local function bind_dependencies(comp)
	local link_ref_field = CompManager.link_ref_field
	local ref = comp.ref

	if type(ref) == "table" then
		if ref.events then
			link_ref_field(comp, ref.events, DepStoreKey.Event)
		end

		if ref.user_events then
			link_ref_field(comp, ref.user_events, DepStoreKey.Event)
		end

		if ref.timing then
			link_ref_field(comp, ref.timing, DepStoreKey.Timer)
		end

		if ref.hidden then
			link_ref_field(comp, ref.hidden, DepStoreKey.Display)
		end

		if ref.min_screen_width then
			link_ref_field(comp, ref.min_screen_width, DepStoreKey.Display)
		end
	end

	local inherit = comp.inherit
	if inherit then
		link_ref_field(comp, inherit, DepStoreKey.Event)
		link_ref_field(comp, inherit, DepStoreKey.Timer)
		link_ref_field(comp, inherit, DepStoreKey.Display)
	end
end

--- Register conditions for a component.
--- @param comp Component The component to register conditions for.
local function bind_update_conditions(comp)
	if comp.timing then
		Timer.register_timer(comp)
	end

	if comp.events then
		Event.register_events(comp, "events")
	end

	if comp.min_screen_width then
		Event.register_vim_resized(comp)
	end

	if comp.user_events then
		Event.register_events(comp, "user_events")
	end
end

--- Pull missing dependencies for a component based on its ref and inherit fields.
--- @param comp Component The component to pull dependencies for.
local function pull_missing_dependencies(comp)
	-- Pull missing dependencies from the component's ref field
	for dep_id in CompManager.iterate_all_dependency_ids(comp.id) do
		if not CompManager.is_existed(dep_id) then
			local c = Component.require_by_id(dep_id)
			if c then
				M.register_abstract_component(c)
			end
		end
	end
	local ref = comp.ref
	if type(ref) == "table" then
		local dependency_ids                = {}
		dependency_ids[#dependency_ids + 1] = ref.context
		dependency_ids[#dependency_ids + 1] = ref.static
		dependency_ids[#dependency_ids + 1] = ref.style
		for _, dep_id in ipairs(dependency_ids) do
			if not CompManager.is_existed(dep_id) then
				local c = Component.require_by_id(dep_id)
				if c then
					M.register_abstract_component(c)
				end
			end
		end
	end
end

--- Register an abstract component that is not directly rendered in the statusline.
--- These components can be used as dependencies for other components.
--- @param comp Component The abstract component to register.
--- @return CompId The ID of the registered component.
function M.register_abstract_component(comp)
	if not comp._abstract then
		local id = CompManager.register(comp)

		if comp.init then
			CompManager.queue_initialization(id)
		end

		bind_update_conditions(comp)
		bind_dependencies(comp)
		pull_missing_dependencies(comp)

		rawset(comp, "_abstract", true)
		return id
	end
	return comp.id
end

--- Build statusline indices for a component.
--- @param comp Component The component to build indices for.
local function build_indices(comp)
  -- Why not support left and right indpendently?
  -- Because the update id the main part   --
  -- The left and right are just the decoration of the main part
  -- So if the main part is not renderable then the left and right are not renderable too
  -- If really need the left and right we just add them as a separate component
	local update = comp.update
	if not update then
		return
	end

  local idx = Statusline.push("")
  local left, right = comp.left, comp.right
  if type(left) == "string" then
    Statusline.set_side_value(idx, -1, left)
  end
  if type(right) == "string" then
    Statusline.set_side_value(idx, 1, right)
  end

	local indices = comp._indices
	if not indices then
		rawset(comp, "_indices", { idx })
	else
		indices[#indices + 1] = idx
	end

  local flexible = comp.flexible
	if flexible then
		Statusline.track_flexible(idx, flexible)
	end
end
--- Register a component node, which may include nested components.
--- @param comp Component The component to register.
--- @param parent_id CompId|nil The ID of the parent component, if any.
--- @return Component The registered component. Nil if registration failed.
local function register_component(comp, parent_id)
	-- Avoid recursion for already loaded components
	if comp._loaded then
		build_indices(comp)
		return comp
	end


	-- Example for this case: comp = {
	--  [0] = "mode",
	--  events = { "VimLeavePre" },
	-- }
	-- And the mode component is {
	--   id = "mode",
	--   events = { "ModeChanged" },
	--   update = function() ... end,
	-- 	...}
	-- So the final component will be {
	--   id = "mode",
	--   events = { "VimLeavePre" },
	--   update = function() ... end,
	--   ...
	-- }
	-- If a component is made base on other component with some overrided fields
	local comp_path = comp[0]
	if type(comp_path) == "string" then
		local c = require("witch-line.core.Component").require(comp_path)
		-- If c is nil, assume that the user is trying to add the [0] field for other purpose
		-- so we just ignore it
		if c then
			comp = require("witch-line.core.Component").overrides(c, comp)
		end
	end

	-- If is a list it just a wrapper for a list components
	-- so we just register its children
	-- Example: { "MyComponent", { child1, child2, ... } }
	-- Example: { { child1, child2, ... } }
	-- Example: { child1, child2, ... }
	if not vim.islist(comp) then
		-- Set parent inheritance if applicable
		if parent_id and not comp.inherit then
			rawset(comp, "inherit", parent_id)
		end

		-- Every component is treat as an abstract component
		-- The difference is that abstract components are not rendered directly
		-- but they can be dependencies of other components
		-- while normal components are rendered in the statusline
		-- This allows users to define components that are not rendered directly
		-- but can be used as dependencies for other components

		-- Abstract registration
		local id = M.register_abstract_component(comp)

    -- When a update type is a string it means that the component is always renderable as lazy is false
    -- So we need to mark it as emergency
		if type(comp.update) == "string" or comp.lazy == false then
			CompManager.mark_emergency(id)
		end
		build_indices(comp)
		rawset(comp, "_loaded", true) -- Mark the component as loaded
	end

	return comp
end

--- Register a literal string component in the statusline.
--- @param comp LiteralComponent The string component to register.
local function register_literal_comp(comp)
	if comp ~= "" then
		Statusline.push(comp,true)
	end
	return comp
end

--- Register a component by its type.
--- @param comp Component The component to register.
--- @param parent_id CompId|nil The ID of the parent component, if any.
--- @return Component|LiteralComponent|nil comp The registered component. Nil if registration failed.
function M.register_combined_component(comp, parent_id)
	local kind = type(comp)
	if kind == "string" then
		local c = Component.require(comp)
		if not c then
			return register_literal_comp(comp)
		end
		comp = register_component(c, parent_id)
	elseif kind == "table" and next(comp) then
		comp = register_component(comp, parent_id)
	else
		-- Invalid component type
		return nil
	end

	-- If the component is not a literal component then it will drop by here
	for i, child in ipairs(comp) do
		M.register_combined_component(child, comp.id)
		rawset(comp, i, nil) -- Remove child to avoid duplication
	end
	return comp
end

--- Setup the statusline with the given configurations.
--- @param user_configs UserConfig  The configurations for the statusline.
--- @param DataAccessor Cache.DataAccessor|nil The accessor to cache data if had cache ortherwise nil
M.setup = function(user_configs, DataAccessor)
	if not DataAccessor then
		local abstract = user_configs.abstract
		if type(abstract) == "table" then
			for i = 1, #abstract do
				local c = abstract[i]
				if type(c) == "string" then
					---@diagnostic disable-next-line
					c = Component.require(c)
				end
				if type(c) == "table" and c.id then
					M.register_abstract_component(c)
				else
					error("Abstract component must be a component with an 'id' field: " .. tostring(c))
				end
			end
		end

		local comps = user_configs.components
		for i = 1, #comps do
			M.register_combined_component(comps[i])
		end
	end

	Event.on_event(function(session_id, ids)
		M.update_comp_graph_by_ids(ids, session_id, DepStoreKey.Event, {})
		Statusline.render()
	end)

	Timer.on_timer_trigger(function(session_id, ids)
		M.update_comp_graph_by_ids(ids, session_id, DepStoreKey.Timer, {})
		Statusline.render()
	end)

	local Session = require("witch-line.core.Session")
	Session.run_once(function(session_id)
		for _, comp in CompManager.iter_pending_init_components() do
			local static = CompManager.get_static(comp)
			local context = CompManager.get_context(comp, session_id, static)
			comp.init(comp, context, static, session_id)
		end
		M.update_comp_graph_by_ids(CompManager.get_emergency_ids(), session_id, {
			DepStoreKey.Event,
			DepStoreKey.Timer,
		}, {})
		Statusline.render()
	end)
end

return M
