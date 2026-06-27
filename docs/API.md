## Runtime

```lua
local Handler = require("witch-line.core.handler")
local Registry = require("witch-line.core.manager.registry")
local Statusline = require("witch-line.core.statusline")
```

- `Handler.request_update_comp_graph(comp, eager?)` — Trigger re-render from custom autocmds. `eager = true` skips debounce.

- `Registry.get_comp(id)` — Get a registered component by ID, or nil.
- `Registry.is_existed(id)` — Check if a component ID is registered.
- `Registry.lookup_plain_value(comp, key)` — Read a value through inherit/ref chain.

- `Statusline.render(winid?)` — Force re-render the statusline immediately.
- `Statusline.render_debounce(...)` — Re-render with 80ms debounce.
- `Statusline.hide_segment(comp_id, winid?)` — Hide a component's segment.
- `Statusline.set_value(comp_id, value, hl_name?, winid?)` — Set a component's displayed value programmatically.
- `Statusline.inspect(winid?)` — Log internal statusline state for debugging.

- `session:get("EventInfo")` — Read autocmd args during event-triggered updates.
