## Module `witch-line`

Main entry point. Call `setup(opts)` to initialize the plugin.

```lua
require("witch-line").setup({
  abstracts = { ... },  -- CombinedComponent[] (optional)
  statusline = { ... },  -- { global: CombinedComponent[], win?: fun(winid): CombinedComponent[] }
  disabled = { ... },    -- { filetypes: string[], buftypes: string[] }
  cache = { ... },       -- { enabled: boolean, notification: boolean, func_strip: boolean }
  auto_theme = true,     -- boolean | nil
})
```

- `setup(user_config)` — Initializes WitchLine with the given configuration. See README.md for full option reference.

---

## Module `witch-line.constant.default`

Returns a table with the default statusline component list:

```lua
"wl.mode", "wl.file.name", "wl.file.icon", "wl.file.modifier",
"wl.git.branch", "wl.git.diff.added", "wl.git.diff.removed", "wl.git.diff.modified",
"%=",
"wl.diagnostic.error", "wl.diagnostic.warn", "wl.diagnostic.info", "wl.diagnostic.hint",
"wl.lsp.clients", "wl.windsurf.neocodeium", "wl.indent", "wl.cursor.pos", "wl.cursor.progress"
```

---

## Module `witch-line.core.handler`

Functions for programmatic component updates and registration.

- `request_update_comp_graph(comp, eager?, dep_graph_kind?, seen?)` — Updates a component and its dependencies, then re-renders the statusline. Call this from custom autocmds to trigger updates. `eager` (boolean) skips debounce if true.

- `update_comp(comp, sid)` — Updates a single component.

- `update_comp_graph(comp, sid, dep_graph_kind?, seen?)` — Recursively updates a component and all its dependents without re-rendering.

- `update_comp_graph_by_ids(ids, sid, dep_graph_kind?, seen?)` — Updates components by ID list and their dependents.

---

## Module `witch-line.core.manager.registry`

Component registry with dependency graph management.

- `require_by_id(id)` — Loads a component by its ID.

- `register(comp)` — Registers a component. Returns the existing one if already registered.

- `get_comp(id)` — Returns a registered component by ID, or nil.

- `is_existed(id)` — Checks if a component is registered.

- `link_dependency(kind, source_id, dependent_id)` — Creates a dependency edge in the dependency graph.

- `iterate_dependents(kind, comp_id)` — Iterates over all components that depend on the given component.

- `mark_emergency(id)` — Marks a component for immediate update on startup.

- `get_emergency_ids()` — Returns the list of emergency component IDs.

- `lookup_plain_value(comp, key)` — Looks up a raw value through the inherit/ref chain.

- `inherit(comp, key, merge_fn?)` — Resolves inherited values with optional merge function.

- `inspect(target?)` — Returns the internal registry state for debugging (`"dep_graph"`, `"comps"`, or both).

---

## Module `witch-line.core.Session`

Recycled session cache for storing ephemeral data during a single render cycle.

- `with_session(fn)` — Creates a session, invokes `fn(session)`, then destroys it. `session.id` is a numeric identifier.

- `session:get(key)` — Returns the value of a store by key.

- `session:set(key, value)` — Sets a value in the session store.

- `session:get_cache(key)` — Returns a cached memoized value by key.

- `session:set_cache(key, value)` — Caches a value for the session.

- `session:memo(fn, ...)` — Calls `fn(...)` and caches the result for the session. Returns the cached value on subsequent calls with the same `fn`.

---

## Module `witch-line.core.statusline`

Low-level statusline rendering and segment management.

- `render(winid?)` — Renders the statusline immediately for the given window.

- `render_debounce(...)` — Renders the statusline with 80ms debounce (args forwarded to `render`).

- `push(comp_id?, value, winid?)` — Appends a component segment (or literal string if comp_id is nil) to the layout.

- `set_value(comp_id, value, hl_name?, winid?)` — Sets the display value of a component segment.

- `set_hl_name(comp_id, new_hl_name, winid?)` — Updates the highlight name for a component segment.

- `set_side_value(comp_id, shift_side, value, hl_name?, force?, winid?)` — Sets left (-1) or right (1) side decoration.

- `set_side_hl_name(comp_id, shift_side, new_hl_name, winid?)` — Updates the highlight name for a side decoration.

- `set_click_handler(comp_id, click_handler, force?, winid?)` — Attaches a click handler string to a segment.

- `hide_segment(comp_id, winid?)` — Hides a segment by clearing its value.

- `track_flexible(comp_id, priority, winid?)` — Marks a component as flexible with the given priority.

- `inspect(winid?)` — Logs the internal statusline state for debugging.

- `setup(disabled_opts)` — Initializes the statusline with disabled filetype/buftype options.

---

## Module `witch-line.core.highlight`

Highlight group management and color utilities.

