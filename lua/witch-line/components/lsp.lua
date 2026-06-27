local colors = require("witch-line.constant.color")

---@type DefaultComponent
local Clients = {
    id = "wl.lsp.clients",
    _plug_provided = true,
    events = { "LspAttach", "LspDetach", "BufWritePost" },
    flexible = 100,
    static = {
        disabled = {
            filetypes = {
                "NvimTree",
            },
        },
    },
    hidden = function(self, session_id)
        local disabled = self.static.disabled
        ---@cast disabled {filetypes: string[]}
        if type(disabled) ~= "table" then
            return false
        end

        return type(disabled.filetypes) == "table" and vim.list_contains(disabled.filetypes, vim.bo.filetype)
    end,
    style = { fg = colors.magenta },

    update = function(self, session_id)
        local bufnr = vim.api.nvim_get_current_buf()
        local server_names = {}

        local ignore_lsp_servers = {
            ["null-ls"] = true,
            ["copilot"] = true,
        }

        for _, client in ipairs(vim.lsp.get_clients { bufnr = bufnr }) do
            if not ignore_lsp_servers[client.name] then
                server_names[#server_names + 1] = client.name
            end
        end

        local has_null_ls, null_ls = pcall(require, "null-ls")
        if has_null_ls then
            local buf_ft = vim.bo[bufnr].filetype
            local sources = require("null-ls.sources")
            local available_sources = sources.get_available(buf_ft)

            for _, source in ipairs(available_sources) do
                local is_lsp_related = source.methods[null_ls.methods.DIAGNOSTICS]
                    or source.methods[null_ls.methods.DIAGNOSTICS_ON_OPEN]
                    or source.methods[null_ls.methods.DIAGNOSTICS_ON_SAVE]
                    or source.methods[null_ls.methods.FORMATTING]

                if is_lsp_related then
                    server_names[#server_names + 1] = source.name
                end
            end
        end

        if package.loaded["conform"] then
            local ok, conform = pcall(require, "conform")
            if ok then
                local formatters = conform.list_formatters(bufnr)
                vim.list_extend(
                    server_names,
                    vim.tbl_map(function(formatter)
                        return formatter.name
                    end, formatters)
                )
            end
        end

        server_names = require("witch-line.utils.tbl").unique_list(server_names)
        return #server_names > 0 and table.concat(server_names, ", ") or "No Lsp, Formatters  "
    end,
}

return {
    clients = Clients,
}
