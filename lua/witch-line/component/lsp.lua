local colors = require("witch-line.config.color")

---@type DefaultComponent
local Clients = {
    id = "wl.lsp.clients",
    ___builtin = true,
    events = { "LspAttach", "LspDetach", "BufWritePost" },
    flexible = 100,
    config = {
        disabled_filetypes = { "NvimTree" },
        ignore_servers = {
            ["null-ls"] = true,
            ["none-ls"] = true,
            ["copilot"] = true,
        },
    },
    hidden = function(self, session_id)
        local disabled = self.config.disabled_filetypes
        return type(disabled) == "table"
            and vim.list_contains(disabled, vim.bo.filetype)
    end,
    style = { fg = colors.magenta },
    update = function(self, session_id)
        local bufnr = vim.api.nvim_get_current_buf()
        if not vim.api.nvim_buf_is_valid(bufnr) then
            return ""
        end

        local ignore = self.config.ignore_servers
        local names = {}
        local seen = {}

        for _, client in ipairs(vim.lsp.get_clients { bufnr = bufnr }) do
            if not ignore[client.name] then
                seen[client.name] = true
                names[#names + 1] = client.name
            end
        end

        local ls = package.loaded["null-ls"] or package.loaded["none-ls"]
        if ls then
            local sources = ls.sources.get_available(vim.bo[bufnr].filetype)
            local methods = ls.methods
            for _, source in ipairs(sources) do
                local m = source.methods
                if not seen[source.name] and (
                        m[methods.DIAGNOSTICS]
                        or m[methods.DIAGNOSTICS_ON_OPEN]
                        or m[methods.DIAGNOSTICS_ON_SAVE]
                        or m[methods.FORMATTING]
                    ) then
                    seen[source.name] = true
                    names[#names + 1] = source.name
                end
            end
        end

        local conform = package.loaded["conform"]
        if conform then
            for _, f in ipairs(conform.list_formatters(bufnr)) do
                if not seen[f.name] then
                    seen[f.name] = true
                    names[#names + 1] = f.name
                end
            end
        end

        if #names == 0 then
            return "No Lsp, Formatters  "
        end
        return table.concat(names, ", ")
    end,
}

return {
    clients = Clients,
}
