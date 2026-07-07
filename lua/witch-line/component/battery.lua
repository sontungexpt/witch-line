local colors = require("witch-line.config.color")

local uv = vim.uv or vim.loop
local sysname = uv.os_uname().sysname

---@type fun(): string, integer
local read_battery

if sysname == "Linux" then
    local bat_dir = vim.fn.glob("/sys/class/power_supply/BAT*", true, true)[1]
    if bat_dir then
        bat_dir = bat_dir:match("(.-)%s*$")
        read_battery = function()
            local f = io.open(bat_dir .. "/uevent", "r")
            if not f then return "", 0 end
            local content = f:read("*all")
            f:close()
            local status = content:match("POWER_SUPPLY_STATUS=(%S+)") or ""
            local cap = content:match("POWER_SUPPLY_CAPACITY=(%d+)")
            return status, cap and tonumber(cap) or 0
        end
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
    read_battery = function()
        local ok = ffi.C.GetSystemPowerStatus(status_struct)
        if ok == 0 then return "Unknown", 0 end
        local s = status_struct[0]
        local capacity = tonumber(s.BatteryLifePercent) or 0
        if s.ACLineStatus == 1 then
            if s.BatteryFlag == 8 or s.BatteryFlag == 9 then return "Charging", capacity end
            return "Full", capacity
        end
        return "Discharging", capacity
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
    read_battery = function()
        local blob = iokit.IOPSCopyPowerSourcesInfo()
        local list = iokit.IOPSCopyPowerSourcesList(blob)
        if list == nil then return "Unknown", 0 end
        local count = core.CFArrayGetCount(list)
        if count == 0 then return "Unknown", 0 end
        local ps = core.CFArrayGetValueAtIndex(list, 0)
        local desc = iokit.IOPSGetPowerSourceDescription(blob, ps)
        local value_ptr = ffi.new("const void *[1]")
        local key = core.CFStringCreateWithCString(nil, "IsCharging", 0)
        local ok = core.CFDictionaryGetValueIfPresent(desc, key, value_ptr)
        core.CFRelease(key)
        local status = "Unknown"
        if ok ~= 0 and value_ptr[0] ~= nil then
            local charging = tonumber(ffi.cast("int*", value_ptr[0])[0]) or 0
            status = charging == 1 and "Charging" or "Discharging"
        end
        key = core.CFStringCreateWithCString(nil, "Current Capacity", 0)
        value_ptr = ffi.new("const void *[1]")
        ok = core.CFDictionaryGetValueIfPresent(desc, key, value_ptr)
        core.CFRelease(key)
        local capacity = 0
        if ok ~= 0 and value_ptr[0] ~= nil then
            capacity = tonumber(ffi.cast("int*", value_ptr[0])[0]) or 0
        end
        core.CFRelease(blob)
        return status, capacity
    end
end

local last_read = 0
local cached_status = ""
local cached_capacity = 0

---@type DefaultComponent
return {
    id = "wl.battery",
    ___builtin = true,
    timing = 1000,
    static = {
        poll_interval = 10000,
        icon = {
            charging = { "󰢟", "󰢜", "󰂆", "󰂇", "󰂈", "󰢝", "󰂉", "󰢞", "󰂊", "󰂋", "󰂅" },
            discharging = { "󰂎", "󰁺", "󰁻", "󰁼", "󰁽", "󰁾", "󰁿", "󰂀", "󰂁", "󰂂", "󰁹" },
        },
    },
    update = function(self, _)
        if not read_battery then return "" end

        local now = uv.now()
        if now - last_read >= self.static.poll_interval then
            cached_status, cached_capacity = read_battery()
            last_read = now
        end
        local status, capacity = cached_status, cached_capacity
        local icon = self.static.icon
        local level = math.floor(capacity / 10) + 1
        local color = level > 8 and colors.green or level > 3 and colors.yellow or colors.red
        local value

        if status == "Full" then
            value = "󰂄 " .. capacity .. "%%"
        elseif status == "Charging" then
            local t = math.floor(now / 1000) % #icon.charging
            value = icon.charging[t + 1] .. " " .. capacity .. "%%"
        elseif status == "Discharging" or status == "Not charging" then
            value = icon.discharging[level] .. " " .. capacity .. "%%"
        else
            value = "Battery: " .. capacity .. "%%"
        end

        return value, { fg = color }
    end,
}
