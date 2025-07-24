-- local highlight = require("witch-line.utils.highlight")
-- local coroutine, rawget, type, str_rep, setmetatable = coroutine, rawget, type, string.rep, setmetatable

-- local M = {}

-- ---@class Component
-- ---@field name string nickname of the component
-- ---@field timing boolean|integer|nil if true, the component will be updated every time interval
-- ---@field lazy boolean|nil if true, the component will be initialized lazily
-- ---@field dispersed boolean|nil if true, the component will be rendered in a dispersed manner
-- ---@field event string[]|nil a table of events that the component will listen to
-- ---@field user_event string[]|nil a table of user defined events that the component will listen to
-- ---@field left string|Component|nil the left part of the component, can be a string or another component
-- ---@field right string|Component|nil the right part of the component, can be a string or another component
-- ---@field padding integer|nil|{left: integer, right:integer} the padding of the component, can be used to add space around the component
-- ---@field style table|nil|fun(ctx: any, self: Component): table a table of styles that will be applied to the component
-- ---@field static table|nil a table of static values that will be used in the component
-- ---@field context nil|fun(self:Component):any a table that will be passed to the component's update function
-- ---@field pre_update nil|fun(ctx: any, self: Component) called before the component is updated, can be used to set up the context
-- ---@field update string|fun(ctx: any, self): string called to update the component, should return a string that will be displayed
-- ---@field post_update nil|fun(ctx: any, self: Component) called after the component is updated, can be used to clean up the context
-- ---@field display_when nil|fun(ctx: any, self: Component): boolean called to check if the component should be displayed, should return true or false
-- ---@field _hl_name string the highlight group name for the component
-- ---@field _parent Component|nil the parent component of this component, used for hierarchical structure
-- ---@field _indices integer[]|nil A list of indices of the component in the Values table, used for rendering the component (only the root component had)
-- ---@field _loaded boolean|nil if true, the component is loaded and ready to be used, used for lazy loading components

-- local function new_node(node, parent, hl_name, cb)
-- 	local node_type = type(node)
-- 	if node_type == "string" then
-- 		node = {
-- 			update = node,
-- 			_parent = parent,
-- 			_hl_name = hl_name,
-- 		}

-- 		if cb then
-- 			cb(node)
-- 		end

-- 		return node
-- 	elseif node_type == "table" then
-- 		node._parent = parent
-- 		if highlight.is_hl_styles(node.styles) then
-- 			hl_name = highlight.gen_hl_name_by_id()
-- 			node._hl_name = hl_name
-- 		end

-- 		local left = node.left
-- 		if left then
-- 			node.left = new_node(left, node, hl_name, cb)
-- 		end

-- 		if cb then
-- 			cb(node)
-- 		end

-- 		local right = node.right
-- 		if right then
-- 			node.right = new_node(right, node, hl_name)
-- 		end

-- 		return node
-- 	end

-- 	return nil
-- end

-- --- @param initial Component | string
-- --- @param on_new fun(node: Component) called for each node created, can be used to set up the component
-- function M.new(initial, on_new)
-- 	local instance = new_node(initial, nil, on_new)

-- 	---@cast instance Component
-- 	return instance
-- end

-- --- Evaluate the component to get its value and style.
-- --- This function will call the `update` function of the component
-- --- and return the value and style of the component.
-- --- If the `update` function is a string
-- --- it will be returned as the value.
-- --- If the `update` function is a function,
-- --- it will be called with the context and the component instance
-- --- and the return value will be used as the value.o
-- --- If the `style` property is a function,
-- --- it will be called with the context and the component instance
-- --- and the return value will be used as the style.
-- ---  If the `style` property is a table,
-- ---  it will be used as the style directly.
-- --- @param comp Component the component to evaluate
-- --- @return string value the new value of the component
-- --- @return table|nil style the new style of the component, or nil if no style is defined
-- function M.evaluate(comp)
-- 	local ctx = comp.context

-- 	if type(ctx) == "function" then
-- 		ctx = ctx(comp)
-- 	end

-- 	if type(comp.pre_update) == "function" then
-- 		comp.pre_update(ctx, comp)
-- 	end

-- 	local value = comp.update
-- 	if type(value) == "function" then
-- 		value = value(ctx, comp)
-- 	end

-- 	if type(value) ~= "string" then
-- 		require("utils.notifier").error("Component:update must return a string, got " .. type(value) .. " instead.")
-- 		return "", nil
-- 	end

-- 	if type(comp.post_update) == "function" then
-- 		comp.post_update(ctx, comp)
-- 	end

-- 	local style = comp.style
-- 	if type(style) == "function" then
-- 		style = style(ctx, comp)
-- 		if type(style) ~= "table" then
-- 			require("utils.notifier").error("Component:style must return a table, got " .. type(style) .. " instead.")
-- 			style = nil
-- 		end
-- 	else
-- 		style = nil
-- 	end

-- 	local padding = comp.padding or 1
-- 	if type(padding) == "number" then
-- 		value = str_rep(" ", padding) .. value .. str_rep(" ", padding)
-- 	elseif type(padding) == "table" then
-- 		local left, right = padding.left, padding.right
-- 		if type(left) == "number" and left > 0 then
-- 			value = str_rep(" ", left) .. value
-- 		end
-- 		if type(right) == "number" and right > 0 then
-- 			value = value .. str_rep(" ", right)
-- 		end
-- 	end

-- 	return value, style
-- end

-- local function count_dfs(comp)
-- 	local comp_type = type(comp)
-- 	if comp_type == "string" then
-- 		return 1
-- 	elseif comp_type ~= "table" then
-- 		local count = 1 -- main node

-- 		if comp.left then
-- 			count = count + count_dfs(comp.left)
-- 		end

-- 		if comp.right then
-- 			count = count + count_dfs(comp.right)
-- 		end

-- 		return count
-- 	end
-- 	return 0
-- end
-- M.count_dfs = count_dfs

-- M.bubble_lookup = function(self, prop_name, max_depth)
-- 	-- find from the current node
-- 	local v = self[prop_name]
-- 	if v then
-- 		return v
-- 	end

-- 	max_depth = max_depth or 100
-- 	--- bubble up the parent nodes
-- 	local node = self._parent
-- 	while node and max_depth > 0 do
-- 		v = node[prop_name]
-- 		if v then
-- 			return v
-- 		end
-- 		node = node._parent
-- 		max_depth = max_depth - 1
-- 	end
-- 	return nil
-- end

-- local function yield_iter(comp)
-- 	if comp.left then
-- 		yield_iter(comp.left)
-- 	end

-- 	coroutine.yield(comp)

-- 	if comp.right then
-- 		yield_iter(comp.right)
-- 	end
-- end

-- M.inorder_iter = function(self)
-- 	return coroutine.wrap(function()
-- 		yield_iter(self)
-- 	end)
-- end

-- return M
