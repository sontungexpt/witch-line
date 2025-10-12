local vim, type, ipairs, rawset, require = vim, type, ipairs, rawset, require
local o = vim.o

local Statusline = require("witch-line.core.statusline")
local Event = require("witch-line.core.manager.event")
local Timer = require("witch-line.core.manager.timer")
local Component = require("witch-line.core.Component")
local Session = require("witch-line.core.Session")
local Manager = require("witch-line.core.manager")
local DepGraphKind = Manager.DepGraphKind

local M = {}

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

--- Update the style of a component if necessary. (Called internally by `update_component`.)
--- @param comp Component The component to update.
--- @param style CompStyle|nil The new style to apply. If nil, the style will be fetched from the component's configuration.
--- @param session_id SessionId The ID of the process to use for this update.
local function update_component_style(comp, style, session_id)
  --- Update style
  local style_updated, ref_comp = false, comp
  if style then
    style_updated = Component.update_style(comp, style, ref_comp, true)

    --- Sync style to session store
    --- This is make sure that the `use_style` hooks always get the latest style
    local store = Session.get_store(session_id, "style")
    if store then
      store[comp.id] = style
    end
  else
    style, ref_comp = Manager.lookup_ref_value(comp, "style", session_id, {})
    if style then
      style_updated = Component.update_style(comp, style, ref_comp)
    end
  end

  local indices = comp._indices
  --- @cast indices number[]
  Statusline.set_value_highlight(indices, comp._hl_name, style_updated)

  --- WARN: Can not do sorter like this
  --- ```lua
  --- Statusline.set_side_value_highlight(
  ---   indices, -1, comp._left_hl_name, Component.update_side_style(comp, "left", style, style_updated, session_id)
  --- )
  --- ```
  --- Because lua evaluate the argument from left to right
  --- So the comp._left_hl_name may be missing if the update_side_style has not been called yet
  local left_style_updated = Component.update_side_style(comp, "left", style, style_updated, session_id)
  Statusline.set_side_value_highlight(
    indices, "left", comp._left_hl_name, left_style_updated
  )

  local right_style_updated = Component.update_side_style(comp, "right", style, style_updated, session_id)
  Statusline.set_side_value_highlight(
    indices, "right", comp._right_hl_name, right_style_updated
  )
end

--- Update a component and its value in the statusline.
--- @param comp Component The component to update.
--- @param session_id SessionId The ID of the process to use for this update.
--- @return boolean hidden True if the component is hidden after the update, false otherwise.
local function update_component(comp, session_id)
	-- It's just a abstract component then no need to really update
	if comp.inherit and not Component.has_parent(comp) then
		local parent = Manager.get_comp(comp.inherit)
		if parent then
			Component.inherit_parent(comp, parent)
		end
	end


	Component.emit_pre_update(comp, session_id)

	--- This part is manage by DepStoreKey.Display so we don't need to reference to the field of other component
	local min_screen_width = Component.min_screen_width(comp, session_id)

	local hidden = min_screen_width and o.columns < min_screen_width
    or Component.hidden(comp, session_id)

	if hidden then
		hide_component(comp)
  else
    local value, style = Component.evaluate(comp, session_id)
    local indices = comp._indices

    -- A abstract component will not have indices
    -- It's just call the update function for other purpose and we not affect to the statusline
    -- So we just ignore it even the value is empty string
    if indices then
      if value == "" then
        hide_component(comp)
        hidden = true
      else
        update_component_style(comp, style, session_id)

        --- Update statusline value
        Statusline.set_value(indices, value)
        Statusline.set_side_value(indices, "left", Component.evaluate_side(comp, "left", session_id))
        if comp.on_click then
          Statusline.set_click_handler(indices, Component.register_click_handler(comp))
        end

        rawset(comp, "_hidden", false) -- Reset hidden state
      end
    end
  end

	Component.emit_post_update(comp, session_id)
	return hidden
end
M.update_component = update_component

--- Update a component and its dependencies.
--- @param comp Component The component to update.
--- @param session_id SessionId The ID of the process to use for this update.
--- @param dep_graph_kind DepGraphKind|DepGraphKind[]|nil Optional. The store to use for dependencies. Defaults to { EventStore.Timer, EventStore.Event}
--- @param seen table<CompId, true>|nil Optional. A table to keep track of already seen components to avoid infinite recursion.
function M.update_comp_graph(comp, session_id, dep_graph_kind, seen)
	seen = seen or {}

	local id = comp.id
	if seen[id] then
		return -- Avoid infinite recursion
	end

	-- Always non nil
	---@cast id CompId
	seen[id] = true

	local hidden = update_component(comp, session_id)

	--- Check if component is loaded and should be render and affect to dependents
	--- If it's not load. It's just the abstract component and we don't care about updated value of it. The function update is just call for update something for abstract component
	if hidden then
		for dep_id, dep_comp in Manager.iterate_dependents(DepGraphKind.Visible, id) do
			seen[dep_id] = true
			hide_component(dep_comp)
		end
	end

 if type(dep_graph_kind) ~= "table" then
		dep_graph_kind = { dep_graph_kind }
	end

	for _, store_id in ipairs(dep_graph_kind) do
		for dep_id, dep_comp in Manager.iterate_dependents(store_id, id) do
			if not seen[dep_id] then
				M.update_comp_graph(dep_comp, session_id, dep_graph_kind, seen)
			end
		end
	end
