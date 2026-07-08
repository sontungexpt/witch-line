local colors = require("witch-line.config.color")

local DEBUG_LOG = ("/tmp/witch-line-debug-%s.log"):format(vim.fn.getpid())
local function debug_log(...)
    vim.fn.writefile({ os.date("%H:%M:%S") .. " " .. table.concat({...}, " ") }, DEBUG_LOG, "a")
end

local INTERFACE_ID = "wl.file.interface"

---@type DefaultComponent
local Interface = {
    id = INTERFACE_ID,
    ___builtin = true,

    events = "BufEnter",

    config = {
        formatter = {
            filetype = {
                ["NvimTree"] = { "NvimTree", "", colors.red },
                ["TelescopePrompt"] = { "Telescope", "", colors.red },
                ["mason"] = { "Mason", "󰏔", colors.red },
                ["lazy"] = { "Lazy", "󰏔", colors.red },
                ["checkhealth"] = { "Health", "", colors.red },
                ["plantuml"] = { nil, "", colors.green },
                ["dashboard"] = { nil, "", colors.red },
                ["toggleterm"] = {
                    function()
                        return "ToggleTerm " .. vim.b.toggle_number
                    end,
                    "",
                    colors.red,
                },
            },

            buftype = {
                ["terminal"] = { "Terminal", "", colors.red },
            },
        },
    },

    ---@param self ManagedComponent
    ---@return {basename: string, icon: string, color: string}
    context = function(self)
        local api, fs, bo = vim.api, vim.fs, vim.bo

        local fmt = self.config.formatter
        local formatter = fmt.filetype[bo.filetype] or fmt.buftype[bo.buftype]

        if formatter then
            local resolve = require("witch-line.util").resolve

            return {
                basename = resolve(formatter[1]) or fs.basename(api.nvim_buf_get_name(0)) or "No File",
                icon = resolve(formatter[2]) or "",
                color = resolve(formatter[3]) or "#ffffff",
            }
        end

        local basename = fs.basename(api.nvim_buf_get_name(0))
        local icon, color

        local devicons = package.loaded["nvim-web-devicons"]
        if not devicons then
            local ok
            ok, devicons = pcall(require, "nvim-web-devicons")
        end
        if devicons then
            local ext = basename:match("%.([^%.]+)$")
            icon, color = devicons.get_icon_color(basename, ext)
        end

        return {
            basename = basename ~= "" and basename or "No File",
            icon = icon or "",
            color = color or "#ffffff",
        }
    end,
}

---@type DefaultComponent
local Name = {
    id = "wl.file.name",
    ___builtin = true,

    ref = {
        events = INTERFACE_ID,
        context = INTERFACE_ID,
    },

    style = {
        fg = colors.orange,
    },
    update = function(self, session)
        debug_log("FILE_NAME update", "self.id=" .. tostring(self.id))
        debug_log("FILE_NAME context type", type(self.context))
        local ctx = self.context(self, session)
        debug_log("FILE_NAME ctx", type(ctx))
        return ctx.basename
    end,
}

---@type DefaultComponent
local Icon = {
    id = "wl.file.icon",
    ___builtin = true,

    ref = {
        events = INTERFACE_ID,
        context = INTERFACE_ID,
    },

    update = function(self, session)
        debug_log("FILE_ICON update", "self.id=" .. tostring(self.id))
        debug_log("FILE_ICON context type", type(self.context))
        local ctx = self.context(self, session)
        debug_log("FILE_ICON ctx", type(ctx))
        return ctx.icon, {
            fg = ctx.color,
        }
    end,
}

---@type DefaultComponent
local Modifier = {
    id = "wl.file.modifier",
    ___builtin = true,

    events = {
        "BufEnter",
        "BufWritePost",
        "TextChangedI",
        "TextChanged",
    },

    style = {
        fg = colors.fg,
    },

    update = function()
        local bo = vim.bo

        if bo.buftype == "prompt" then
            return ""
        elseif not bo.modifiable or bo.readonly then
            return ""
        elseif bo.modified then
            return ""
        end

        return ""
    end,
}

---@type DefaultComponent
local Size = {
    id = "wl.file.size",
    ___builtin = true,

    events = "BufWritePost",

    ref = {
        events = INTERFACE_ID,
    },

    style = {
        fg = colors.green,
    },

    config = {
        icon = "",
    },

    update = function(self)
        local file = vim.api.nvim_buf_get_name(0)
        if file == "" then
            return ""
        end

        local stat = (vim.uv or vim.loop).fs_stat(file)
        if type(stat) ~= "table" or not stat.size or stat.size == 0 then
            return ""
        end

        local size = stat.size
        local units = { "B", "KB", "MB", "GB" }
        local i = 1

        while size > 1024 and i < #units do
            size = size / 1024
            i = i + 1
        end

        return ("%s %s"):format(
            self.config.icon,
            string.format(i == 1 and "%d%s" or "%.1f%s", size, units[i])
        )
    end,
}

return {
    interface = Interface,
    name = Name,
    icon = Icon,
    modifier = Modifier,
    size = Size,
}
