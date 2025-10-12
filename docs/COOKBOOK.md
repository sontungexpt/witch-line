The cookbook is a collection of recipes that demonstrate how to use various features of the software. Each recipe provides step-by-step instructions, code examples, and explanations to help you understand and implement specific functionalities.

## Navigation

- ⚙️ [Component Fields](#-component-fields)
  - 🗒️ [Notes](#-notes)
  - 🎣 [Hooks to Access Component Data](#-hooks-to-access-component-data)
  - 🔡 [Global Accessible Fields](#-global-accessible-fields)
  - 🧰 [Basic Fields](#-basic-fields)
  - 🧩 [Referencing Fields](#-referencing-fields)
  - 🚀 [Advanced Fields](#-advanced-fields)
  - 🧪 [Component Function Lifecycle](#-component-function-lifecycle)

## ⚙️ Component Fields

### ⚠️ Important Notes (Read Before Creating Components)

Important about function fields to make the cache work properly:

- Function fields should be pure functions without side effects.
- They should only depend on their input parameters and not have any up-values.
- The up-values allowed are only global variables such as `vim`, `package`, `require`.
- The tips to remove up-values:
  - Move the up-value inside the function.
  - If you are using a module, require it inside the function.
  - If you are using a global variable, use `vim` or `package` directly inside the function.

Example of a pure function:

```lua
local api = vim.api -- Not allowed, as it's an up-value you need to move it inside the function like below
local builtin = require("witch-line.builtin") -- Not allowed, as it's an up-value you need to move it inside the function like below


local component = {
  id = "identifier",
  update = function(self, session_id)
    local builtin = require("witch-line.builtin") -- Allowed, as it's inside the function
    local api = vim.api -- Allowed, as it's a global API call
    return api.nvim_buf_get_name(0) -- Depends only on the current buffer
  end,
}

```

### 🎣 Hooks to Access Component Data

WitchLine provides some hooks to access data in module `witch-line.core.manager.hook`.

- `use_static(comp)`: Access the static field of the component or from referenced component.
- `use_context(comp, session_id)`: Access the context field of the component or from referenced component for the given session.
- `use_event_info(comp, session_id)`: Access the data event that triggered the update for the component in the given session. The result is the argument passed to the event callback in vim.api.nvim_create_autocmd.
- `use_style(comp, session_id)`: Access the style of the component after resolving all the references and function calls for the given session. When the returned style is updated, the highlight will be updated automatically.

### 🔡 Global Accessible Fields

- **static**:

| **Type** | **Description**                                                                                                                           |
| -------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `table`  | A table that holds static data for the component.                                                                                         |
| `string` | A module path that returns a table. This is useful when you want to lazily load the static data. (This also helps reduce cache file size) |
| `nil`    | No static data for the component.                                                                                                         |

**Description**: A table that holds static data for the component. It can be used to store configuration or other immutable values of component.

When a component has a `static` field or reference `static` from another component, Then the user can access the static field by using the hook `require("witch-line.core.manager.hook").use_static(comp)`.

Tricks:

- If you ensure that the component has a static field by self not referencing other components, then you can use the `self.static` directly in any function of the component like `init`, `update`, etc for better performance.

**Example**:

```lua
local component = {
    static = {
        config_value = true,
        another_value = "example",
        icon = "⚡"
    },
    update = function(self, session_id)
        return self.static.icon .. " updated text" -- Using self.static directly
    end,
    init = function(self, session_id)
      local hook = require("witch-line.core.manager.hook") -- Use hook to access static
      local static = hook.use_static(self)
      print(static.config_value) -- true
    end
}
```

- **context**:

  | **Type**:                                | **Description**                                                                                                                         |
  | ---------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
  | `table`                                  | A table that holds dynamic data for the component.                                                                                      |
  | `string`                                 | A module path that returns a table. It's useful when you want to lazily load the context data. (This also helps reduce cache file size) |
  | `fun(self, session_id): table \| string` | A function that returns a table or a module path.                                                                                       |

  **Description**: A table or a function that holds dynamic data for the component. It can be used to store values that can change frequently and are reactive.

  When a component has a `context` field or reference `context` from another component, Then the user can access the context field by using the hook `require("witch-line.core.manager.hook").use_context(comp, session_id)`.

  Tricks:

  - If you ensure that the context is same for all sessions by self not referencing other components (usually when context is a static table or a string path), then you can use the `self.context` directly in any function of the component like `init`, `update`, etc for better performance.

  **Example**:

  - Type: `string`

  ```lua
  local component = {
    context = "my.module.path",

    update = function(self, session_id)
        local hook = require("witch-line.core.manager.hook") -- Use hook to access context
        local ctx = hook.use_context(self, session_id) --- The ctx is the table returned by the module path
        return "Dynamic Value: " .. ctx.dynamic_value
    end
  }
  ```

  - Type: `table`

  ```lua
  local component = {
    context = {
        dynamic_value = 42,
        another_dynamic_value = "dynamic"
    },
    update = function(self, session_id)
        local hook = require("witch-line.core.manager.hook") -- Use hook to access context
        local ctx = hook.use_context(self, session_id)

        -- You can also use self.context directly if you ensure that context is same for all sessions
        -- local ctx = self.context

        return "Dynamic Value: " .. ctx.dynamic_value
    end
  }
  ```

  - Type: `fun(self, ctx, static, session_id) -> table`

  ```lua
  local component = {
    context = function(self, ctx, static, session_id)
        return {
            dynamic_value = math.random(1, 100), -- Random value between 1 and 100
            another_dynamic_value = os.date("%Y-%m-%d %H:%M:%S") -- Current date and time
        }
    end,
    update = function(self, session_id)
        local hook = require("witch-line.core.manager.hook") -- Use hook to access context
        local ctx = hook.use_context(self, session_id)
        return "Dynamic Value: " .. ctx.dynamic_value
    end
  }
  ```

### 🧰 Basic Fields

- **id**: (Very Important)

  **Type**: `string | number`

  **Description**: A unique identifier for the component. It's allow an component to be referenced by other components. The id must be different from default components provided by WitchLine. You can see the list of default ids in the [Default Components](./../README.md#-default-components) section.

  **Example**:

  ```lua
  local component = {
      id = "my_component"
  }
  ```

- **lazy**:

  | **Type** | **Description**                                      |
  | -------- | ---------------------------------------------------- |
  | `true`   | The component will be loaded lazily.                 |
  | `false`  | The component will be loaded immediately.            |
  | `nil`    | The component will be loaded lazily (default value). |

  **Description**: A flag that indicates whether the component should be loaded lazily. If set to `true`, the component will only be loaded when it is needed, which can help improve performance. If not provided, the component will be loaded lazily.

  **Example**:

  ```lua
  local component = {
      lazy = true
  }
  ```

- **version**:

  **Type**: `number | string | nil`

  **Description**: The version of the component. This can be used to manage cache manually. If the version is changed, the component will be reloaded even if it is cached. This is useful when you want to manually invalidate the cache for a component. If not provided, the cache will use all the fields of the component to determine if it needs to be reloaded (This will be slower).

  **Example**:

  ```lua
  local component = {
      version = 2
  }
  ```

- **events**:

  | **Type**   | **Description**                                              |
  | ---------- | ------------------------------------------------------------ |
  | `string[]` | A list of events that the component listens to.              |
  | `string`   | A single event that the component listens to.                |
  | `nil`      | The component will not listen to any events (default value). |

  **Description**: A list of events that the component listens to. When any of these events are triggered, the component will be updated. If not provided, the component will not listen to any events. Type `:h autocmd-events` in Neovim to see the list of available events.

  **Example**:

  - Type: `string[]`

  ```lua
  local component = {
      events = {"BufEnter", "CursorHold"}
  }
  ```

  - Type: `string`

  ```lua
  local component = {
      events = "BufEnter"
  }
  ```

- **user_events**:

  | **Type**   | **Description**                                                     |
  | ---------- | ------------------------------------------------------------------- |
  | `string[]` | A list of user-defined events that the component listens to.        |
  | `string`   | A single user-defined event that the component listens to.          |
  | `nil`      | The component will not listen to any user-defined events (default). |

  **Description**: A list of user-defined events that the component listens to. When any of these events are triggered, the component will be updated. If not provided, the component will not listen to any user-defined events. You can trigger a user-defined event using `vim.api.nvim_exec_autocmds("User", {pattern = "YourEventName"})`.

  **Example**:

  - Type: `string[]`

  ```lua
  local component = {
      user_events = {"LazyLoad", "AnotherEvent"}
  }
  ```

  - Type: `string`

  ```lua
  local component = {
      user_events = "LazyLoad"
  }
  ```

- **timing**:

  | **Type** | **Description**                                                                |
  | -------- | ------------------------------------------------------------------------------ |
  | `true`   | The component will be updated every 1000 milliseconds (default debounce time). |
  | `number` | The component will be updated every specified number of milliseconds.          |
  | `nil`    | The component will not rely on timer-based updates (default value).            |

  **Description**: The time in milliseconds to debounce updates for the component. If set to `true`, it will use a default debounce time of 1000 milliseconds. If not provided, the component will not rely on timer-based updates.

  **Example**:

  - Type: `true`

  ```lua
  local component = {
      timing = true -- Default debounce time of 1000ms
  }
  ```

  - Type: `number`

  ```lua
  local component = {
      timing = 500 -- Debounce time of 500ms
  }
  ```

- **temp**:

  **Type**: `any`

  **Description**: Any temporary data that you want to store in the component instance. The data inside this field will not be cached, so you need to set them in any function like `init`, `update`, etc. This is useful for storing state or other information that should not persist across Neovim restarts. If the value is not a table, the `temp` field will be removed when restarting Neovim. If is a `table`, then the table will be emptied when restarting Neovim.

  **Example**:

  ```lua
  local component = {
      -- Empty table to hold temporary datas. The datas inside this table will not be cached so you need to set them in any function like init or update.
      temp = {},
      -- If a temp is not a table, the temp field will be removed when restarting neovim.
      -- or temp = "",
      init = function(self, session_id)
        -- If temp is a table, and you set temp as a component field then you can do something like this to initialize the temp.current_state values because the temp field is still be a empty table when restarting neovim.
        self.temp.current_state = "initial"

        -- But if temp is not a table, then you need to set it like this.
        -- The temp field will be removed when restarting neovim, so you need to set it in init or any function that is called when the component is created.
        -- self.temp = "initial"
      end,
      update = function(self, session_id)
          -- You can use self.temp.current_state here
          return "Current State: " .. (self.temp.current_state or "unknown")
      end}
  ```

- **flexible**:

  **Type**: `number | nil`

  **Description**: A priority value that determines how the component behaves when there is limited space in the status line. If the total width of all components exceeds the available space, components with higher `flexible` values will be truncated or hidden first. If not provided, the component will not be flexible and will always be displayed in full.

  **Example**:

  ```lua
  local component = {
      flexible = 2 -- Higher priority for truncation or hiding
  }
  ```

- **padding**:

  **Alias**: `PaddingFunc` : `fun(self, session_id): number | nil`

  | **Type**                                                                      | **Description**                                                                            |
  | ----------------------------------------------------------------------------- | ------------------------------------------------------------------------------------------ |
  | `number`                                                                      | The padding applied to both sides of the component                                         |
  | `PaddingFunc`                                                                 | A function that returns the padding for both sides, or a table with left and right fields. |
  | `{ left: number \| PaddingFunc \| nil, right: number \| PaddingFunc \| nil }` | A table with `left` and `right` fields to specify different padding for each side.         |

  **Description**: The padding to be applied to the component. It can be a number, a function, or a table with `left` and `right` fields. If not provided, a default padding of 1 space will be applied to both sides of the component.

  - Note: Padding is applied inner separator if separator is provided. For example, if padding = 1 and separator = "|", the output will be "| text |".

  **Example**:

  - Type: `number`

  ```lua
  local component = {
      padding = 2 -- Adds 2 spaces on both sides
  }
  ```

  - Type: `PaddingFunc`

  ```lua
  local component = {
      padding = function(self, session_id)
          return 3 -- Adds 3 spaces on both sides
      end
  }
  ```

  - Type: `{ left: number, right: number }`

  ```lua
  local component = {
      padding = { left = 1, right = 2 } -- Adds 1 space on the left and 2 spaces on the right
  }
  ```

  - Type: `{ left: PaddingFunc, right: PaddingFunc }`

  ```lua
  local component = {
      padding = {
          left = function(self, session_id) return 1 end,
          right = function(self, session_id) return 2 end
      } -- Adds 1 space on the left and 2 spaces on the right
  }
  ```

  - Type: `nil`

  ```lua
  local component = {
      padding = nil -- Adds 1 space on both sides (default behavior)
  }
  ```

- **init**:

  | **Type**                     | **Description**                                                                                  |
  | ---------------------------- | ------------------------------------------------------------------------------------------------ |
  | `string`                     | A module path that returns a function. This is useful when you want to lazily load the function. |
  | `fun(self, session_id): nil` | A function that initializes the component. It is called once when the component is created.      |

  **Description**: A function that initializes the component. It is called once when the component is created right after the component is managed by WitchLine.

  **Example**:

   - Type: `fun(self, session_id): nil`

  ```lua
  local component = {
      init = function(self, session_id)
          -- Initialization code here
      end
  }
  ```

    - Type: `string`

  ```lua
  -- my/module/path.lua
  local vim = vim
  return function(self, session_id)
    -- Initialization code here
  end


  -- In your component definition
  local component = {
    init = "my.module.path" -- The module should return a function
  }
  ```

  - Some tricks:

  ```lua
    local component = {
        init = function(self, session_id)
            local hook = require("witch-line.core.manager.hook")
            local static = hook.use_static(self) -- Use hook to access static
            local ctx = hook.use_context(self, session_id) -- Use hook to access context

              -- You can set static values here
            static.icon = "⚡"

              -- You can also set ctx values here if ctx is a static value and not a function like a table
            ctx.some_value = 42

            -- You can also add autocmds here
            vim.api.nvim_create_autocmd("BufWritePost", {
                pattern = "*",
                callback = function()
                    -- This will trigger an update for the component when the event is fired
                    require("witch-line.core.handler").refresh_comp_graph(self)
                end
            })
          end,
          update = function(self, session_id)
            local hook = require("witch-line.core.manager.hook")
            local static = hook.use_static(self) -- Use hook to access static
            return static.icon .. " updated text"
          end
    }
  ```

- **style**:

  | **Type**                                                    | **Description**                                                                                                                   |
  | ----------------------------------------------------------- | --------------------------------------------------------------------------------------------------------------------------------- |
  | `string`                                                    | A highlight group name to be applied to the component.                                                                            |
  | `vim.api.keyset.highlight`                                  | A static highlight group to be applied to the component.                                                                          |
  | `nil`                                                       | No specific highlight group will be applied (default behavior).                                                                   |
  | `fun(self, session_id): string \| vim.api.keyset.highlight` | A function that returns a highlight group. This can be used to create dynamic styles based on the current state of the component. |

  **Description**: The highlight style to be applied to the component.

  **Example**:

  - Type: `vim.api.keyset.highlight`

  ```lua
  local component = {
      style = {
          fg = "#ffffff",
          bg = "#000000",
      }
  }
  ```

  - Type: `fun(self, session_id) -> vim.api.keyset.highlight`

  ```lua
  local component = {
      style = function(self, session_id)
        local static = require("witch-line.core.manager.hook").use_static(self) -- Use hook to access static
        if static.config_value then
            return { fg = "#00ff00" } -- Green text if config_value is true
        else
            return { fg = "#ff0000" } -- Red text if config_value is false
        end
      end
  }
  ```

- **pre_update**:

  **Type**: `fun(self, session_id) -> nil`

  **Description**: A function that is called before the component is updated. It is called every time the component needs to be rerendered, right before the `update` function is called. This can be used to perform any necessary actions or calculations before the component is updated.

  **Example**:

  ```lua
  local component = {
    pre_update = function(self, session_id)
            -- Pre-update code here
    end
  }
  ```

- **update**:
  **Type**: `fun(self, session_id): string , vim.api.keyset.highlight|string|nil`

  **Description**: A function that updates the component. It is called every time the component needs to be rerendered. It should return the text to be displayed and the highlight properties to be applied.

  The reason for the second return value is to allow dynamic highlights based on the current state of the component. Although we had the `style` field to define
  style, but sometimes the style needs to change based on the value, and this allows for that flexibility.

  **Example**:

  ```lua
  local component = {
      update = function(self, session_id)
          -- Update code here
          return "updated text", { fg = "#ffffff", bg = "#000000" } -- Return text and highlight
      end
  }
  ```

- **post_update**:

  **Type**: `fun(self, session_id) -> nil`

  **Description**: A function that is called after the component is updated. It is called every time the component is rerendered, right after the `update` function is called. This can be used to perform any necessary actions or calculations after the component is updated.

  **Example**:

  ```lua
  local component = {
      post_update = function(self, session_id)
          -- Post-update code here
      end
  }
  ```

- **min_screen_width**:

  | **Type**                        | **Description**                                                                              |
  | ------------------------------- | -------------------------------------------------------------------------------------------- |
  | `number`                        | The minimum screen width required for the component to be displayed.                         |
  | `fun(self, session_id): number` | A function that returns the minimum screen width required for the component to be displayed. |
  | `nil`                           | No minimum screen width requirement (default behavior).                                      |

  **Description**: The minimum screen width required for the component to be displayed. If the screen width is less than this value, the component will not be rendered. This can be used to hide components on smaller screens or when there is not enough space to display them properly.

  **Example**:

  - Type: `number`

  ```lua
  local component = {
      min_screen_width = 80 -- Component will only be displayed if screen width is at least 80
  }
  ```

  - Type: `fun(self, session_id) -> number`

  ```lua
  local component = {
      min_screen_width = function(self, session_id)
          return session_id and 100 or 50 -- Dynamic minimum screen width based on session_id
      end
  }
  ```

- **hidden**:

  | **Type**                         | **Description**                                                                        |
  | -------------------------------- | -------------------------------------------------------------------------------------- |
  | `boolean`                        | A flag that determines whether the component is hidden or not.                         |
  | `fun(self, session_id): boolean` | A function that returns a boolean to determine whether the component is hidden or not. |
  | `nil`                            | The component will not be hidden (default behavior).                                   |

  **Description**: A flag that determines whether the component is hidden or not. If set to `true`, the component will not be rendered. This can be used to conditionally hide components based on certain criteria.

- **Example**:

  - Type: `boolean`

  ```lua
  local component = {
    hidden = true -- Component will always be hidden
  }
  ```

  - Type: `fun(self, session_id) -> boolean`

  ```lua
  local component = {
      hidden = function(self, session_id)
          local static = require("witch-line.core.manager.hook").use_static(self) -- Use hook to access static
          return static.config_value -- Dynamic hiding based on config_value
      end
  }
  ```

- **left**:

  | **Type**                        | **Description**                                                                     |
  | ------------------------------- | ----------------------------------------------------------------------------------- |
  | `string`                        | A static string to be used as the left separator of the component.                  |
  | `fun(self, session_id): string` | A function that returns a string to be used as the left separator of the component. |

  **Description**: The left separator of the component.

  **Example**:

  - Type: `string`

  ```lua
  local component = {
    -- semi circle separator
    left = "⦅" -- Static left part
  }
  ```

  - Type: `fun(self, session_id) -> string`

  ```lua
  local component = {
    left = function(self, session_id)
        local static = require("witch-line.core.manager.hook").use_static(self) -- Use hook to access static
        return static.icon .. " ⦅" -- Dynamic left part based on static values
    end
  }
  ```

- **right**:
  | **Type** | **Description** |
  | ------------------------------- | ------------------------------------------------------------------------------------ |
  | `string` | A static string to be used as the right separator of the component. |
  | `fun(self, session_id): string \| nil` | A function that returns a string to be used as the right separator of the component. |
  | `nil` | No right separator will be used (default behavior). |

**Description**: The right separator of the component.

**Example**:

- Type: `string`

```lua
local component = {
    -- right semi circle separator
    right = "⦆" -- Static right part
}
```

- Type: `fun(self, session_id) -> string`

```lua
local component = {
    right = function(self, session_id)
        local static = require("witch-line.core.manager.hook").use_static(self) -- Use hook to access static
        return static.icon .. " ⦆" -- Dynamic right part based on static values
    end
}
```

- **left_style**:

  **Alias**: `SepStyle` : `0 | 1 | 2 | 3`

  | **Values**: | **Description**                                                                                                                                                     |
  | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
  | 0           | Inherit from component style                                                                                                                                        |
  | 1           | The foreground color of the separator is the foreground color of the component, and the background color of the separator is `NONE`.                                |
  | 2           | The foreground color of the separator is the background color of the component, and the background color of the separator is `NONE`.                                |
  | 3           | The foreground color of the separator is the background color of the component, and the background color of the separator is the foreground color of the component. |

  | **Type**                                                                       | **Description**                                                                                                                   |
  | ------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------- |
  | `SepStyle`                                                                     | A predefined style based on the component's style.                                                                                |
  | `vim.api.keyset.highlight`                                                     | A static highlight group to be applied to the left part of the component.                                                         |
  | `nil`                                                                          | No specific highlight group will be applied to the left part (default behavior).                                                  |
  | `fun(self, session_id): vim.api.keyset.highlight \| SepStyle \| string \| nil` | A function that returns a highlight group. This can be used to create dynamic styles based on the current state of the component. |
  | `string`                                                                       | A highlight group name to be applied to the left part of the component.                                                           |

  **Description**: The highlight style to be applied to the left part of the component.

  **Example**:

  - Type: `SepStyle`

  ```lua
  local component = {
      left_style = 1
  }
  ```

  - Type: `vim.api.keyset.highlight`

  ```lua
  local component = {
      left_style = {
          fg = "#ffffff",
          bg = "#000000",
      }
  }
  ```

  - Type: `fun(self, ctx, static, session_id) -> vim.api.keyset.highlight`

  ```lua
  local component = {
      left_style = function(self, ctx, static, session_id)
          if static.config_value then
              return { fg = "#00ff00" } -- Green text if config_value is true
          else
              return { fg = "#ff0000" } -- Red text if config_value is false
          end
      end
  }
  ```

  - Type: `fun(self, session_id) -> SepStyle`

  ```lua
  local component = {
      left_style = function(self, session_id)
          if self.config_value then
              return 1 -- Use SepStyle 1 if config_value is true
          else
              return 2 -- Use SepStyle 2 if config_value is false
          end
      end
  }
  ```

  - Type: `string`

  ```lua
    local component = {
        left_style = "MyHighlightGroup" -- Use a custom highlight group
    }
  ```

- **right_style**:

  **Alias**: `SepStyle` : `0 | 1 | 2 | 3`

  | **Values**: | **Description**                                                                                                                                                     |
  | ----------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
  | 0           | Inherit from component style                                                                                                                                        |
  | 1           | The foreground color of the separator is the foreground color of the component, and the background color of the separator is `NONE`.                                |
  | 2           | The foreground color of the separator is the background color of the component, and the background color of the separator is `NONE`.                                |
  | 3           | The foreground color of the separator is the background color of the component, and the background color of the separator is the foreground color of the component. |

  | **Type**                                                                       | **Description**                                                                                                                   |
  | ------------------------------------------------------------------------------ | --------------------------------------------------------------------------------------------------------------------------------- |
  | `SepStyle`                                                                     | A predefined style based on the component's style.                                                                                |
  | `vim.api.keyset.highlight`                                                     | A static highlight group to be applied to the right part of the component.                                                        |
  | `nil`                                                                          | No specific highlight group will be applied to the right part (default behavior).                                                 |
  | `fun(self, session_id): vim.api.keyset.highlight \| SepStyle \| string \| nil` | A function that returns a highlight group. This can be used to create dynamic styles based on the current state of the component. |
  | `string`                                                                       | A highlight group name to be applied to the right part of the component.                                                          |

  **Description**: The highlight style to be applied to the right part of the component. It can be a static highlight group or a function that returns a highlight group. If not provided, the default highlight group will be used. The function can be used to create dynamic styles based on the current state of the component, this accepts the `context` field as the second argument, and `static` as the third argument, so you can use those values to determine the style dynamically.

  **Example**:

  - Type: `SepStyle`

  ```lua
  local component = {
      right_style = 1
  }
  ```

  - Type: `vim.api.keyset.highlight`

  ```lua
  local component = {
      right_style = {
          fg = "#ffffff",
          bg = "#000000",
      }
  }
  ```

  - Type: `fun(self, ctx, static, session_id) -> vim.api.keyset.highlight`

  ```lua
  local component = {
      right_style = function(self, ctx, static, session_id)
          if static.config_value then
              return { fg = "#00ff00" } -- Green text if config_value is true
          else
              return { fg = "#ff0000" } -- Red text if config_value is false
          end
      end
  }
  ```

  - Type: `fun(self, ctx, static, session_id) -> SepStyle`

  ```lua
      local component = {
          right_style = function(self, ctx, static, session_id)
              if static.config_value then
                  return 1 -- Use SepStyle 1 if config_value is true
              else
                  return 2 -- Use SepStyle 2 if config_value is false
              end
          end
      }
  ```

- **on_click**:

  **Alias**: `OnClickFunc` : `fun(self: ManagedComponent,  minwid: 0, click_times: number, mouse button: "l"|"r"|"m", modifier_pressed: "s"|"c"|"a"|"m"): nil`

  | **Type**                                | **Description**                                                            |
  | --------------------------------------- | -------------------------------------------------------------------------- |
  | `nil`                                   | The component will not have any click handler (default behavior).          |
  | `string`                                | The name of a global function to be called when the component is clicked.  |
  | `OnClickFunc`                           | A function that will be called when the component is clicked.              |
  | `{name: string, callback: OnClickFunc}` | A table with `name` and `callback` fields to define a named click handler. |

  **Description**: A function name or a function that is called when the component is clicked. It can be a string representing the name of a global function, a function itself, or a table with `name` and `callback` fields. If it's a table, the `name` field is used to identify the click handler, and the `callback` field is the function that will be called when the component is clicked.

  The function accepts the following parameters:
  | **Parameter** | **Type** | **Description** |
  | -------------------- | ---------------------------- | ---------------------------------------------------- |
  | `self` | `ManagedComponent` | The component instance. |
  | `minwid` | `number` | The minimum width of the component. |
  | `click_times` | `number` | The number of clicks (1 for single click, 2 for double click, etc.). |
  | `mouse button` | `"l" \| "r" \| "m"` | The mouse button that was clicked (`"l"` for left, `"r"` for right, `"m"` for middle). |
  | `modifier_pressed` | `"s" \| "c" \| "a" \| "m"` | The modifier key that was pressed (`"s"` for Shift, `"c"` for Control, `"a"` for Alt, `"m"` for Meta). |

  **Example**:

  ```lua
  local component = {
      on_click = function(self, minwid, button, clicks, mouse_pos)
          -- Click handling code here
          print("Component clicked with button: " .. button .. ", clicks: " .. clicks)
      end
  }
  ```

### 🔗 Referencing Fields

An component can reference other components for some of its fields. This allows for reusing common configurations and creating more complex components by combining simpler ones. The following fields can reference other components:

- **inherit**:

  **Type**: `CompId | nil`

  **Description**: The id of another component to inherit fields from. The fields of the inherited component will be merged with the fields of the current component. If a field is defined in both components, the value from the current component will take precedence. This allows for creating base components that can be extended by other components.

  The component inherited from another component will be updated when the parent component is updated. This means that if the parent component changes, the child component will also reflect those changes. If the parent is hidden, the child component will also be hidden.

  **Example**:

  ```lua
  local base_component = {
      id = "base_component",
      events = {"BufEnter"},
      timing = true,
      style = { fg = "#ffffff", bg = "#000000" },
      padding = 1,
      update = function(self, ctx, static, session_id)
          return "Base Component"
      end
  }

  local child_component = {
      -- So the child will update on BufEnter event, update every 1000ms (default timing for true),
      -- and have the same style and padding as the base component.
      id = "child_component",
      inherit = "base_component",
      update = function(self, ctx, static, session_id)
          return "Child Component"
      end
  }

  ```

- **ref**:

  **Type**: `table`

  **Description**: A table that maps fields of the current component to the ids of other components. This allows for referencing specific fields from other components without inheriting all their fields. The fields that can be referenced are:

  | Field              | Type                 | Description                                                                               |
  | ------------------ | -------------------- | ----------------------------------------------------------------------------------------- |
  | `events`           | `CompId \| CompId[]` | The component will be updated when the referenced events are triggered.                   |
  | `user_events`      | `CompId \| CompId[]` | The component will be updated when the referenced user-defined events are triggered.      |
  | `timing`           | `CompId \| CompId[]` | The component will be updated based on the timing provided by the referenced components.  |
  | `style`            | `CompId`             | The style of the component will be taken from the referenced component.                   |
  | `static`           | `CompId`             | The component will be updated with static values from the referenced component.           |
  | `context`          | `CompId`             | The component will be updated with context values from the referenced component.          |
  | `hidden`           | `CompId \| CompId[]` | The component will be hidden when the referenced components are hidden.                   |
  | `min_screen_width` | `CompId \| CompId[]` | The component will be updated with min screen width logic from the referenced components. |

  **Example**:

  ```lua
  local event_component = {
      id = "event_component",
      events = {"BufEnter", "CursorHold"},
      static = { event_info = "Event Info" },
      update = function(self, ctx, static, session_id)
          return "Event Component"
      end
  }
  local style_component = {
      id = "style_component",
      style = { fg = "#00ff00", bg = "#000000" },
      update = function(self, ctx, static, session_id)
          return "Style Component"
      end
  }
  local main_component = {
      id = "main_component",
      ref = {
          static = "event_component", -- The main component will have static values from event_component, In this case static = { event_info = "Event Info" }
          events = "event_component", -- The main component will update on BufEnter and CursorHold events. In this case, the main component will update when event_component updates.
          style = "style_component"    -- The main component will have the style defined in style_component, In this case fg = "#00ff00", bg = "#000000"
      },
      update = function(self, ctx, static, session_id)
          -- static.event_info is available here because we referenced static from event_component
          return "Main Component"
      end
  }
  ```

### 🚀 Advanced Fields

- **{...}**:

  **Type**: `Component[]`

  **Description**: A list of child components that will be rendered inside the current component. This allows for creating nested components and more complex layouts. The child components will be set `inherit` by the id of the parent component, so they will inherit fields from the parent component unless they override them. This is useful for creating groups of components that share common configurations.

  **Example**:

  ```lua
  local parent = {
      id = "parent_component",
      timing = true,
      style = { fg = "#ffffff", bg = "#000000" },
      padding = 1,


      {
          id = "child_component_1",
          -- So the child will have the same style and padding as the parent component.
          -- The child will also update every 1000ms (default timing for true).
          update = function(self, ctx, static, session_id)
              return "Child 2"
          end
      },
      {
          id = "child_component_2",
          -- This child will also have the same style as the parent component, but will override the padding.
          -- The child will also update every 1000ms (default timing for true).
          padding = 2, -- This child will override the padding of the parent component.
          update = function(self, ctx, static, session_id)
              return "Child 3"
          end
      }

  }
  ```

### 🧪 Component Function Lifecycle

- `init` : Called once when the component is created. After `WitchLine` manages the component. (Such as setting up autocmds, etc.)
- `pre_update` : Called every time the component needs to be update, right before calling `min_screen_width` -> `hidden` -> `update` functions.
- `min_screen_width` : Called every time the component needs to be update, right after calling `pre_update` function, right before calling `hidden` function.
- `hidden` : Called every time the component needs to be update, right after calling `min_screen_width` function, right before calling `update` function.
- `update` : Called every time the component needs to be update, right after calling `hidden` function, right before calling `padding` -> `post_update` function.
- `padding` : Called every time the component needs to be update, right after calling `update` function, to get the padding of the component.
- `post_update` : Called every time the component needs to be update, right after calling `update` function.
- `style` : Called every time the component updated successfully, after calling `update` function, to get the style of the component.
- `left` : Called every time the component updated successfully, after calling `update` function, to get the left part of the component.
- `right` : Called every time the component updated successfully, after calling `update` function, to get the right part of the component.
- `left_style` : Called every time the component updated successfully, after calling `update` function, to get the style of the left part of the component.
- `right_style` : Called every time the component updated successfully, after calling `update` function, to get the style of the right part of the component.
