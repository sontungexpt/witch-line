## Runtime

```lua
local Engine = require("witch-line.engine.init")
local Registry = require("witch-line.core.registry")
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

For `Request`, `Session`, and `Session Cache` APIs see [COOKBOOK.md](COOKBOOK.md#api-reference).
