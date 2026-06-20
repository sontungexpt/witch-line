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

## Module `witch-line.builtin`

Helpers for creating custom variants of default components.

- `comp(path, override)` — Returns a component table that inherits from the default component at `path` (e.g. `"file.name"`) with the given `override` fields applied.

  ```lua
  local my_comp = require("witch-line.builtin").comp("file.name", {
    padding = { left = 2 },
    min_screen_width = 60,
  })
  ```

---

## Module `witch-line.handler`

Functions for programmatic component updates and registration.

- `refresh_component_graph(comp, eager?, dep_graph_kind?, seen?)` — Updates a component and its dependencies, then re-renders the statusline. Call this from custom autocmds to trigger updates. `eager` (boolean) skips debounce if true.

- `update_comp_graph(comp, sid, dep_graph_kind?, seen?)` — Recursively updates a component and all its dependents without re-rendering.

- `update_by_ids(ids, sid, dep_graph_kind?, seen?)` — Updates components by ID list and their dependents.

- `register_abstract(comp, winid?)` — Registers an abstract (non-rendered) component for use as a dependency.

- `register_combined(comp, parent_id?, winid?)` — Registers a combined component (string, table, or list) for rendering.

---

## Module `witch-line.hook`

Hooks for accessing component data from within component functions.

- `use_static(comp)` — Returns the resolved static data (merged through inherit/reference chain) for the given component.

- `use_context(comp, session_id)` — Returns the resolved context data for the component in the given session.

- `use_event_info(comp, session_id)` — Returns the event info table that triggered the current update cycle, or nil if not triggered by an event. The result matches `vim.api.keyset.create_autocmd.callback_args`.

- `use_plain_field(comp_id, field_name)` — Look up a raw (non-evaluated) field value from any registered component by its ID.

- `use_dynamic_field(comp_id, field_name, sid)` — Look up an evaluated field value from any registered component by its ID.

---

## Module `witch-line.session`

Recycled session cache for storing ephemeral data during a single render cycle.

- `with_session(fn)` — Clears the session cache and calls `fn(sid)` where `sid` is always `1`. Use this to scope temporary data.

- `get(key)` — Returns the value of a store by key.

- `get_deep(key, sub_key)` — Returns a specific sub-value within a store.

- `set_deep(key, sub_key, value)` — Sets a specific sub-value within a store.

---

## Module `witch-line.statusline`

Low-level statusline rendering and segment management.

- `render(winid?)` — Renders the statusline immediately for the given window (or global if laststatus=3).

- `render_debounce(winid?)` — Renders the statusline with 80ms debounce.

- `push(comp_id?, value, winid?)` — Appends a component segment (or literal string if comp_id is nil) to the layout.

- `set_value(comp_id, value, hl_name?, winid?)` — Sets the display value of a component segment.

- `set_side_value(comp_id, shift_side, value, hl_name?, force?, winid?)` — Sets left (-1) or right (1) side decoration.

- `set_click_handler(comp_id, click_handler, force?, winid?)` — Attaches a click handler string to a segment.

- `hide_segment(comp_id, winid?)` — Hides a segment by clearing its value.

- `track_flexible(comp_id, priority, winid?)` — Marks a component as flexible with the given priority.

- `inspect()` — Logs the internal statusline state for debugging.

- `on_vim_leave_pre(CacheDataAccessor)` — Freezes state for cache persistence.

- `load_cache(CacheDataAccessor)` — Restores statusline from cache.

---

## Module `witch-line.highlight`

Highlight group management and color utilities.

- `highlight(group_name, hl_style)` — Defines or updates a Neovim highlight group. `hl_style` can be a string (link target) or a `ThemeAwareStyle` table.

- `make_hl_name_from_id(id)` — Generates a valid highlight group name from a component ID.

- `assign_highlight_name(str, hl_name)` — Wraps a string with highlight group markers (`%#...#`).

- `replace_highlight_name(str, new_hl_name, n?)` — Replaces highlight group markers in a string.

- `merge_hl(child, parent, n)` — Merges two highlight definitions (child takes precedence).

- `safe_nvim_get_hl(opts)` — Safely queries Neovim's highlight table via pcall.

- `get_style(comp)` — Retrieves the cached style for a component.

- `set_auto_theme(value)` — Enables/disables the auto-theme feature.

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

## Module `witch-line.registry`

Component and dependency graph registry.

- `register(comp)` — Registers a component. Returns the existing one if already registered.

- `get(id)` — Returns a registered component by ID, or nil.

- `is_existed(id)` — Checks if a component is registered.

- `iterate()` — Iterates over all registered components.

- `mark_emergency(id)` — Marks a component for immediate update on startup.

