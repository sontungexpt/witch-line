local M = {}

--- Sentinel key for the fallback handler in the command trie.
local FALLBACK_KEY = {}

local COMMANDS = {
    toggle_auto_theme = function(...)
        return require("witch-line.core.highlight").toggle_auto_theme(...)
    end,
    inspect = {
        event_store = function(...)
            return require("witch-line.core.manager.event").inspect(...)
        end,
        timer_store = function(...)
            return require("witch-line.core.manager.timer").inspect(...)
        end,
        comp_manager = {
            comps = function(...)
                return require("witch-line.core.manager").inspect(...)
            end,
            dep_store = function(...)
                return require("witch-line.core.manager").inspect(...)
            end,
        },
        highlight = {
            rgb24bit = function(...)
                return require("witch-line.core.highlight").inspect(...)
            end,
            styles = function(...)
                return require("witch-line.core.highlight").inspect(...)
            end,
        },
        statusline = function(...)
            return require("witch-line.core.statusline").inspect(...)
        end,
    },
}

--- Completion function for the :WitchLine command.
--- Walks the COMMANDS trie to find matching subcommand completions.
---@param arg_lead string  The current argument being completed.
---@param cmd_line string  The full command line so far.
---@param cursor_pos integer  Cursor position in the command line.
---@return string[] completions  List of matching subcommand names.
local function get_trie_completions(arg_lead, cmd_line, cursor_pos)
    local args = vim.split(cmd_line, "%s+")

    table.remove(args, 1)

    local node = COMMANDS
    for i = 1, #args - 1 do
        node = node[args[i]]
        if not node then
            return {}
        end
    end

    if type(node) ~= "table" then
        return {}
    end

    local completions = {}
    for key in pairs(node) do
        if key ~= FALLBACK_KEY and key:find("^" .. vim.pesc(arg_lead)) then
            completions[#completions + 1] = key
        end
    end
    table.sort(completions)
    return completions
end

vim.api.nvim_create_user_command("WitchLine", function(a)
    local args = a.fargs
    if #args < 1 then
        return
    end

    local arg = args[1]
    local work = COMMANDS[arg]
    for i = 2, #args do
        arg = args[i]
        work = work[arg]
    end

    if type(work) == "function" then
        work(arg, a)
    elseif type(work) == "table" then
        local fallback = work[FALLBACK_KEY]
        if type(fallback) == "function" then
            fallback(arg, a)
        else
            require("witch-line.utils.notifier").error("WitchLine: Incomplete command. Subcommand required.")
        end
    end
end, {
    nargs = "*",
    complete = get_trie_completions,
})
return M
