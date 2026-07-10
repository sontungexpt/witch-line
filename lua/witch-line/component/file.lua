local colors = require("witch-line.constant.color")
local uv, api, bo = vim.uv or vim.loop, vim.api, vim.bo

local resolve = function(v) return type(v) == "function" and v() or v end

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
        local fs = vim.fs

        local fmt = self.config.formatter
        local formatter = fmt.filetype[bo.filetype] or fmt.buftype[bo.buftype]

        if formatter then
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
        local ctx = self.context(self, session)
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
        local ctx = self.context(self, session)
        return ctx.icon, {
            fg = ctx.color,
        }
    end,
}

---@type DefaultComponent
local Modifier = {
    id = "wl.file.modifier",
    ___builtin = true,
    events = "OptionSet",
    style = {
        fg = colors.fg,
    },
    update = function(self, session)
        if bo.buftype ~= "" then
            return ""
        end

        if not bo.modifiable or bo.readonly then
            return ""
        end

        if bo.modified then
            return ""
        end

        return ""
    end,
}

---@type DefaultComponent
local Size = {
    id = "wl.file.size",
    ___builtin = true,

    events = {
        "BufEnter",
        "BufWritePost",
        "FileChangedShellPost"
    },

    style = {
        fg = colors.green,
    },

    update = function(self)
        local file = api.nvim_buf_get_name(0)
        if file == "" then
            return ""
        end

        local stat = uv.fs_stat(file)
        if type(stat) ~= "table" or stat.type ~= "file" or not stat.size then
            return ""
        end

        local s, i = stat.size, 1

        local SIZE_UNITS = { "B", "KB", "MB", "GB" }
        while s > 1024 and i < #SIZE_UNITS do
            s, i = s / 1024, i + 1
        end


        return ((i == 1 and "%d" or "%.1f") .. "%s"):format(
            s, SIZE_UNITS[i]
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
