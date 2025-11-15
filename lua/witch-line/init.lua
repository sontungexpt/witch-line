local require, vim, type = require, vim, type

local M = {}

---@alias UserConfig.Disabled {filetypes: string[], buftypes: string[]}
--- The full user configuration for Witch-Line.
---@class UserConfig : table
--- Abstract components that are **not directly rendered**,
--- but may be inherited or referenced by other components.
--- Typically used to define shared layouts or reusable base definitions.
---@field abstracts CombinedComponent[]|nil
---
--- Components that are **actually rendered** in the statusline.
--- These can inherit or reference abstract components to build complex layouts.
---@field components CombinedComponent[]
---@field disabled UserConfig.Disabled|nil Filetypes/buftypes where statusline is disabled.
---@field cache_full_scan boolean|nil Perform full plugin scan for cache expiration. Default false.
---@field cache_cleared_notification boolean|nil Show notification when cache is cleared. Default true.
---@field cache_func_strip boolean|nil Strip debug info when caching dumped functions. Default false.

--- Apply missing default configuration values to the user-provided config.
--- Ensures required fields exist (such as `disabled` and `components`)
--- and fills them with the default values when absent or invalid.
---
--- @param user_configs UserConfig|nil The user configuration table to normalize.
--- @return UserConfig normalized The user config with defaults safely applied.
local use_default_config = function(user_configs)
  user_configs = type(user_configs) == "table" and user_configs or {}
  if type(user_configs.disabled) ~= "table" then
    user_configs.disabled = {
      buftypes = {
        "terminal",
      },
    }
  end
  user_configs.cache_cleared_notification = user_configs.cache_cleared_notification or true
  return user_configs
end

--- Apply default components if cache was not loaded.
--- @param user_configs UserConfig The config table to modify.
--- @param cached boolean Whether cache exists (skip defaults if cached).
--- @return UserConfig The config table with components applied if missing.
local apply_default_components = function(user_configs, cached)
  if not cached then
    local components = user_configs.components
    user_configs.components = (type(components) ~= "table" or next(components) == nil) and
        require("witch-line.constant.default") or components
  end
  return user_configs
end

--- @param user_configs UserConfig|nil user_configs
M.setup = function(user_configs)
  local Cache = require("witch-line.cache")
  local conf_checksum = Cache.config_checksum(user_configs)
  user_configs = use_default_config(user_configs)

  -- Read cache
  local DataAccessor = Cache.read(
    conf_checksum,
    user_configs.cache_full_scan,
    user_configs.cache_cleared_notification
  )


  local CACHE_MODS = {
    "witch-line.core.manager.event",
    "witch-line.core.manager.timer",
    "witch-line.core.manager",
    "witch-line.core.statusline",
    "witch-line.core.highlight",
  }

  if DataAccessor then
    for i = 1, #CACHE_MODS do
      require(CACHE_MODS[i]).load_cache(DataAccessor)
    end
  end

  apply_default_components(user_configs, DataAccessor ~= nil)
  require("witch-line.core.handler").setup(user_configs, DataAccessor)
  require("witch-line.core.statusline").setup(user_configs.disabled)

  vim.api.nvim_create_autocmd("VimLeavePre", {
    once = true,
    callback = function()
      if not Cache.loaded() then
        DataAccessor = Cache.DataAccessor
        for i = 1, #CACHE_MODS do
          require(CACHE_MODS[i]).on_vim_leave_pre(DataAccessor)
        end
        Cache.save(conf_checksum, user_configs.cache_func_strip)
      end
    end,
  })

  vim.api.nvim_create_autocmd("CmdlineEnter", {
    once = true,
    callback = function()
      require("witch-line.command")
    end,
  })
end

return M
