local Id       = require("witch-line.constant.id").Id
local colors   = require("witch-line.constant.color")

--- @type DefaultComponent
return {
	id = Id["battery"],
  _plug_provided = true,
	timing = true,
	static = {
		icons = {
			charging = {
				"󰢟",
				"󰢜",
				"󰂆",
				"󰂇",
				"󰂈",
				"󰢝",
				"󰂉",
				"󰢞",
				"󰂊",
				"󰂋",
				"󰂅",
			},
			discharging = {
				"󰂎",
				"󰁺",
				"󰁻",
				"󰁼",
				"󰁽",
				"󰁾",
				"󰁿",
				"󰂀",
				"󰂁",
				"󰂂",
				"󰁹",
			},
		},
	},
	style = {
		fg = colors.green,
	},
  context = {
    current_charging_index = 0,
  },
  init = function (self, ctx, static, session_id)
		local bat_dir = vim.fn.glob("/sys/class/power_supply/BAT*", true, true)[1]
		if not bat_dir then
      return
    end
		bat_dir = bat_dir:match("(.-)%s*$")

		local read_battery_file = function(filename)
			local f = io.open(bat_dir .. "/" .. filename, "r")
			if not f then return "" end
			local content = f:read("*all")
			f:close()
			return content:match("(.-)%s*$")
		end

    ctx.get_status = function() return read_battery_file("status") end
		ctx.get_capacity = function() return read_battery_file("capacity") end
	end,
  update = function (self, ctx, static, session_id)
    if not ctx.get_status or not ctx.get_capacity then
      return ""
    end

		local status = ctx.get_status()
		local capacity = ctx.get_capacity()
		local icon_index = math.floor(capacity / 10) + 1
		local battery_color = icon_index > 8 and colors.green
			or icon_index > 3 and colors.yellow
			or colors.red

    local value = ""
		if status == "Charging" then
			ctx.current_charging_index = ctx.current_charging_index == 0 and icon_index
				or ctx.current_charging_index < #static.icons.charging and ctx.current_charging_index + 1
				or icon_index

      value =  static.icons.charging[ctx.current_charging_index] .. " " .. capacity .. "%%"
		elseif status == "Discharging" or status == "Not charging" then
			ctx.current_charging_index = 0

      value = static.icons.discharging[icon_index] .. " " .. capacity .. "%%"
		elseif status == "Full" then
			ctx.current_charging_index = 0
      value =  "󰂄 " .. capacity .. "%%"
		else
			ctx.current_charging_index = 0
			return "Battery: " .. capacity .. "%%"
		end

    return value,{ fg = battery_color }
	end,
  hide = function (self, ctx, static, session_id)
     return (vim.uv or vim.loop).os_uname().sysname ~= "Linux"
  end,
}
