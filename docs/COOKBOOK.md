## Using the Cookbook

The cookbook is a collection of recipes that demonstrate how to use various features of the software. Each recipe provides step-by-step instructions, code examples, and explanations to help you understand and implement specific functionalities.

## Navigation

- [📚 Component Fields](#-component-fields)
  - [🔍 Notes](#-notes)
  - [📚 Basic Fields](#basic-fields)
  - [📚 Referencing Fields](#referencing-fields)
  - [📚 Advanced Fields](#advanced-fields)

### Component Fields

#### 🔍 Notes

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
  update = function(self, ctx, static, session_id)
    local builtin = require("witch-line.builtin") -- Allowed, as it's inside the function
    local api = vim.api -- Allowed, as it's a global API call
    return api.nvim_buf_get_name(0) -- Depends only on the current buffer
  end,
}

```

#### Basic Fields

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

  **Type**: `boolean | nil`

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

  **Type**: `string | string[] | nil`

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

  **Type**: `string | string[] | nil`

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

- **timming**:

  **Type**: `true | number | nil`

  **Description**: The time in milliseconds to debounce updates for the component. If set to `true`, it will use a default debounce time of 1000 milliseconds. If not provided, the component will not rely on timer-based updates.

  **Example**:

  - Type: `true`

  ```lua
  local component = {
      timming = true -- Default debounce time of 1000ms
  }
  ```

  - Type: `number`

  ```lua
  local component = {
      timming = 500 -- Debounce time of 500ms
  }
  ```

- **static**:

  **Type**: `table | number | string | boolean | nil` (Any primitive type or table)

  **Description**: A table that holds static data for the component. This data is not reactive and will not trigger updates when changed. It can be used to store configuration or other information that does not change frequently. It is passed to many internal functions and can be used to customize the behavior of the component.

  **Example**:

  ```lua
  local component = {
      static = {
          config_value = true,
          another_value = "example",
          icon = "⚡"
      }
  }
  ```

- **context**:

  **Type**: `table | string | boolean | number | nil | fun(self, static, session_id) -> `any`

  **Description**: This field is quite similar to `static`, but the difference is that if it is a function, it will be called every time the component is updated and passed the result to the internal functions. This allows for dynamic context values that can change based on the current state of the component or other factors. It is useful for storing values that need to be recalculated frequently, such as the current time, random values, or values based on external conditions.

  Difference between `static` and `context`:

  - `static` is for values that do not change often and are not reactive.
  - `context` is for values that can change frequently and are reactive.

  Assume that the update function: `fun(self, ctx, static, session_id)` -> string,

  - `static`: function () return 1 end
  - `context`: function () return math.random(1, 100) end

  When the update function is called, it will receive:

  - `static`(Third argument) will always be function () return 1 end
  - `ctx`(Second argument) will be a random number between 1 and 100 every time the update function is called.

  **Example**:

  - Type: `table`

  ```lua
  local component = {
      context = {
          dynamic_value = 42,
          another_dynamic_value = "dynamic"
      }
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
      end
  }
  ```

- `**temp**`:

  **Type**: `any`

  **Description**: A table that holds temporary data for the component. This data is not reactive and will not trigger updates when changed. It can be used to store state or other information that is only relevant during the lifetime of the component. It is not passed to any internal functions and is only accessible within the component itself. It is not stored in the cache, so it will when neovim is restarted.

  **Example**:

  ```lua
  local component = {
      -- Empty table to hold temporary datas. The datas inside this table will not be cached so you need to set them in any function like init or update.
      temp = {
      },
      -- If a temp is not a table, the temp field will be removed when restarting neovim.
      -- or temp = "",
      init = function(self, ctx, static, session_id)
        self.temp.current_state = "initial"
      end,
  }
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

  **Alias**: `PaddingFunc` : `fun(self, ctx, static, session_id): number | nil`

  **Type**: `number | nil` | `PaddingFunc` | { left: number | PaddingFunc | nil, right: number | PaddingFunc | nil } | nil

  **Description**: The padding to be applied to the component. It can be a number, a function, or a table with `left` and `right` fields. If not provided, a default padding of 1 space will be applied to both sides of the component.

  - If a number is provided, it adds that many spaces on both sides of the component.
  - If a function is provided, it should return a number that specifies the padding for both sides. It accepts the `context` field as the second argument, and `static` as the third argument, so you can use those values to determine the padding dynamically.
  - If a table is provided, it can have `left` and `right` fields to specify different padding for each side. If not provided, add padding = 1 to both sides.
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
      padding = function(self, ctx, static, session_id)
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
          left = function(self, ctx, static, session_id) return 1 end,
          right = function(self, ctx, static, session_id) return 2 end
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

  **Type**: `fun(self, ctx, static, session_id) -> Nil`

  **Description**: A function that initializes the component. It is called once when the component is created right after the component is managed by WitchLine. This accepts the `context` field as the second argument, and `static` as the third argument, so you can use those values to initialize the component. This is useful for setting up any necessary state or configuration for the component before it is used.

  **Example**:

  ```lua
  local component = {
      init = function(self, ctx, static, session_id)
          -- Initialization code here
      end
  }
  ```

  - Some tricks:

  ```lua
      local component = {
          init = function(self, ctx, static, session_id)
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
          update = function(self, ctx, static, session_id)
              return static.icon .. " updated text"
          end
      }
  ```

- **style**:

  **Type**: `vim.api.keyset.highlight | nil | fun(self, ctx, static, session_id) -> vim.api.keyset.highlight | nil`

  **Description**: The highlight style to be applied to the component. It can be a static highlight group or a function that returns a highlight group. If not provided, the default highlight group will be used. The function can be used to create dynamic styles based on the current state of the component, this accepts the `context` field as the second argument, and `static` as the third argument, so you can use those values to determine the style dynamically.

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

  - Type: `fun(self, ctx, static, session_id) -> vim.api.keyset.highlight`

  ```lua
  local component = {
      style = function(self, ctx, static, session_id)
          if static.config_value then
              return { fg = "#00ff00" } -- Green text if config_value is true
          else
              return { fg = "#ff0000" } -- Red text if config_value is false
          end
      end
  }
  ```

- **pre_update**:

  **Type**: `fun(self, ctx, static, session_id) -> Nil`

  **Description**: A function that is called before the component is updated. It is called every time the component needs to be rerendered, right before the `update` function is called. This can be used to perform any necessary actions or calculations before the component is updated. It accepts the `context` field as the second argument, and `static` as the third argument, so you can use those values to perform any necessary actions before the update.

  **Example**:

  ```lua
  local component = {
      pre_update = function(self, ctx, static, session_id)
          -- Pre-update code here
      end
  }
  ```

- **update**:
  **Type**: `fun(self, ctx, static, session_id) -> string , vim.api.keyset.highlight`
  **Description**: A function that updates the component. It is called every time the component needs to be rerendered. It should return the text to be displayed and the highlight properties to be applied. It accepts the `context` field as the second argument, and `static` as the third argument, so you can use those values to determine the text and style dynamically.

  The reason for the second return value is to allow dynamic highlights based on the current state of the component. Although we had the `style` field to define
  style, but sometimes the style needs to change based on the value, and this allows for that flexibility.

  **Example**:

  ```lua
  local component = {
      update = function(self, ctx, static, session_id)
          -- Update code here
          return "updated text", vim.api.keyset.highlight
      end
  }
  ```

- **post_update**:

  **Type**: `fun(self, ctx, static, session_id) -> Nil`

  **Description**: A function that is called after the component is updated. It is called every time the component is rerendered, right after the `update` function is called. This can be used to perform any necessary actions or calculations after the component is updated. It accepts the `context` field as the second argument, and `static` as the third argument, so you can use those values to perform any necessary actions after the update.

  **Example**:

  ```lua
  local component = {
      post_update = function(self, ctx, static, session_id)
          -- Post-update code here
      end
  }
  ```

- **min_screen_width**:

  **Type**: `number | fun(self, ctx, static, session_id) -> number | nil`

  **Description**: The minimum screen width required for the component to be displayed. If the screen width is less than this value, the component will not be rendered. This can be used to hide components on smaller screens or when there is not enough space to display them properly. It can also be a function that returns a number, allowing for dynamic minimum screen widths based on the current state of the component. If it's a function, it accepts the `context` field as the second argument, and `static` as the third argument, so you can use those values to determine the minimum screen width dynamically.

  **Example**:

  - Type: `number`

  ```lua
  local component = {
      min_screen_width = 80 -- Component will only be displayed if screen width is at least 80
  }
  ```

  - Type: `fun(self, ctx, static, session_id) -> number`

  ```lua
  local component = {
      min_screen_width = function(self, ctx, static, session_id)
          return static.config_value and 100 or 50 -- Dynamic minimum screen width based on config_value
      end
  }
  ```

- **hidden**:

  **Type**: `boolean | fun(self, ctx, static, session_id) -> boolean | nil`

  **Description**: A flag that determines whether the component is hidden or not. If set to `true`, the component will not be rendered. This can be used to conditionally hide components based on certain criteria. It can also be a function that returns a boolean, allowing for dynamic hiding of the component based on the current state of the component. If it's a function, it accepts the `context` field as the second argument, and `static` as the third argument, so you can use those values to determine whether to hide the component dynamically.

- **Example**:

  - Type: `boolean`

  ```lua
  local component = {
    hidden = true -- Component will always be hidden
  }
  ```

  - Type: `fun(self, ctx, static, session_id) -> boolean`

  ```lua
  local component = {
      hidden = function(self, ctx, static, session_id)
          return static.config_value -- Dynamic hiding based on config_value
      end
  }
  ```

- **left**:

  **Type**: `string | nil | fun(self, ctx, static, session_id) -> string | nil`

  **Description**: The left separator of the component. It can be a static string or a function that returns a string. If it's a function, it accepts the `context` field as the second argument, and `static` as the third argument, so you can use those values to determine the left part dynamically. If not provided, the left part will be empty.

  **Example**:

  - Type: `string`

  ```lua
  local component = {
    -- separator
    left = "|" -- Static left part
  }  }
  ```

  - Type: `fun(self, ctx, static, session_id) -> string`

  ```lua
  local component = {
    left = function(self, ctx, static, session_id)
        return static.icon .. " |" -- Dynamic left part based on static values
    end
  }
  ```

- **right**:

  **Type**: `string | nil | fun(self, ctx, static, session_id) -> string | nil`

  **Description**: The right separator of the component. It can be a static string or a function that returns a string. If it's a function, it accepts the `context` field as the second argument, and `static` as the third argument, so you can use those values to determine the right part dynamically. If not provided, the right part will be empty.

  **Example**:

  - Type: `string`

  ```lua
  local component = {
      -- separator
      right = "| " -- Static right part
  }
  ```

  - Type: `fun(self, ctx, static, session_id) -> string`

  ```lua
  local component = {
      right = function(self, ctx, static, session_id)
          return " | " .. static.icon -- Dynamic right part based on static values
      end
  }
  ```

- **left_style**:

  **Alias**: `SepStyle` : `0 | 1 | 2 | 3`

  - 0: Inherit from component style
  - 1: The foreground color of the separator is the foreground color of the component, and the background color of the separator is `NONE`.
  - 2: The foreground color of the separator is the background color of the component, and the background color of the separator is `NONE`.
  - 3: The foreground color of the separator is the background color of the component, and the background color of the separator is the foreground color of the component.

  **Type**: `vim.api.keyset.highlight | nil | SepStyle | fun(self, ctx, static, session_id) -> vim.api.keyset.highlight | SepStyle | nil`

  **Description**: The highlight style to be applied to the left part of the component. It can be a static highlight group or a function that returns a highlight group. If not provided, the default highlight group will be used. The function can be used to create dynamic styles based on the current state of the component, this accepts the `context` field as the second argument, and `static` as the third argument, so you can use those values to determine the style dynamically.

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

  - Type: `fun(self, ctx, static, session_id) -> SepStyle`

  ```lua
  local component = {
      left_style = function(self, ctx, static, session_id)
          if static.config_value then
              return 1 -- Use SepStyle 1 if config_value is true
          else
              return 2 -- Use SepStyle 2 if config_value is false
          end
      end
  }
  ```

- **right_style**:

  **Alias**: `SepStyle` : `0 | 1 | 2 | 3`

  - 0: Inherit from component style
  - 1: The foreground color of the separator is the foreground color of the component, and the background color of the separator is `NONE`.
  - 2: The foreground color of the separator is the background color of the component, and the background color of the separator is `NONE`.
  - 3: The foreground color of the separator is the background color of the component, and the background color of the separator is the foreground color of the component.

  **Type**: `vim.api.keyset.highlight | nil | SepStyle | fun(self, ctx, static, session_id) -> vim.api.keyset.highlight | SepStyle | nil`

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

#### Referencing Fields

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
      timming = true,
      style = { fg = "#ffffff", bg = "#000000" },
      padding = 1,
      update = function(self, ctx, static, session_id)
          return "Base Component"
      end
  }

  local child_component = {
      -- So the child will update on BufEnter event, update every 1000ms (default timming for true),
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

#### Advanced Fields

- **{...}**:

  **Type**: `Component[]`

  **Description**: A list of child components that will be rendered inside the current component. This allows for creating nested components and more complex layouts. The child components will be set `inherit` by the id of the parent component, so they will inherit fields from the parent component unless they override them. This is useful for creating groups of components that share common configurations.

  **Example**:

  ```lua
  local parent = {
      id = "parent_component",
      timming = true,
      style = { fg = "#ffffff", bg = "#000000" },
      padding = 1,


      {
          id = "child_component_1",
          -- So the child will have the same style and padding as the parent component.
          -- The child will also update every 1000ms (default timming for true).
          update = function(self, ctx, static, session_id)
              return "Child 2"
          end
      },
      {
          id = "child_component_2",
          -- This child will also have the same style as the parent component, but will override the padding.
          -- The child will also update every 1000ms (default timming for true).
          padding = 2, -- This child will override the padding of the parent component.
          update = function(self, ctx, static, session_id)
              return "Child 3"
          end
      }

  }
  ```