- `highlight(group_name, hl_style)` — Defines or updates a Neovim highlight group. `hl_style` can be a string (link target) or a `ThemeAwareStyle` table.

- `make_hl_name_from_id(id)` — Generates a valid highlight group name from a component ID.

- `assign_highlight_name(str, hl_name)` — Wraps a string with highlight group markers (`%#...#`).

- `replace_highlight_name(str, new_hl_name, n?)` — Replaces highlight group markers in a string.

- `merge_hl(child, parent)` — Merges two highlight definitions (child takes precedence).

- `safe_nvim_get_hl(opts)` — Safely queries Neovim's highlight table via pcall.

- `get_style(comp)` — Retrieves the cached style for a component.

- `set_auto_theme_enabled(value)` — Enables/disables the auto-theme feature.

- `toggle_auto_theme()` — Toggles the auto-theme feature on/off.

- `inspect(target?)` — Logs the highlight cache for debugging (`"rgb24bit"`, `"styles"`, or both).

---

## Module `witch-line.cache`

Cache persistence layer — saves and loads component state across Neovim restarts using bytecode serialization.

- `loaded()` — Returns true if cache data has been loaded.

- `cache_file_readable()` — Returns true if the cache file exists and is readable.

- `read(config_checksum, notification?)` — Reads and validates the cache file. Returns a `DataAccessor` object, or nil if the cache is invalid.

- `save(config_checksum, func_strip?, pre_work?)` — Serializes current state to the cache file.

- `clear(notification?)` — Deletes the cache file.

- `config_checksum(user_configs)` — Computes a stable checksum from the user configuration for cache invalidation.

- `inspect()` — Logs the current cache data for debugging.

---

## Module `witch-line.utils.benchmark`

Benchmark utility for measuring callback execution time.

- `benchmark(cb, name, file_path?)` — Measures `cb()` execution time in nanoseconds and logs the result via `vim.notify` or appends to a file.

---

## Module `witch-line.constant.id`

Default component ID mapping and validation.

- `path(id)` — Returns the internal module path for a default ID, or nil if not found.

- `existed(id)` — Checks if an ID corresponds to a default component.

- `validate(id)` — Validates that an ID is a non-empty string and not a default ID.

---

## Module `witch-line.constant.color`

Color palette for theme-aware styling.

Returns a table with colors mapped by name.

---

## Module `witch-line.core.component.evaluator`

Component evaluation utilities.

- `evaluate(comp, session)` — Calls `update` and applies padding. Returns `(string, CompStyle|nil)`.
- `hidden(comp, session)` — Returns `true` if the component is hidden.
- `min_screen_width(comp, session)` — Returns the min screen width for the component, or nil.
- `auto_theme(comp, session)` — Returns whether auto theme is enabled for the component.
- `emit_init(comp)` — Calls `comp.init(comp)` if defined.
- `emit_pre_update(comp)` — Calls `comp.pre_update(comp)` if defined.
- `emit_post_update(comp)` — Calls `comp.post_update(comp)` if defined.
- `side_style(comp, side)` — Returns the side style for left or right.
- `hl_name_field(side)` — Returns the internal hl name field key for the side (`"_left_hl_name"` or `"_right_hl_name"`).

---

## Module `witch-line.core.component.override`

Allows overriding default component fields with type-safe merging.

- `override(comp, override)` — Merges `override` fields into the default component. Only fields listed in `OVERRIDEABLE_TYPE_MAP` are accepted, with type validation.

---

## Module `witch-line.command`

Registers the `:WitchLine` user command with subcommands:

| Command | Description |
| --- | --- |
| `:WitchLine clear_cache` | Clears the cache |
| `:WitchLine toggle_auto_theme` | Toggles auto theme adjustment |
| `:WitchLine inspect` | Inspect internal state (aliases at `:WitchLine inspect --help`) |

---

## Module `witch-line.core.manager.event`

Neovim autocmd event management for component updates.

- `register_events(comp)` — Registers a component's event declarations (strings or tables).

- `register_vim_resized(comp)` — Registers a component for `VimResized`.

- `register_win_enter(comp)` — Registers a component for `WinEnter`.

- `on_event(work)` — Initializes autocmds and sets up event dispatch. The `work` callback receives `(sid, queue)`.

- `inspect()` — Returns the internal event store for debugging.

---

## Module `witch-line.core.manager.timer`

libuv timer management for periodic component updates.

- `register_timer(comp)` — Registers a component for timer-based updates. `comp.timing` can be `true` (=1000ms) or a number (custom ms).

- `on_timer_trigger(work)` — Starts all registered timers. The `work` callback receives `(sid, queue)`.

- `stop_all_timers()` — Stops and closes all active timers.

- `inspect()` — Returns the internal timer store for debugging.

---

## Module `witch-line.core.manager.click`

Click handler registration.

- `register(comp)` — Registers a click handler for the component.
- `unregister(comp)` — Unregisters a component's click handler.


