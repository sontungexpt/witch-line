# COOKBOOK

This guide walks you through creating components from scratch. Each section builds on the previous one — read it top-to-bottom the first time, then use the [Field Summary](#field-summary) as a quick reference.

---

## Your First Component

A component is a Lua table with two required fields: `id` (a unique name) and `update` (a function that returns text).

```lua
-- 1. Define the component
local greeting = {
  id = "my.greeting",
  update = function(self, session)
    return "Hello from witch-line!"
  end,
}

-- 2. Register it in your config
require("witch-line").setup({
  statusline = {
    global = {
      "wl.mode",          -- built-in mode indicator
      "wl.file.name",     -- built-in filename
      "%=",               -- separator (pushes right side to the right)
      "my.greeting",      -- your component (by id string)
    },
  },
})
```

**How it works:** When the statusline renders, each entry in the `global` list is resolved. Strings like `"wl.mode"` are looked up as component IDs. Tables with an `id` field are loaded directly. The `%=` is a statusline item that aligns everything after it to the right.

**Key rules:**
- `id` must be a string. Use dots as separators (`my.clock`, `my.battery`).
- `update` receives `self` (your component table) and `session` (the current render cycle). It must return a string.
- Components without `events` or `timing` update only on the next full statusline render (triggered by other components or Neovim events).

---

## Adding Data to Your Component

### `static` — internal fixed data

Use `static` for constants that never change and should not be user-overridable:

```lua
local battery = {
  id = "my.battery",
  static = {
    icon_ok = "🔋",
    icon_low = "🪫",
    icon Charging = "⚡",
    threshold = 20,
  },
  update = function(self, session)
    local level = get_battery_level()        -- your own function
    local icon = level <= self.static.threshold
        and self.static.icon_low
        or self.static.icon_ok
    return icon .. " " .. level .. "%%"
  end,
}
```

Access via `self.static.<field>`. The table is created once when the component loads.

### `config` — user-overridable values

Use `config` for values you want users to customize via `override` (see [Overriding Default Components](#overriding-default-components)):

```lua
local clock = {
  id = "my.clock",
  config = {
    format = "%H:%M",
    icon = "🕐",
  },
  update = function(self, session)
    return self.config.icon .. " " .. os.date(self.config.format)
  end,
}
```

**`static` vs `config`:** Both are accessed via `self`. The difference is that `config` values can be overridden by the user in `setup()`. Use `static` for internal constants, `config` for user-facing options.

### Custom fields

Any field you add to the table is accessible via `self`:

```lua
local comp = {
  id = "my.counter",
  count = 0,
  update = function(self, session)
    self.count = self.count + 1
    return "updates: " .. self.count
  end,
}
```

Custom fields persist across renders for the lifetime of the component.

---

## Controlling When to Update

By default, a component updates only when the full statusline re-renders. To make it update independently, use `events` or `timing`.

### `events` — react to Neovim autocmds

```lua
local mode = {
  id = "my.mode",
  events = "ModeChanged",
  update = function(self, session)
    return vim.fn.mode():upper()
  end,
}
```

This component re-renders every time the mode changes. Without `events`, it would only update when something else triggers a full statusline render.

**Event syntax** (same as `:autocmd`):

```lua
events = "BufEnter"                         -- fire on BufEnter
events = "BufEnter *.lua"                   -- only for .lua files
events = "BufEnter *.lua,*.py ++once"       -- fire once per pattern match
events = { "BufEnter", "BufLeave" }         -- multiple events
events = "User VeryLazy"                    -- user event
events = "User LazyLoad ++once"             -- user event, once
```

| Syntax | Meaning |
|---|---|
| `"EventName"` | Fire on every occurrence. |
| `"EventName pattern"` | Only when the buffer matches the pattern. |
| `"EventName pattern ++once"` | Fire once, then auto-remove (`++once` must be last). |
| `"User Name"` | User event (name passed as pattern to `nvim_create_autocmd`). |

### `timing` — periodic updates

```lua
local clock = {
  id = "my.clock",
  timing = 1000,    -- every 1000 ms
  update = function(self, session)
    return os.date("%H:%M:%S")
  end,
}
```

Set `timing = true` for a default 1000 ms interval. The timer starts when the component mounts and stops when it is hidden.

### Combining events and timing

You can use both. `events` fires on specific triggers; `timing` provides a regular heartbeat. They are independent — either one can trigger a re-render.

---

## Styling

### Static style

Set a `style` table to give your component a consistent look:

```lua
local comp = {
  id = "my.status",
  style = { fg = "#ffffff", bg = "#333333", bold = true },
  update = function(self, session)
    return "OK"
  end,
}
```

Available highlight fields: `fg`, `bg`, `bold`, `italic`, `underline`, ` strikethrough`, `sp` (special color), `reverse`. All are optional.

### Dynamic style

Use a function to change style based on state:

```lua
local comp = {
  id = "my.modified",
  style = function(self, session)
    if vim.bo.modified then
      return { fg = "#ffff00", bold = true }   -- yellow when modified
    end
    return { fg = "#888888" }                    -- grey otherwise
  end,
  update = function(self, session)
    return vim.bo.modified and "[+]" or ""
  end,
}
```

Return `nil` to use no highlight (default terminal colors).

### Inline style from `update`

Return a second value from `update` to apply a one-off highlight without defining `style`:

```lua
update = function(self, session)
  if vim.bo.modified then
    return "[+]", { fg = "#ffff00" }
  end
  return "", nil
end
```

Inline style takes precedence over `style` for that render cycle.

### Padding

Spaces around the text. Default is 1 on each side:

```lua
padding = 2                              -- 2 spaces on each side
padding = { left = 1, right = 3 }       -- asymmetric
padding = function(self, session)       -- dynamic
  return vim.bo.modified and 2 or 1
end
```

### Separators

Decorative characters on each side of the text:

```lua
left = " ", right = " "
left = function(self, session) return vim.bo.modified and "●" or "○" end
```

Separator highlight style:

```lua
left_style = 0    -- inherit from component
left_style = 1    -- sep fg = component fg, sep bg = NONE
left_style = 2    -- sep fg = component bg, sep bg = NONE
left_style = 3    -- sep fg = component bg, sep bg = component fg
left_style = { fg = "#ffffff", bg = "#333333" }  -- explicit
```

### Conditional visibility

**`hidden`** — hide the component entirely:

```lua
hidden = function(self, session)
  return vim.bo.buftype == "nofile"   -- hide in special buffers
end
```

When hidden, the component occupies no space in the statusline.

**`min_screen_width`** — hide when the terminal is too narrow:

```lua
min_screen_width = 80   -- hide if fewer than 80 columns
min_screen_width = function(self, session)
  return vim.o.columns < 120 and 80 or 120
end
```

### Flexible (hiding priority)

When space is tight, components with higher `flexible` values are hidden first:

```lua
{
  id = "my.encoding",
  flexible = 2,           -- hidden first
  update = function(self, session) return vim.bo.encoding end,
}
```

A component with `flexible = 3` is hidden before `flexible = 2`, which is hidden before `flexible = 1`. Components without `flexible` are never hidden automatically.

---

## Lifecycle

### `init` — one-time setup

Called once when the component is first loaded. Use it to set up autocmds, timers, or initialize state. There is no `session` argument.

```lua
local comp = {
  id = "my.watcher",
  init = function(self)
    self.my_state = { count = 0 }
    vim.api.nvim_create_autocmd("BufWritePost", {
      callback = function()
        self.my_state.count = self.my_state.count + 1
        -- Request a re-render of this component:
        local engine = package.loaded["witch-line.engine"]
        if engine then
          local Request = require("witch-line.engine.request")
          Request.update_comp(self)
        end
      end,
    })
  end,
  update = function(self, session)
    return "saves: " .. self.my_state.count
  end,
}
```

### `pre_update` / `post_update`

Runs before and after each render cycle:

```lua
pre_update = function(self, session)
  -- Runs before hidden, min_screen_width, and update.
  -- Good for preparing data that update will use.
end

post_update = function(self, session)
  -- Runs after the component is fully rendered.
  -- Good for side effects (logging, triggering other updates).
end
```

### Full render cycle order

```
init                    (once, at load)
  → pre_update
  → min_screen_width    (if too narrow → hidden)
  → hidden              (if true → component disappears)
  → update              (returns text + optional inline style)
  → padding
  → style               (static table, dynamic function, or named group)
  → left / right        (separator characters)
  → left_style / right_style
  → on_click
  → post_update
```

---

## Interactivity

### Click handler

```lua
local comp = {
  id = "my.clickable",
  update = function(self, session) return "click me" end,
  on_click = function(self, minwid, click_times, mouse_button, modifier_pressed)
    if mouse_button == "l" then
      vim.cmd("echo 'left click'")
    elseif mouse_button == "r" then
      vim.cmd("echo 'right click'")
    end
  end,
}
```

| Parameter | Type | Values |
|---|---|---|
| `minwid` | `number` | Window number. |
| `click_times` | `number` | 1 = single click, 2 = double click. |
| `mouse_button` | `string` | `"l"` = left, `"r"` = right, `"m"` = middle. |
| `modifier_pressed` | `string` | `"s"` = shift, `"c"` = ctrl, `"a"` = alt, `"m"` = meta. |

You can also pass a table `{ name = "global_handler_name", callback = function ... end }` or a string naming a global function.

---

## Reusing Components

### `ref` — live delegation

`ref` lets one component read another component's field values without copying. When the referenced component updates, the referring component sees the new value.

```lua
-- Provider: computes shared data
local stats = {
  id = "my.stats",
  events = "CursorMoved",
  context = function(self, session)
    return {
      total_lines = vim.fn.line("$"),
      current_line = vim.fn.line("."),
    }
  end,
}

-- Consumer: displays the data
local line_info = {
  id = "my.line_info",
  ref = { context = "my.stats" },    -- delegate context to stats
  update = function(self, session)
    local ctx = self:with_session(session).context(self, session)
    return ctx.current_line .. "/" .. ctx.total_lines
  end,
}
```

**Why `self:with_session(session)`?** Without it, `self.context` on the consumer would give you the raw `ref` value (the string `"my.stats"`), not the resolved context table. `with_session` follows the ref chain and returns the actual value.

**What ref keys create automatic update propagation?**

| Ref Key | Propagation Type | When the parent updates, the child... |
|---|---|---|
| `events` | Event dependency | Re-renders on the same events. |
| `timing` | Timer dependency | Re-renders on the same timer. |
| `hidden` | Visibility dependency | Re-checks visibility. |
| `min_screen_width` | Visibility dependency | Re-checks visibility. |
| `config`, `context`, `style`, etc. | None (passive) | Does NOT automatically re-render. Read via `with_session` when the child renders. |

If you need a child to re-render when a parent's `context` changes, also ref the parent's `events`:

```lua
local child = {
  id = "my.child",
  ref = {
    context = "my.provider",
    events = "my.provider",           -- re-render when provider's events fire
  },
  update = function(self, session)
    local ctx = self:with_session(session).context(self, session)
    return tostring(ctx.value)
  end,
}
```

### `inherit` — copy fields from a parent

`inherit` copies fields from another component at mount time. The child gets its own copy — changes to the parent after mounting do not propagate.

```lua
local base_style = {
  id = "my.base",
  style = { fg = "#ffffff" },
  padding = 1,
}

local child = {
  id = "my.child",
  inherit = "my.base",        -- copies style and padding
  style = { bold = true },    -- overrides parent's style
  update = function(self, session) return "child" end,
}
```

Child values override parent values. Parent functions run with `self = child`.

### `ref` vs `inherit`

| | `ref` | `inherit` |
|---|---|---|
| **Mechanism** | Live read-through delegation | Copy on mount |
| **Updates propagate?** | Yes (for dependency keys) | No |
| **Coupling** | Loose (child reads parent at render time) | Tight (fields are copied) |
| **Use when** | Sharing live events, styles, context | Creating variants of a base component |

**Rule of thumb:** Start with `ref`. Use `inherit` only when you need to copy and override a base definition.

### `abstract` — provider without rendering

A component with `abstract = true` never renders. It exists only to provide data to other components via `ref`:

```lua
local file_info = {
  id = "my.file_info",
  abstract = true,
  events = "BufEnter",
  context = function(self, session)
    return {
      name = vim.fn.expand("%:t"),
      ext = vim.fn.expand("%:e"),
      size = vim.fn.getfsize(vim.fn.expand("%")),
    }
  end,
}

local file_display = {
  id = "my.file_display",
  ref = {
    context = "my.file_info",
    events = "my.file_info",
  },
  update = function(self, session)
    local ctx = self:with_session(session).context(self, session)
    return ctx.name
  end,
}
```

### Nested components

Children inside a parent table inherit the parent's fields automatically:

```lua
{
  id = "my.section",
  style = { fg = "#ffffff" },
  {
    id = "my.section.child1",
    update = function(self, session) return "A" end,
  },
  {
    id = "my.section.child2",
    update = function(self, session) return "B" end,
  },
}
```

Both children inherit `style` from the parent. Each child is rendered as a separate statusline segment.

---

## Accessing Event Data

When a component triggers on an `event`, the raw autocmd data is available on the session:

```lua
local comp = {
  id = "my.autocmd_info",
  events = "BufEnter",
  update = function(self, session)
    local event_info = session:get("EventInfo")
    if event_info then
      local my_data = event_info[self.id]   -- per-component event data
      return my_data and my_data.file or ""
    end
    return ""
  end,
}
```

---

## Memoization

Cache expensive computations within a render cycle:

```lua
local comp = {
  id = "my.heavy",
  events = "CursorMoved",
  update = function(self, session)
    local scope = session:cache("my.heavy")
    local result = scope:memo(function()
      -- This only runs once per render cycle,
      -- no matter how many times update is called.
      return expensive_calculation()
    end)
    return tostring(result)
  end,
}
```

`scope:memo(fn, ...)` caches by function reference. The same function always returns the cached result within the same scope, regardless of arguments. Use different functions or scopes to cache different values.

---

## Overriding Default Components

Modify built-in components by passing an `override` table:

```lua
require("witch-line").setup({
  statusline = {
    global = {
      {
        id = "wl.mode",
        override = {
          style = { fg = "#ffffff", bg = "#333333" },
          padding = { left = 2, right = 2 },
        },
      },
    },
  },
})
```

**Overrideable fields:** `padding`, `config`, `timing`, `lazy`, `style`, `min_screen_width`, `hide`, `left_style`, `right_style`, `left`, `right`, `flexible`, `theme_aware`.

---

## Common Patterns

### Hide in specific filetypes

```lua
hidden = function(self, session)
  local ft = vim.bo.filetype
  return ft == "NvimTree" or ft == "neo-tree" or ft == "TelescopePrompt"
end
```

### Show only in insert mode

```lua
hidden = function(self, session)
  return vim.fn.mode() ~= "i"
end
```

### Style based on diagnostics

```lua
style = function(self, session)
  local errors = #vim.diagnostic.get(0, { severity = vim.diagnostic.severity.ERROR })
  if errors > 0 then
    return { fg = "#ff4444", bold = true }
  end
  return { fg = "#888888" }
end
```

### Update on custom user events

```lua
-- In your plugin code:
vim.api.nvim_exec_autocmds("User", { data = { name = "MyPluginUpdate" } })

-- In your component:
{
  id = "my.plugin_status",
  events = "User MyPluginUpdate",
  update = function(self, session)
    return get_plugin_status()
  end,
}
```

---

## Field Summary

| Field | Type | Default | Description |
|---|---|---|---|
| `id` | `string` | — | Unique identifier. Required. |
| `update` | `function(self, session)` | — | Returns display text (and optional inline style). Required. |
| `static` | `table` | `nil` | Internal fixed data, not user-overridable. |
| `config` | `table` | `nil` | User-overridable values. |
| `context` | `table \| function(self, session)` | `nil` | Shared data consumed by other components via `ref`. |
| `events` | `string \| string[]` | `nil` | Autocmd events that trigger re-render. |
| `timing` | `boolean \| number` | `nil` | Timer interval in ms. `true` = 1000. |
| `win_individual` | `boolean` | `false` | Re-render per window instead of globally. |
| `style` | `table \| string \| function` | `nil` | Highlight: table, named group, or dynamic function. |
| `padding` | `number \| table \| function` | `1` | Spaces around text. |
| `left` / `right` | `string \| function` | `nil` | Separator characters. |
| `left_style` / `right_style` | `number \| table` | `1` | Separator highlight (0–3 or explicit table). |
| `hidden` | `boolean \| function` | `false` | Conditionally hide the component. |
| `min_screen_width` | `number \| function` | `nil` | Hide when terminal has fewer columns. |
| `flexible` | `number` | `nil` | Hiding priority. Higher = hidden first when space is tight. |
| `lazy` | `boolean` | `true` | `false` to update at startup before any events fire. |
| `abstract` | `boolean` | `false` | Provider-only. Never rendered. |
| `inherit` | `string` | `nil` | Parent ID to copy fields from. |
| `ref` | `table` | `nil` | Live field delegation to another component. |
| `init` | `function(self)` | `nil` | One-time setup. No `session`. |
| `pre_update` | `function(self, session)` | `nil` | Before each render. |
| `post_update` | `function(self, session)` | `nil` | After each render. |
| `on_click` | `string \| function \| table` | `nil` | Click callback. |