end

--- Refresh a component and its dependencies in the next session.
--- @param comp Component The component to refresh.
--- @param dep_graph_kind DepGraphKind|DepGraphKind[]|nil Optional. The store to use for dependencies. Defaults to { EventStore.Event, EventStore.Timer }
--- @param seen table<CompId, true>|nil Optional. A table to keep track of already seen components to avoid infinite recursion. Defaults to an empty table.
M.refresh_component_graph = function(comp, dep_graph_kind, seen)
	require("witch-line.core.Session").with_session(function(sid)
		M.update_comp_graph(comp, sid, dep_graph_kind or {
      DepGraphKind.Event,
      DepGraphKind.Timer,
    }, seen)
		Statusline.render()
	end)
end


--- Update multiple components by their IDs.
--- @param ids CompId[] The IDs of the components to update.
--- @param session_id SessionId The ID of the process to use for this update.
--- @param dep_graph_kind DepGraphKind|DepGraphKind[]|nil Optional. The store to use for dependencies. Defaults to { EventStore.Event, EventStore.Timer}
--- @param seen table<CompId, true>|nil Optional. A table to keep track of already seen components to avoid infinite recursion.
M.update_comp_graph_by_ids = function(ids, session_id, dep_graph_kind, seen)
	seen = seen or {}
	for _, id in ipairs(ids) do
		if not seen[id] then
			local comp = Manager.get_comp(id)
			if comp then
				M.update_comp_graph(comp, session_id, dep_graph_kind, seen)
			end
		end
	end
end

--- Link dependencies for a component based on its ref and inherit fields.
--- @param comp Component The component to link dependencies for.
local function bind_dependencies(comp)
	local link_ref_field = Manager.link_ref_field
	local ref = comp.ref

	if type(ref) == "table" then
		if ref.events then
			link_ref_field(comp, ref.events, DepGraphKind.Event)
		end

		if ref.user_events then
			link_ref_field(comp, ref.user_events, DepGraphKind.Event)
		end

		if ref.timing then
			link_ref_field(comp, ref.timing, DepGraphKind.Timer)
		end

		if ref.hidden then
			link_ref_field(comp, ref.hidden, DepGraphKind.Visible)
		end

		if ref.min_screen_width then
			link_ref_field(comp, ref.min_screen_width, DepGraphKind.Visible)
		end
	end

	local inherit = comp.inherit
	if inherit then
		link_ref_field(comp, inherit, DepGraphKind.Event)
		link_ref_field(comp, inherit, DepGraphKind.Timer)
		link_ref_field(comp, inherit, DepGraphKind.Visible)
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
	for dep_id in Manager.iterate_all_dependency_ids(comp.id) do
		if not Manager.is_existed(dep_id) then
			local c = Component.require_by_id(dep_id)
			if c then
				M.register_abstract_component(c)
			end
		end
	end
	local ref = comp.ref
	if type(ref) == "table" then
		local dependency_ids = {}
		dependency_ids[#dependency_ids + 1] = ref.context
		dependency_ids[#dependency_ids + 1] = ref.static
		dependency_ids[#dependency_ids + 1] = ref.style
		for _, dep_id in ipairs(dependency_ids) do
			if not Manager.is_existed(dep_id) then
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
		local id = Manager.register(comp)

		if comp.init then
			Manager.queue_initialization(id)
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

		if comp.lazy == false then
			Manager.mark_emergency(id)
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
		local c = Component.require_by_id(comp)
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
					c = Component.require_by_id(c)
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
		M.update_comp_graph_by_ids(ids, session_id, DepGraphKind.Event, {})
		Statusline.render()
	end)

	Timer.on_timer_trigger(function(session_id, ids)
		M.update_comp_graph_by_ids(ids, session_id, DepGraphKind.Timer, {})
		Statusline.render()
	end)

	Session.with_session(function(sid)
		for _, comp in Manager.iter_pending_init_components() do
      Component.emit_init(comp, sid)
		end
		M.update_comp_graph_by_ids(Manager.get_emergency_ids(), sid, {
			DepGraphKind.Event,
			DepGraphKind.Timer,
		}, {})
		Statusline.render()
	end)
end

return M