- `get_emergency_ids()` — Returns the list of emergency component IDs.

- `queue_init(id)` — Queues a component's `init()` call.

- `iterate_pending_init()` — Iterates over queued init components.

- `link_dependency(ref_id, comp_id, dep_graph_kind)` — Creates a dependency edge in the dependency graph.

- `iterate_dependents(dep_graph_kind, comp_id)` — Iterates over all components that depend on the given component.

- `iterate_missing_dep_ids(comp_id)` — Finds dependencies that are referenced but not yet registered.

- `inspect()` — Returns the internal registry state for debugging.

---

## Module `witch-line.resolver`

Value resolution with inheritance and reference chain traversal.

- `lookup_plain(comp, key, seen?)` — Finds the raw (un-evaluated) value for a key, traversing local → inherit → ref chains.

- `lookup_dynamic(comp, key, sid, seen?, ...)` — Same as `lookup_plain` but evaluates functions. Caches results per session cycle.

- `deepest_reference(comp, key, seen?)` — Returns the deepest reference component for a given key.

- `dynamic_inherit(comp, key, sid, merge, self_val?)` — Resolves and merges inherited values (e.g. styles) through the inherit chain using a merge function.

- `clear_raw_cache()` — Clears the internal raw value cache.

---

## Module `witch-line.command`

Registers the `:WitchLine` user command with subcommands:

| Command | Description |
| --- | --- |
| `:WitchLine clear_cache` | Clears the cache |
| `:WitchLine toggle_auto_theme` | Toggles auto theme adjustment |
| `:WitchLine inspect` | Inspect internal state (aliases at `:WitchLine inspect --help`) |

---

## Module `witch-line.events`

Neovim autocmd event management for component updates.

- `register(events, comp_id)` — Registers a component's event declarations (strings or tables).

- `register_resized(comp_id)` — Registers a component for `VimResized`.

- `register_win_enter(comp_id)` — Registers a component for `WinEnter`.

- `get_event_info(comp, _sid)` — Returns the event info that triggered the component's update.

- `listen(work)` — Initializes autocmds and sets up event dispatch. The `work` callback receives `(sid, queue)`.

- `inspect()` — Returns the internal event store for debugging.

---

## Module `witch-line.timers`

libuv timer management for periodic component updates.

- `register(interval, comp_id)` — Registers a component for timer-based updates. `true` = 1000ms. Numbers specify custom ms.

- `start(work)` — Starts all registered timers. The `work` callback receives `(sid, queue)`.

- `stop_all()` — Stops and closes all active timers.

- `inspect()` — Returns the internal timer store for debugging.

---

## Module `witch-line.constant.default`

Returns a table with the default statusline component list:

```lua
"mode", "file.name", "file.icon", "file.modifier",
"git.branch", "git.diff.added", "git.diff.removed", "git.diff.modified",
"%=",
"diagnostic.error", "diagnostic.warn", "diagnostic.info", "diagnostic.hint",
"lsp.clients", "windsurf.neocodeium", "indent", "cursor.pos", "cursor.progress"
```

---

## Module `witch-line.constant.id`

Default component ID mapping and validation.

- `Id` — Metatable-based enum of all default IDs (e.g. `require("witch-line.constant.id").Id["mode"]` → `"mode"`).

- `path(id)` — Returns the internal module path for a default ID, or nil if not found.

- `existed(id)` — Checks if an ID corresponds to a default component.

- `validate(id)` — Validates that an ID is a non-empty string and not a default ID.

---

## Module `witch-line.override`

Allows overriding default component fields with type-safe merging.

- `override(comp, override)` — Merges `override` fields into the default component. Only fields listed in `OVERRIDEABLE_TYPE_MAP` are accepted, with type validation.

---

## Module `witch-line.config`

Configuration normalization.

- `normalize(user_configs)` — Applies defaults and ensures required fields exist. Returns the normalized config.

---

## Module `witch-line.component`

Low-level component utilities — id assignment, evaluate, hidden check, click handler registration.

- `setup(comp)` — Ensures the component has a valid id.
- `require(path)` — Loads a default component by dotted path.
- `require_by_id(id_or_path)` — Loads a component by its id.
- `evaluate(comp, sid)` — Calls `update` and applies padding.
- `hidden(comp, sid)` — Returns true if the component is hidden.
- `min_screen_width(comp, sid)` — Returns the min screen width for the component.
- `auto_theme(comp, sid)` — Returns whether auto theme is enabled for the component.
- `register_click_handler(comp)` — Registers a click handler and returns its global name.
- `side_style(comp, side)` — Returns the side style for left or right.
- `hl_name_field(side)` — Returns the internal hl name field key for the side.
