local vim, type, ipairs, rawset, require = vim, type, ipairs, rawset, require
local o = vim.o

local Statusline = require("witch-line.core.statusline")
local Event = require("witch-line.core.manager.event")
local Timer = require("witch-line.core.manager.timer")
local Highlight = require("witch-line.core.highlight")
local Session = require("witch-line.core.Session")
local Manager = require("witch-line.core.manager")
local Component = require("witch-line.core.Component")
local DepGraphKind = Manager.DepGraphKind
local SepStyle = Component.SepStyle

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

--- Format the side value
--- @param val any the value of the side
--- @param is_func boolean|nil Flag indicate that is the side is a function or not
--- @return nil|string result String if valid, otherwise nil
local function format_side_value(val, is_func)
	-- Avoid non-string values if function-type
	if is_func then
		return type(val) ~= "string" and "" or val
	elseif type(val) ~= "string" then
		return nil
	end
	return val
end

--- Update or apply the highlight style of a component.
---
--- This function resolves a component’s `style` field (including inherited and
--- referenced styles), generates or reuses its highlight group name (`_hl_name`),
--- and applies the highlight definition through `Highlight.highlight()`.
---
--- Behavior:
--- 1. Uses `Manager.dynamic_inherit()` to compute the final merged `style` value,
---    combining local, inherited, and referenced styles with `Highlight.merge_hl()`.
--- 2. If the component already has a `_hl_name`:
---    - Reapplies the highlight if the style is dynamic (`force == true`)
---      or has been externally overridden (`style_overided` provided).
--- 3. If `_hl_name` is not set:
---    - Generates a new one via `Highlight.make_hl_name_from_id()`.
---    - If the component has parents (`pcount > 0`), assigns its own name.
---    - Otherwise, tries to reuse the deepest referenced component’s `_hl_name`
---      (if any), caching it for future lookups.
--- 4. Applies the resolved highlight style and updates the `_hl_name` cache.
---
--- @param comp Component          The component whose highlight style should be updated.
--- @param sid SessionId           The session ID used for dynamic style resolution and caching.
--- @param override_style CompStyle|nil Optional override style, applied before inheritance.
--- @return boolean updated        Whether the highlight was updated (`true`) or skipped (`false`).
--- @return CompStyle style        The resolved and applied highlight style.
local function update_comp_style(comp, sid, override_style)
	local style, force, pcount = Manager.dynamic_inherit(comp, "style", sid, Highlight.merge_hl, override_style)
	local hl_name = comp._hl_name
	if hl_name then
		if force or override_style then
			Highlight.highlight(hl_name, style)
			return true, style
		end
	else
		if pcount > 0 then
			hl_name = Highlight.make_hl_name_from_id(comp.id)
		else
			local ref_comp = Manager.deepest_reference_component(comp, "style")
			if ref_comp then
				hl_name = ref_comp._hl_name or Highlight.make_hl_name_from_id(ref_comp.id)
				rawset(ref_comp, "_hl_name", hl_name)
			else
				hl_name = Highlight.make_hl_name_from_id(comp.id)
			end
		end
		rawset(comp, "_hl_name", hl_name)
		Highlight.highlight(hl_name, style)
		return true, style
	end
	return false, style
end

