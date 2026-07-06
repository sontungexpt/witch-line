
local colors = require("witch-line.config.color")

---@type fun(): string|nil
local get_status
---@type fun(): integer|nil
local get_capacity
---@type fun()
local battery_init

battery_init = function()
    if get_status then return end
    local uv = vim.uv or vim.loop
    local sysname = uv.os_uname().sysname

    if sysname == "Linux" then
        local bat_dir = vim.fn.glob("/sys/class/power_supply/BAT*", true, true)[1]
        if bat_dir then
            bat_dir = bat_dir:match("(.-)%s*$")
            local function read_file(filename)
                local f = io.open(bat_dir .. "/" .. filename, "r")
                if not f then return "" end
                local content = f:read("*all")
                f:close()
                return content:match("(.-)%s*$")
            end
            get_status = function() return read_file("status") end
            get_capacity = function() return tonumber(read_file("capacity")) end
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
        get_status = function()
            if ffi.C.GetSystemPowerStatus(status_struct) == 0 then return "Unknown" end
            local s = status_struct[0]
            if s.ACLineStatus == 1 then
                if s.BatteryFlag == 8 or s.BatteryFlag == 9 then return "Charging" end
                return "Full"
            end
            return "Discharging"
        end
        get_capacity = function()
            if ffi.C.GetSystemPowerStatus(status_struct) == 0 then return 0 end
            return tonumber(status_struct[0].BatteryLifePercent) or 0
        end
    elseif sysname == "Darwin" then
        local ffi = require("ffi")
        ffi.cdef([[
            CFTypeRef IOPSCopyPowerSourcesInfo(void);
            CFArrayRef IOPSCopyPowerSourcesList(CFTypeRef blob);
            CFDictionaryRef IOPSGetPowerSourceDescription(CFTypeRef blob, CFTypeRef ps);
            CFDictionaryRef CFDictionaryGetValue(CFDictionaryRef dict, CFStringRef key);
            CFStringRef CFStringCreateWithCString(void *alloc, const char *cStr, int encoding);
            const void *CFDictionaryGetValueIfPresent(CFDictionaryRef theDict, CFStringRef key, const void **value);
            int CFNumberGetValue(CFTypeRef number, int type, void *value);
            int CFStringCompare(CFStringRef theString1, CFStringRef theString2, int compareOptions);
            void CFRelease(CFTypeRef cf);
            int CFArrayGetCount(CFArrayRef theArray);
            CFTypeRef CFArrayGetValueAtIndex(CFArrayRef theArray, int idx);
        ]])
        local iokit = ffi.load("/System/Library/Frameworks/IOKit.framework/IOKit")
        local core = ffi.load("/System/Library/Frameworks/CoreFoundation.framework/CoreFoundation")
        get_status = function()
            local blob = iokit.IOPSCopyPowerSourcesInfo()
            local list = iokit.IOPSCopyPowerSourcesList(blob)
            if list == nil then return "Unknown" end
            local count = core.CFArrayGetCount(list)
            if count == 0 then return "Unknown" end
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
        get_capacity = function()
            local blob = iokit.IOPSCopyPowerSourcesInfo()
            local list = iokit.IOPSCopyPowerSourcesList(blob)
            if list == nil then return 0 end
            local count = core.CFArrayGetCount(list)
            if count == 0 then return 0 end
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
end

---@type integer
local charge_anim_index = 0

---@type DefaultComponent
return {
    id = "wl.battery",
    ___plug_provided = true,
    timing = 10000,
    static = {
        icons = {
            charging = { "󰢟", "󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅" },
            discharging = { "󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹" },
        },
    },
    style = { fg = colors.green },
    update = function(self, _)
        battery_init()
        if not get_status then return "" end

        local icons = self.static.icons
        local status = get_status()
        local capacity = get_capacity()
        local level_index = math.floor(capacity / 10) + 1

        local battery_color = level_index > 8 and colors.green
            or level_index > 3 and colors.yellow
            or colors.red

        local value

        if status == "Charging" then
            charge_anim_index = charge_anim_index == 0 and level_index
                or charge_anim_index < #icons.charging and charge_anim_index + 1
                or level_index
            value = icons.charging[charge_anim_index] .. " " .. capacity .. "%%"
        elseif status == "Discharging" or status == "Not charging" then
            charge_anim_index = 0
            value = icons.discharging[level_index] .. " " .. capacity .. "%%"
        elseif status == "Full" then
            charge_anim_index = 0
            value = "󰂄 " .. capacity .. "%%"
        else
            charge_anim_index = 0
            value = "Battery: " .. capacity .. "%%"
        end

        return value, { fg = battery_color }
    end,
}
