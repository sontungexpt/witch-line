local type, str_rep = type, string.rep

local M = {}
---
---@alias Id string
---@alias NotString table|number|boolean|function|nil|thread

---@class FlatComponent
---@field id Id|nil the unique identifier of the component, can be a string or an integer
---@field timing boolean|integer|nil|Id|Id[] if true, the component will be updated every time interval
---@field lazy boolean|nil if true, the component will be initialized lazily
---@field events string[]|Id[]|nil a table of events that the component will listen to
---@field user_events string[]|Id[]|nil a table of user defined events that the component will listen to
---@field left string|nil the left part of the component, can be a string or another component
---@field right string|nil the right part of the component, can be a string or another component
---@field padding integer|nil|{left: integer, right:integer} the padding of the component, can be used to add space around the component
---@field style Id|vim.api.keyset.highlight|nil|fun(self: Component, ctx: NotString, static: NotString): vim.api.keyset.highlight a table of styles that will be applied to the component
---@field static Id|table|nil a table of static values that will be used in the component
---@field context Id|nil|fun(self:FlatComponent, static:NotString): NotString a table that will be passed to the component's update function
---@field init nil|fun(self: FlatComponent, ctx: NotString, static: NotString ) called when the component is initialized, can be used to set up the context
---@field pre_update nil|fun(self: Component, ctx: NotString, static: NotString) called before the component is updated, can be used to set up the context
---@field update string|fun(self:FlatComponent, ctx: NotString, static: NotString): string called to update the component, should return a string that will be displayed
---@field post_update nil|fun(self: FlatComponent,ctx: NotString, static: NotString) called after the component is updated, can be used to clean up the context
---@field should_display Id|nil|fun(self: FlatComponent, ctx:NotString, static: NotString): boolean called to check if the component should be displayed, should return true or false
---@field _indices integer[]|nil A list of indices of the component in the Values table, used for rendering the component (only the root component had)
---@field _hl_name string|nil the highlight group name for the component
---@field _loaded boolean|nil if true, the component is loaded and ready to be used, used for lazy loading components

M.call_init = function(comp, ctx)
	ctx = ctx or comp.context
	if type(ctx) == "function" then
		ctx = ctx(comp)
	end

	if type(comp.init) == "function" then
		comp.init(ctx, comp)
	end
end

--- @param comp FlatComponent the component to evaluate
--- @return string value the new value of the component
--- @return table|nil style the new style of the component, or nil if no style is defined
M.evaluate = function(comp, ctx, static)
	if type(comp.pre_update) == "function" then
		comp.pre_update(comp, ctx, static)
	end

	local value = comp.update
	if type(value) == "function" then
		value = value(comp, ctx, static)
	end

	if type(value) ~= "string" then
		require("utils.notifier").error("Component:update must return a string, got " .. type(value) .. " instead.")
		return "", nil
	end

	if type(comp.post_update) == "function" then
		comp.post_update(comp, ctx, static)
	end

	local padding = comp.padding or 1
	if type(padding) == "number" then
		value = str_rep(" ", padding) .. value .. str_rep(" ", padding)
	elseif type(padding) == "table" then
		local left, right = padding.left, padding.right
		if type(left) == "number" and left > 0 then
			value = str_rep(" ", left) .. value
		end
		if type(right) == "number" and right > 0 then
			value = value .. str_rep(" ", right)
		end
	end

	return value
end

return M