--- Update and apply the highlight style for a component’s side (left or right).
---
--- This function determines and applies a side-specific highlight style
--- (e.g. separators between components in a statusline or UI block).
--- It reuses the main component style if possible or evaluates dynamic styles.
---
--- **Behavior:**
--- 1. If a custom highlight already exists and doesn’t need re-rendering, it returns early.
--- 2. If the side style is a function, it’s dynamically evaluated using `(comp, sid)`.
--- 3. If the side style is a numeric code (`SepStyle`), it derives a new highlight table
---    based on the main style:
---    - `SepFg`:  `{ fg = main_style.fg, bg = "NONE" }`
---    - `SepBg`:  `{ fg = main_style.bg, bg = "NONE" }`
---    - `Reverse`: `{ fg = main_style.bg, bg = main_style.fg }`
---    - `Inherited`: Inherit the component’s `_hl_name` directly.
---
--- **Return values:**
--- - `true`:  Style was updated and applied.
--- - `false`: No change was necessary or style was invalid.
---
--- @param comp Component The component whose side style should be updated.
--- @param sid SessionId The session identifier used for dynamic style evaluation.
--- @param side "left"|"right" The side to update.
--- @param main_style_updated boolean Whether the main style was recently updated (forces re-render).
--- @param main_style? CompStyle The component’s main style used as reference.
--- @return boolean updated Whether the side highlight was changed.
local function update_comp_side_style(comp, sid, side, main_style_updated, main_style)
	local side_style = comp[Component.style_field(side)] or SepStyle.SepBg

	local t = type(side_style)
	local hl_name_field = Component.hl_name_field(side)
	local hl_name = comp[hl_name_field]

	-- Return early if no need to update
	if
		not (
			hl_name == nil
			or t == "function"
			or (
				main_style_updated
				and t == "number"
				and (
					side_style == SepStyle.SepFg
					or side_style == SepStyle.SepBg
					or side_style == SepStyle.Reverse
					or side_style == SepStyle.Inherited
				)
			)
		)
	then
		return false
	end

	if t == "function" then
		side_style = side_style(comp, sid)
		t = type(side_style)
	end

	if t == "number" and main_style then
		if side_style == SepStyle.SepFg then
			---@diagnostic disable-next-line: cast-local-type
			side_style = {
				fg = main_style.fg,
				bg = "NONE",
			}
		elseif side_style == SepStyle.SepBg then
			---@diagnostic disable-next-line: cast-local-type
			side_style = {
				fg = main_style.bg,
				bg = "NONE",
			}
		elseif side_style == SepStyle.Reverse then
			---@diagnostic disable-next-line: cast-local-type
			side_style = {
				fg = main_style.bg,
				bg = main_style.fg,
			}
		elseif side_style == SepStyle.Inherited then
			rawset(comp, hl_name_field, comp._hl_name)
			return true
		else
			--- invalid styles
			return false
		end
	end
	-- Ensure highlight name exists and apply the new highlight
	hl_name = hl_name or Highlight.make_hl_name_from_id(comp.id) .. side
	rawset(comp, hl_name_field, hl_name)
	---@diagnostic disable-next-line: param-type-mismatch
	return Highlight.highlight(hl_name, side_style)
end

--- Update a component and its value in the statusline.
--- @param comp Component The component to update.
--- @param sid SessionId The ID of the process to use for this update.
--- @return boolean hidden True if the component is hidden after the update, false otherwise.
local function update_comp(comp, sid)
	Component.emit_pre_update(comp, sid)

	--- This part is manage by DepStoreKey.Display so we don't need to reference to the field of other component
	local min_screen_width = Component.min_screen_width(comp, sid)

	local hidden = min_screen_width and o.columns < min_screen_width or Component.hidden(comp, sid)

	if hidden then
		hide_component(comp)
	else
		local value, override_style = Component.evaluate(comp, sid)

		local indices = comp._indices
		-- A abstract component will not have indices
		-- It's just call the update function for other purpose and we not affect to the statusline
		-- So we just ignore it even the value is empty string
		if indices then
			if value == "" then
				hide_component(comp)
				hidden = true
			else
				-- Main part
				-- Update style first to make sure comp._hl_name is not nil
				local style_updated, style = update_comp_style(comp, sid, override_style)
				Statusline.set_value(indices, value, comp._hl_name)

				--- Left part
				local result = Manager.lookup_dynamic_value(comp, "left", sid)
				if result then
					local lval, force = result[1], result[4]
					if lval then
						update_comp_side_style(comp, sid, "left", style_updated, style)
					end
					lval = format_side_value(lval, force)
					if lval then
						Statusline.set_side_value(indices, -1, lval, comp._left_hl_name, force)
					end
				end

				--- Right part
				result = Manager.lookup_dynamic_value(comp, "right", sid, {})
				if result then
					local rval, force = result[1], result[4]
					if rval then
						update_comp_side_style(comp, sid, "right", style_updated, style)
					end
					rval = format_side_value(rval, force)
					if rval then
						Statusline.set_side_value(indices, 1, rval, comp._right_hl_name, force)
					end
				end

				if comp.on_click then
					Statusline.set_click_handler(indices, Component.register_click_handler(comp))
				end

				rawset(comp, "_hidden", false) -- Reset hidden state
			end
		end
	end

	Component.emit_post_update(comp, sid)
	return hidden
end
M.update_comp = update_comp

