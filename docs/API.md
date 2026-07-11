## Runtime

```lua
local Engine = require("witch-line.engine.init")
local Registry = require("witch-line.core.registry")
local Statusline = require("witch-line.engine.statusline")
```

### Engine (`witch-line.engine.init`)

- `Engine.request_update_comp_graph(comp, eager?)` — Trigger re-render from custom autocmds. `eager = true` skips debounce.

### Registry (`witch-line.core.registry`)

- `Registry.get_comp_by_id(id)` — Get a registered component by ID, or nil.
- `Registry.is_existed(id)` — Check if a component ID is registered.

### Resolver (`witch-line.core.resolver`)

```lua
local Resolver = require("witch-line.core.resolver")
```

- `Resolver.resolve_plain_field(comp, key)` — Read a value through the ref chain. Returns `value, owner` or `nil, nil`.
- `Resolver.resolve_field_owner(comp, key)` — Return only the owner component of a resolved field.

### Statusline (`witch-line.engine.statusline`)

- `Statusline.render(winid?)` — Force re-render the statusline immediately.
- `Statusline.render_debounce(...)` — Re-render with 80ms debounce.
- `Statusline.hide_segment(comp_id, winid?)` — Hide a component's segment.
- `Statusline.set_value(comp_id, value, hl_name?, winid?)` — Set a component's displayed value programmatically.
- `Statusline.set_hl_name(comp_id, new_hl_name, winid?)` — Replace the highlight name on a rendered segment.
- `Statusline.set_side_value(comp_id, shift_side, value, hl_name?, force?, winid?)` — Set the left (`-1`) or right (`1`) separator value.
- `Statusline.set_side_hl_name(comp_id, shift_side, new_hl_name, winid?)` — Replace the highlight name on a separator.
- `Statusline.set_click_handler(comp_id, click_handler, force?, winid?)` — Attach a click handler to a segment.
- `Statusline.track_flexible(comp_id, priority, winid?)` — Register a component for flex-based hiding.
- `Statusline.inspect(winid?)` — Log internal statusline state for debugging.

### Session

```lua
-- During an event-triggered update, the raw autocmd args are stored on the session:
local event_info = session:get("EventInfo")
```

### Session Cache

```lua
-- Memoize expensive computations within a cache scope:
local scope = session:cache("component_id")
local result = scope:memo(expensive_fn, arg1, arg2)
```
