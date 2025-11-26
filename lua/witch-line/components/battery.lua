local Id = require("witch-line.constant.id").Id
local colors = require("witch-line.constant.color")

--- @class witch-line.componets.battery.Static
--- @field icons {charging: string[], discharging: string[]}
--- @field colors {battery_high: string, battery_medium: string, battery_weak : string}
---
--- @class witch-line.componets.battery.Context
--- @field charge_anim_index integer
--- @field get_status? fun():string
--- @field get_capacity? fun():number
--- @type DefaultComponent
return {
	id = Id["battery"],
	_plug_provided = true,
	timing = 10000, -- 10 seconds
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
		colors = {
			battery_high = colors.green,
			battery_medium = colors.yellow,
			battery_weak = colors.red,
		},
	},
	style = {
		fg = colors.green,
	},
	context = {
		charge_anim_index = 0,
	},
	init = function(self, session_id)
		local sysname = (vim.uv or vim.loop).os_uname().sysname
		local ctx = require("witch-line.core.manager.hook").use_context(self, session_id)
		if sysname == "Linux" then
			local bat_dir = vim.fn.glob("/sys/class/power_supply/BAT*", true, true)[1]
			if not bat_dir then
				return
			end
			bat_dir = bat_dir:match("(.-)%s*$")
			local read_battery_file = function(filename)
				local f = io.open(bat_dir .. "/" .. filename, "r")
				if not f then
					return ""
				end
				local content = f:read("*all")
				f:close()
				return content:match("(.-)%s*$")
			end

			ctx.get_status = function()
				return read_battery_file("status")
			end
			ctx.get_capacity = function()
				return tonumber(read_battery_file("capacity"))
			end
		elseif sysname == "Windows_NT" then
			local ffi = require("ffi")
			ffi.cdef([[
        typedef struct {
          unsigned char ACLineStatus;
          unsigned char BatteryFlag;
          unsigned char BatteryLifePercent;
          unsigned char Reserved1;
          unsigned long BatteryLifeTime;
          unsigned long BatteryFullLifeTime;
        } SYSTEM_POWER_STATUS;
        int GetSystemPowerStatus(SYSTEM_POWER_STATUS *lpSystemPowerStatus);
      ]])

			local status_struct = ffi.new("SYSTEM_POWER_STATUS[1]")
			ctx.get_status = function()
				if ffi.C.GetSystemPowerStatus(status_struct) == 0 then
					return "Unknown"
				end
				local s = status_struct[0]
				if s.ACLineStatus == 1 then
					if s.BatteryFlag == 8 or s.BatteryFlag == 9 then
						return "Charging"
					end
					return "Full"
				else
					return "Discharging"
				end
			end
			ctx.get_capacity = function()
				if ffi.C.GetSystemPowerStatus(status_struct) == 0 then
					return 0
				end
				return tonumber(status_struct[0].BatteryLifePercent) or 0
			end
		elseif sysname == "Darwin" then
			--- macOS IOKit bindings
			local ffi = require("ffi")
			ffi.cdef([[
        CFTypeRef IOPSCopyPowerSourcesInfo(void);
        CFArrayRef IOPSCopyPowerSourcesList(CFTypeRef blob);
        CFDictionaryRef IOPSGetPowerSourceDescription(CFTypeRef blob, CFTypeRef ps);
        CFTypeRef CFDictionaryGetValue(CFDictionaryRef dict, CFStringRef key);
        CFStringRef CFStringCreateWithCString(void *alloc, const char *cStr, int encoding);
        const void *CFDictionaryGetValueIfPresent(CFDictionaryRef theDict, CFStringRef key, const void **value);
        int CFNumberGetValue(CFTypeRef number, int type, void *value);
        int CFStringCompare(CFStringRef theString1, CFStringRef theString2, int compareOptions);
        void CFRelease(CFTypeRef cf);
        int CFArrayGetCount(CFArrayRef theArray);
        CFTypeRef CFArrayGetValueAtIndex(CFArrayRef theArray, int idx);
      ]])
			-- macOS battery info via IOKit
			local iokit = ffi.load("/System/Library/Frameworks/IOKit.framework/IOKit")
			local core = ffi.load("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")

			ctx.get_status = function()
				local blob = iokit.IOPSCopyPowerSourcesInfo()
				local list = iokit.IOPSCopyPowerSourcesList(blob)
				if list == nil then
					return "Unknown"
				end
				local count = core.CFArrayGetCount(list)
				if count == 0 then
					return "Unknown"
				end

				local ps = core.CFArrayGetValueAtIndex(list, 0)
				local desc = iokit.IOPSGetPowerSourceDescription(blob, ps)
				local value_ptr = ffi.new("const void *[1]")

				local key = core.CFStringCreateWithCString(nil, "IsCharging", 0)
				local ok = core.CFDictionaryGetValueIfPresent(desc, key, value_ptr)
				core.CFRelease(key)
				if ok ~= 0 and value_ptr[0] ~= nil then
					local charging = tonumber(ffi.cast("int*", value_ptr[0])[0]) or 0
					core.CFRelease(blob)
					return charging == 1 and "Charging" or "Discharging"
				end
				core.CFRelease(blob)
				return "Unknown"
			end

			ctx.get_capacity = function()
				local blob = iokit.IOPSCopyPowerSourcesInfo()
				local list = iokit.IOPSCopyPowerSourcesList(blob)
				if list == nil then
					return 0
				end
				local count = core.CFArrayGetCount(list)
				if count == 0 then
					return 0
				end

				local ps = core.CFArrayGetValueAtIndex(list, 0)
				local desc = iokit.IOPSGetPowerSourceDescription(blob, ps)
				local value_ptr = ffi.new("const void *[1]")
				local key = core.CFStringCreateWithCString(nil, "Current Capacity", 0)
				local ok = core.CFDictionaryGetValueIfPresent(desc, key, value_ptr)
				core.CFRelease(key)
				if ok ~= 0 and value_ptr[0] ~= nil then
					local capacity = tonumber(ffi.cast("int*", value_ptr[0])[0]) or 0
					core.CFRelease(blob)
					return capacity
				end
				core.CFRelease(blob)
				return 0
			end
		end
	end,
	update = function(self, session_id)
		local ctx, static = self.context, self.static
		--- @cast static witch-line.componets.battery.Static
		--- @cast ctx witch-line.componets.battery.Context

		if not ctx.get_status or not ctx.get_capacity then
			return ""
		end

		local status = ctx.get_status()
		local capacity = ctx.get_capacity()
		local level_index = math.floor(capacity / 10) + 1

		local battery_color = level_index > 8 and static.colors.battery_high
			or level_index > 3 and static.colors.battery_medium
			or static.colors.battery_weak

		local charge_anim_index = ctx.charge_anim_index

		local value = ""
		if status == "Charging" then
			charge_anim_index = charge_anim_index == 0 and level_index
				or charge_anim_index < #static.icons.charging and charge_anim_index + 1
				or level_index

			value = static.icons.charging[charge_anim_index] .. " " .. capacity .. "%%"
		elseif status == "Discharging" or status == "Not charging" then
			charge_anim_index = 0
			value = static.icons.discharging[level_index] .. " " .. capacity .. "%%"
		elseif status == "Full" then
			charge_anim_index = 0
			value = "󰂄 " .. capacity .. "%%"
		else
			charge_anim_index = 0
			value = "Battery: " .. capacity .. "%%"
		end

		ctx.charge_anim_index = charge_anim_index
		return value, { fg = battery_color }
	end,
}