--- Update a component and its dependencies.
--- @param comp Component The component to update.
--- @param sid SessionId The ID of the process to use for this update.
--- @param dep_graph_kind DepGraphKind|DepGraphKind[] The store to use for dependencies. Defaults to { EventStore.Timer, EventStore.Event}
--- @param seen table<CompId, true>|nil Optional. A table to keep track of already seen components to avoid infinite recursion.
function M.update_comp_graph(comp, sid, dep_graph_kind, seen)
	seen = seen or {}

	local id = comp.id
	if seen[id] then
		return -- Avoid infinite recursion
	end

	-- Always non nil
	---@cast id CompId
	seen[id] = true

	local hidden = update_comp(comp, sid)

	--- Check if component is loaded and should be render and affect to dependents
	--- If it's not load. It's just the abstract component and we don't care about updated value of it. The function update is just call for update something for abstract component
	if hidden then
		for dep_id, dep_comp in Manager.iterate_dependents(DepGraphKind.Visible, id) do
			seen[dep_id] = true
			hide_component(dep_comp)
		end
	end

	if type(dep_graph_kind) ~= "table" then
		for dep_id, dep_comp in Manager.iterate_dependents(dep_graph_kind, id) do
			if not seen[dep_id] then
				M.update_comp_graph(dep_comp, sid, dep_graph_kind, seen)
			end
		end
	else
		for _, kind in ipairs(dep_graph_kind) do
			for dep_id, dep_comp in Manager.iterate_dependents(kind, id) do
				if not seen[dep_id] then
					M.update_comp_graph(dep_comp, sid, dep_graph_kind, seen)
				end
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
--- @param sid SessionId The ID of the process to use for this update.
--- @param dep_graph_kind DepGraphKind|DepGraphKind[] Optional. The store to use for dependencies. Defaults to { EventStore.Event, EventStore.Timer}
--- @param seen table<CompId, true>|nil Optional. A table to keep track of already seen components to avoid infinite recursion.
M.update_comp_graph_by_ids = function(ids, sid, dep_graph_kind, seen)
	seen = seen or {}
	for _, id in ipairs(ids) do
		if not seen[id] then
			local comp = Manager.get_comp(id)
			if comp then
				M.update_comp_graph(comp, sid, dep_graph_kind, seen)
			end
		end
	end
end

--- Link dependencies for a component based on its ref and inherit fields.
--- @param comp Component The component to link dependencies for.
local function bind_dependencies(comp)
	local link_dependency = Manager.link_dependency
	local ref = comp.ref

	if type(ref) == "table" then
		if ref.events then
			link_dependency(comp, ref.events, DepGraphKind.Event)
		end

		if ref.timing then
			link_dependency(comp, ref.timing, DepGraphKind.Timer)
		end

		if ref.hidden then
			link_dependency(comp, ref.hidden, DepGraphKind.Visible)
		end

		if ref.min_screen_width then
			link_dependency(comp, ref.min_screen_width, DepGraphKind.Visible)
		end
	end

	local inherit = comp.inherit
	if inherit then
		link_dependency(comp, inherit, DepGraphKind.Event)
		link_dependency(comp, inherit, DepGraphKind.Timer)
		link_dependency(comp, inherit, DepGraphKind.Visible)
	end
end

--- Register conditions for a component.
--- @param comp Component The component to register conditions for.
local function bind_update_conditions(comp)
	if comp.timing then
		Timer.register_timer(comp)
	end

	if comp.events then
		Event.register_events(comp)
	end

	if comp.min_screen_width then
		Event.register_vim_resized(comp)
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
	if type(ref) ~= "table" then
		return
	end

	local ref_keys = {
		"context",
		"static",
		"style",
		"left",
		"left_style",
		"right",
		"right_style",
	}

	for i = 1, #ref_keys do
		local dep_id = ref[ref_keys[i]]
		if dep_id and not Manager.is_existed(dep_id) then
			local c = Component.require_by_id(dep_id)
			if c then
				M.register_abstract_component(c)
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
	--- @cast comp_path DefaultId
	if type(comp_path) == "string" then
		local c = require("witch-line.core.Component").require_by_id(comp_path)
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
		Statusline.push(comp, true)
	end
	return comp
end

--- Register a component by its type.
--- @param comp Component|LiteralComponent The component to register.
--- @param parent_id CompId|nil The ID of the parent component, if any.
--- @return Component|LiteralComponent|nil comp The registered component. Nil if registration failed.
function M.register_combined_component(comp, parent_id)
	local kind = type(comp)
	if kind == "string" then
		--- @cast comp DefaultId
		local c = Component.require_by_id(comp)
		if not c then
			return register_literal_comp(comp)
		end
		comp = register_component(c, parent_id)
	elseif kind == "table" and next(comp) then
		--- @cast comp Component
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

	Event.on_event(function(sid, ids)
		M.update_comp_graph_by_ids(ids, sid, DepGraphKind.Event, {})
		Statusline.render()
	end)

	Timer.on_timer_trigger(function(sid, ids)
		M.update_comp_graph_by_ids(ids, sid, DepGraphKind.Timer, {})
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
