## Your First Component

A component is a Lua table with an `id` and an `update` function. The `update` function receives `self` (the component) and `session` (the current render cycle) and returns a string:

```lua
local filename = {
  id = "wl.filename",
  update = function(self, session)
    return vim.fn.expand("%:t")
  end,
}
```

Register it in your statusline config:

```lua
require("witch-line").setup({
  statusline = { global = { "wl.filename" } },
})
```

---

## Adding Data

### Static values

Use `static` for fixed config that doesn't change per cycle:

```lua
local indicator = {
  id = "wl.indicator",
  static = { icon = "⚡", max_count = 5 },
  update = function(self, session)
    return self.static.icon .. " ready"
  end,
}
```

Access via `self.static` anywhere in your component functions.

### Dynamic context

Use `context` to compute data that other components consume via `ref` (see [Reuse](#reuse)):

```lua
local provider = {
  id = "wl.provider",
  context = function(self, session)
    return { lines = vim.fn.line("$") }
  end,
}
```

The function receives `(self, session)` just like `update`.

### Custom fields

Any field you add is accessible via `self.<field>`:

```lua
local comp = {
  id = "wl.my_comp",
  my_data = { foo = "bar" },
  update = function(self, session)
    return self.my_data.foo
  end,
}
```

---

## Controlling When to Update

### Events

Re-render on Neovim autocmd events:

```lua
local mode_indicator = {
  id = "wl.mode",
  events = "ModeChanged",
  update = function(self, session)
    return vim.fn.mode():upper()
  end,
}
```

Multiple events, patterns, and options:

```lua
events = {
  "BufEnter",
  "User VeryLazy,LazyLoad",
  "BufEnter *.lua, *.py",
  { "CursorHold", once = true },
}
```

Special event fields:

| Field | Type | Description |
|---|---|---|
| `[1]` | `string` | Event name(s). |
| `pattern?` | `string\|string[]` | Autocmd pattern. |
| `once?` | `boolean` | Fire once then remove. |
| `remove_when?` | `fun(): boolean` | Remove when returns true. |

String syntax supports inline patterns: `"BufEnter *.lua,*.py"`, `"User LazyLoad"`.

### Timer

Update on a fixed interval in milliseconds:

```lua
local clock = {
  id = "wl.clock",
  timing = 1000,
  update = function(self, session)
    return os.date("%H:%M:%S")
  end,
}
```

Set `timing = true` for a default 1000 ms interval.

### Per-window

Re-render independently in each window:

```lua
local cwd = {
  id = "wl.cwd",
  win_individual = true,
  update = function(self, session)
    return vim.fn.getcwd()
  end,
}
```

---

## Styling

### Return inline style from `update`

Return a second value with highlight overrides:

```lua
update = function(self, session)
  return "Hello", { fg = "#00ff00" }
end
```

### Static or dynamic `style`

```lua
-- Static highlight table
style = { fg = "#ffffff", bg = "#000000" }

-- Dynamic (evaluated each cycle)
style = function(self, session)
  return vim.bo.modified and { fg = "#ffff00" } or nil
end

-- Named highlight group
style = "MyHighlightGroup"
```

### Padding

Spaces around the text. Default is 1 on each side:

```lua
padding = 2                    -- 2 on each side
padding = { left = 1, right = 3 }
padding = function(self, session) return vim.bo.modified and 2 or 1 end
```

### Separators

Decorative characters on each side:

```lua
left = "⦅", right = "⦆"
left = function(self, session) return " " end
```

Separator highlight styles via `SepStyle` constants or explicit tables:

```lua
left_style = 1           -- Sep bg = NONE, Sep fg = comp fg
left_style = { fg = "#fff" }
```

| SepStyle | Meaning |
|---|---|
| `0` | Inherit from component style. |
| `1` | Sep fg = comp fg, sep bg = NONE. |
| `2` | Sep fg = comp bg, sep bg = NONE. |
| `3` | Sep fg = comp bg, sep bg = comp fg. |

### Conditional visibility

Hide the component without removing it:

```lua
hidden = true
hidden = function(self, session)
  return vim.bo.buftype == "nofile"
end
```

Hide below a screen width:

```lua
min_screen_width = 80
min_screen_width = function(self, session)
  return session and 100 or 50
end
```

---

## Lifecycle Hooks

### `init` — one-time setup

Called once when the component is first loaded. No `session` available.

```lua
init = function(self)
  self.static.icon = "⚡"
  vim.api.nvim_create_autocmd("BufWritePost", {
    callback = function()
      require("witch-line.core.handler").request_update_comp_graph(self, true)
    end,
  })
end
```

### `pre_update` / `post_update` — before/after each render

```lua
pre_update = function(self, session)
  -- runs before min_screen_width, hidden, update
end
post_update = function(self, session)
  -- runs after all rendering is done
end
```

Full cycle order:

```
init → pre_update → min_screen_width → hidden → update
  → padding → style → left/right → left_style/right_style
  → on_click → post_update
```

---

## Interactivity

### Click handler

```lua
local clickable = {
  id = "wl.clickable",
  update = function(self, session) return "click me" end,
  on_click = function(self, minwid, click_times, mouse_button, modifier_pressed)
    print("clicked!")
  end,
}
```

| Parameter | Type | Description |
|---|---|---|
| `minwid` | `number` | Window number. |
| `click_times` | `number` | 1=single, 2=double. |
| `mouse_button` | `"l"\|"r"\|"m"` | Left/right/middle. |
| `modifier_pressed` | `"s"\|"c"\|"a"\|"m"` | Shift/ctrl/alt/meta. |

You can also pass a table with a `name` (for the global handler) and `callback`, or a string naming an existing global function.

### Flexible (hiding priority)

When space is tight, components with higher `flexible` values are hidden first:

```lua
flexible = 2   -- hidden before flexible = 1
```

---

## Reuse

### `inherit` — copy fields from another component

> **Prefer `ref` over `inherit`** in most cases. `ref` is read-only, avoids
> coupling, and creates explicit dependency links so changes propagate
> automatically. Use `inherit` only when you genuinely need to *copy and
> override* fields (e.g. extending a base style with overrides).

Child values override parent. Functions from the parent run with `self = child`.

```lua
local base = {
  id = "wl.base",
  style = { fg = "#fff" },
  padding = 1,
}

local child = {
  id = "wl.child",
  inherit = "wl.base",
  update = function(self, session) return "child" end,
}
```

### `ref` — read-only delegation

Reference another component's field without copying. The referenced component drives the value.

```lua
local provider = {
  id = "wl.provider",
  context = function(self, session)
    return { lines = vim.fn.line("$") }
  end,
}

local display = {
  id = "wl.display",
  ref = { context = "wl.provider" },
  update = function(self, session)
    local ctx = self:with_session(session).context(self, session)
    return "lines: " .. ctx.lines
  end,
}
```

Some ref keys create dependency links so changes propagate automatically:

| Key | Dependency |
|---|---|
| `events` | ✅ Event |
| `timing` | ✅ Timer |
| `hidden` | ✅ Visible |
| `min_screen_width` | ✅ Visible |
| `static`, `context`, `style`, `left`, `right`, `left_style`, `right_style` | — |

### `with_session` — reaching referenced data

Use `self:with_session(session)` to resolve a field from a referenced component. This follows the `ref` chain and returns the resolved value.

```lua
-- Field on this component directly:
self.static
self.context

-- Field from a referenced component:
self:with_session(session).static
self:with_session(session).context(self, session)
```

Without the proxy, `self.context` on a component with `ref.context` gives you the raw component ID string, not the resolved context table.

### Resolution order

```
Local → Inherit → Reference
```

1. Check the component's own field.
2. If absent, walk the `inherit` chain.
3. If still absent, walk the `ref` chain.

### Nested components

Children inherit fields from the parent (as if each had `inherit = parent.id`):

```lua
local parent = {
  id = "wl.parent",
  style = { fg = "#fff" },
  { id = "wl.child1", update = function() return "a" end },
  { id = "wl.child2", update = function() return "b" end },
}
```

---

## Session

During an event-triggered update, the raw autocmd args are stored on the session:

```lua
local event_info = session:get("EventInfo")
```

---

## Field Summary

| Field | Type | Default | Description |
|---|---|---|---|
| `id` | `string` | — | Unique identifier. Required for `ref` and `inherit`. |
| `update` | `fun(self, session): string[, table]` | — | Returns display text and optional highlight. |
| `static` | `table` | `nil` | Fixed config values. |
| `context` | `table\|fun(self, session): table` | `nil` | Dynamic data shared via `ref`. |
| `events` | `string\|string[]\|SpecialEvent[]` | `nil` | Autocmd events that trigger re-render. |
| `timing` | `boolean\|number` | `nil` | Timer interval in ms (`true` = 1000). |
| `win_individual` | `boolean` | `false` | Re-render per window. |
| `style` | `table\|string\|fun(self, session): table\|nil` | `nil` | Highlight: inline table, named group, or function. |
| `padding` | `number\|table\|fun(self, session): number` | `1` | Spaces around text. |
| `left` / `right` | `string\|fun(self, session): string` | `nil` | Decorative separators. |
| `left_style` / `right_style` | `SepStyle\|table` | `SepStyle.SepBg` | Separator highlight. |
| `hidden` | `boolean\|fun(self, session): boolean` | `false` | Conditionally hide. |
| `min_screen_width` | `number\|fun(self, session): number` | `nil` | Hide below column count. |
| `init` | `fun(self)` | `nil` | Called once at load. |
| `pre_update` | `fun(self, session)` | `nil` | Before each render. |
| `post_update` | `fun(self, session)` | `nil` | After each render. |
| `on_click` | `string\|fun\|table` | `nil` | Click callback. |
| `flexible` | `number` | `nil` | Hiding priority (higher = hidden first). |
| `lazy` | `boolean` | `true` | Load only when needed. |
| `inherit` | `string` | `nil` | Parent component ID to copy fields from. |
| `ref` | `table` | `nil` | Read-only field delegation. |
