# WitchLine Workflow Analysis

This document describes the internal architecture, module dependency graph, and data flow of WitchLine.

---

## 1. Module Dependency Graph

```
witch-line (init.lua)          ← entry point
  ├── witch-line.cache         ← cache read/write
  │     ├── witch-line._version
  │     ├── witch-line.utils.hash
  │     ├── witch-line.utils.persist
  │     └── (mods passed to save/load)
  │
  ├── witch-line.core.statusline   ← rendering engine
  │     ├── witch-line.core.highlight
  │     └── witch-line.utils.bitmask
  │
  ├── witch-line.core.handler      ← setup + update orchestration
  │     ├── witch-line.core.statusline
  │     ├── witch-line.core.highlight
  │     ├── witch-line.core.Session
  │     ├── witch-line.core.manager
  │     ├── witch-line.core.Component
  │     ├── witch-line.core.manager.event
  │     ├── witch-line.core.manager.timer
  │     └── witch-line.components.* (via Component.require_by_id)
  │
  └── witch-line.command           ← :WitchLine cmd
        ├── witch-line.core.manager
        ├── witch-line.cache
        ├── witch-line.core.statusline
        ├── witch-line.core.manager.event
        ├── witch-line.core.manager.timer
        └── witch-line.core.highlight
```

```
Public API wrappers (witch-line.*, non-core):
  witch-line.hook        → delegates to witch-line.core.manager.hook
  witch-line.handler     → delegates to witch-line.core.handler
  witch-line.statusline  → delegates to witch-line.core.statusline
  witch-line.session     → provides recycled session cache
  witch-line.highlight   → delegates to witch-line.core.highlight
  witch-line.resolver    → value resolution (used internally)
  witch-line.registry    → component registry
```

---

## 2. Startup Flow

```
require("witch-line").setup(user_config)
  │
  ├── 1. Compute config_checksum (hash of user config)
  │
  ├── 2. Try cache read
  │     ├── Cache hit → load all module caches (manager/event/timer/statusline/highlight)
  │     └── Cache miss → register VimLeavePre hook to save cache on exit
  │
  ├── 3. Apply default components if no cache (statusline.global = defaults)
  │
  ├── 4. Set auto_theme if configured
  │
  ├── 5. Setup statusline (lazy init + disabled filetype/buftype handlers)
  │
  ├── 6. Setup handler:
  │     ├── Register abstract components from user config
  │     ├── Register combined components (global statusline)
  │     ├── Setup per-window handlers (if statusline.win is set)
  │     ├── Start event listener (autocmd dispatch)
  │     ├── Start timer dispatch (libuv timers)
  │     └── Run pending init + emergency updates
  │
  └── 7. Register :WitchLine command (lazy on CmdlineEnter)
```

---

## 3. Component Registration Flow

```
register_combined_component(comp, parent_id, winid)
  │
  ├── If string: Component.require_by_id(path) → register_node(c, parent_id, winid)
  │
  ├── If table:
  │     ├── Handle [0] override syntax → require("override").override(base, user)
  │     ├── register_abstract_component(comp, winid):
  │     │     ├── Manager.register(comp) → stores in ManagedComps[id]
  │     │     ├── Queue init() if present
  │     │     ├── Set win_individual if winid
  │     │     ├── bind_update_conditions:
  │     │     │     ├── Timer.register_timer(comp)  (if comp.timing)
  │     │     │     ├── Event.register_events(comp) (if comp.events)
  │     │     │     ├── Event.register_vim_resized  (if comp.min_screen_width)
  │     │     │     └── Event.register_win_enter    (if comp.win_individual)
  │     │     ├── bind_dependencies:
  │     │     │     ├── ref.events → DepGraphKind.Event
  │     │     │     ├── ref.timing → DepGraphKind.Timer
  │     │     │     ├── ref.hidden → DepGraphKind.Visible
  │     │     │     └── inherit   → Event + Timer + Visible
  │     │     └── pull_missing_dependencies
  │     │           → auto-register referenced components if not yet registered
  │     │
  │     ├── Set inherit = parent_id if applicable
  │     ├── If lazy == false → mark_emergency
  │     └── build_indices → Statusline.push + track_flexible
  │
  └── Recurse into child components (integer-indexed entries)
```

---

## 4. Update Lifecycle (per component)

When a component is triggered for update (by event, timer, or manual refresh):

```
update_comp(comp, sid)
  │
  ├── 1. emit_pre_update(comp, sid)     ← calls comp.pre_update(self, sid)
  │
  ├── 2. min_screen_width check         ← resolve(comp.min_screen_width, comp, sid)
  │
  ├── 3. hidden check                   ← resolve(comp.hidden, comp, sid) == true
  │     └── If hidden → hide_segment(), return
  │
  ├── 4. evaluate(comp, sid)            ← resolve(comp.update, comp, sid) + padding
  │     └── If empty → hide_segment(), return
  │
  ├── 5. Resolve style:
  │     ├── dynamic_inherit("style", comp, sid, merge_hl, override_style)
  │     └── Highlight.highlight(hl_name, style)
  │
  ├── 6. Statusline.set_value(cid, value, hl_name, winid)
  │
  ├── 7. Resolve left/right:
  │     ├── lookup_dynamic(comp, "left", sid)  → format_side_value
  │     ├── resolve_side_style("left", ...)
  │     ├── Statusline.set_side_value(...)
  │     ├── lookup_dynamic(comp, "right", sid) → format_side_value
  │     ├── resolve_side_style("right", ...)
  │     └── Statusline.set_side_value(...)
  │
  ├── 8. If comp.on_click → register_click_handler + Statusline.set_click_handler
  │
  └── 9. emit_post_update(comp, sid)    ← calls comp.post_update(self, sid)
```

---

## 5. Value Resolution Pipeline

```
lookup_dynamic(comp, key, sid, seen)
  │
  ├── 1. Check session cache → return if cached
  │
  ├── 2. find_raw_value(comp, key, seen):
  │     ├── Check comp[key] directly (LOCAL)
  │     ├── If nil and inherit → recurse into parent (INHERIT)
  │     └── If nil and ref → recurse into ref component (REFERENCE)
  │
  ├── 3. If value is function → evaluate with (ctx, sid)
  │     └── ctx = deepest reference component (drc) or self
  │
  ├── 4. Cache in session (if sid is truthy)
  │
  └── 5. Return (value, origin, drc, dynamic)
```

Priority order: **Local → Inherit → Reference**

For `style` fields, additional inheritance merging occurs via `dynamic_inherit()`, which walks the `inherit` chain and merges using `Highlight.merge_hl()`.

---

## 6. Event Flow

```
Events.listen(work)
  │
  ├── autocmd registered for all events in event_store
  │
  ├── On trigger:
  │     └── Collect comp_ids → event_queue[comp_id] = event_info
  │
  └── dispatch (60ms debounce):
        └── Session.with_session → work(sid, event_queue)
              → handler.update_comp_graph_by_ids(ids, sid, DepGraphKind.Event)
              → Statusline.render_debounce()
```

Special events (with patterns, once, remove_when) are registered individually and support pattern-based filtering.

---

## 7. Timer Flow

```
Timer.start(work)
  │
  ├── One libuv timer per unique base interval
  │
  ├── On each tick:
  │     ├── elapsed = tick * base_ms
  │     ├── Collect all comp_ids where elapsed % interval == 0
  │     └── Session.with_session → work(sid, queue)
  │           → handler.update_comp_graph_by_ids(queue, sid, DepGraphKind.Timer)
  │           → Statusline.render_debounce()
  │
  └── LCM-based tick reset for alignment
```

---

## 8. Rendering Pipeline

```
Statusline.render(winid)
  │
  ├── 1. Determine Statusline state (global vs per-window)
  │
  ├── 2. Get sorted flexible components (highest flex first)
  │
  ├── 3. build_value(slots, state_map, skip_mask):
  │     ├── For each slot (not skipped):
  │     │     ├── click_handler_form (outer wrapper)
  │     │     ├── left decorations
  │     │     ├── value (main content)
  │     │     ├── right decorations
  │     │     └── %X (click handler end)
  │     └── Concat → statusline string
  │
  ├── 4. If no flex components → set statusline directly
  │
  ├── 5. If flex components exist:
  │     ├── Compute total rendered width
  │     ├── If width <= max → set directly
  │     └── Else → iteratively hide highest-flex slots until width fits
  │
  └── 6. nvim_set_option_value("statusline", result, { win = winid })
```

---

## 9. Session Cache Lifecycle

```
Session.with_session(fn)
  │
  ├── Clear session cache table
  ├── fn(1)   ← sid is always 1
  └── (cache is discarded — single-cycle ephemeral store)
```

The session cache serves as a per-cycle memoization layer for `lookup_dynamic` results. Cached values are discarded after each `with_session()` cycle, ensuring fresh evaluation on next event/timer.

---

## 10. Cache Persistence Flow

```
On VimLeavePre:
  ├── manager.on_vim_leave_pre:
  │     ├── Component.format_state_before_cache(comp)
  │     ├── serialize_function(comp)
  │     └── Store ManagedComps, DepGraph, Urgents, PendingInit
  ├── event.on_vim_leave_pre:
  │     └── Store EventStore
  ├── timer.on_vim_leave_pre:
  │     └── Store TimerStore
  ├── statusline.on_vim_leave_pre:
  │     └── Freeze GlobalStatusline.state_map
  │
  └── Cache.save(checksum, func_strip)
        ├── serialize_table_as_bytecode(DataAccessor, ...)
        └── Write to cache.luac with checksum header

On next startup (cache hit):
  ├── Read cache.luac
  ├── Validate checksum
  ├── Deserialize bytecode
  └── Load into each module via load_cache()
```

---

## 11. Dependency Graph Kinds

| Kind | Constant | Used For |
| --- | --- | --- |
| `DepGraphKind.Event` | 2 | Autocmd-triggered updates (`ref.events`, `inherit`) |
| `DepGraphKind.Timer` | 3 | Timer-triggered updates (`ref.timing`, `inherit`) |
| `DepGraphKind.Visible` | 1 | Visibility propagation (`ref.hidden`, `ref.min_screen_width`, `inherit`) |

---

## 12. Key Data Structures

```
ManagedComps: table<CompId, ManagedComponent>
  ├── id, version, lazy, timing, events, flexible
  ├── inherit, ref
  ├── static, context, temp
  ├── style, left_style, right_style
  ├── left, right, padding
  ├── init, pre_update, update, post_update
  ├── hidden, min_screen_width, on_click
  ├── auto_theme, win_individual
  ├── _hl_name, _left_hl_name, _right_hl_name
  ├── _abstract, _renderable, _hidden, _loaded
  └── _click_handler, _use_returned_style

DepGraph: table<DepGraphKind, table<CompId, table<CompId, true>>>
  └── dependency → { dependent1 = true, dependent2 = true }

Statusline[0]: {
  state_map: table<CompId, CompState>,
  slots: CompId[],
  flexs: table,
  literal_n: integer,
}

CompState: {
  [VALUE_SHIFT=2]: string,
  [WIDTH_SHIFT=5]: integer,
  [-1]: string (left),
  [1]: string (right),
  total_width: integer,
  flex: integer,
  click_handler_form: string,
}
```

---

## 13. Component Override System

When a user defines a component using `[0] = "file.name"` or `builtin.comp("file.name", override)`:

```
override.override(base_comp, override)
  │
  ├── Type-checks each override field against OVERRIDEABLE_TYPE_MAP
  ├── Tables are deep-merged (keep mode: child > parent)
  ├── If override.style is set → _use_returned_style = false
  ├── If override.style/left_style/right_style → auto_theme = false
  └── Returns the modified base component
```

---

## 14. File Structure

```
lua/witch-line/
  ├── init.lua                     # Entry point: setup()
  ├── builtin.lua                  # comp() helper
  ├── handler.lua                  # Public handler API
  ├── hook.lua                     # Public hook API
  ├── statusline.lua               # Public statusline API
  ├── session.lua                  # Recycled session cache (public)
  ├── highlight.lua                # Public highlight API
  ├── cache.lua                    # Cache persistence
  ├── command.lua                  # :WitchLine command
  ├── config.lua                   # Config normalization
  ├── registry.lua                 # Component registry
  ├── resolver.lua                 # Value resolution
  ├── override.lua                 # Component override
  ├── component.lua                # Component utilities
  ├── events.lua                   # Event management
  ├── timers.lua                   # Timer management
  │
  ├── core/                        # Core implementation (used internally)
  │   ├── handler/init.lua         #   Handler orchestration
  │   ├── statusline.lua           #   Rendering engine
  │   ├── highlight.lua            #   Highlight management
  │   ├── Session.lua              #   Session lifecycle (create/remove)
  │   ├── types.lua                #   Type definitions
  │   ├── Component/
  │   │   ├── init.lua             #   Component class
  │   │   ├── initial_state.lua    #   Context save/restore for caching
  │   │   └── override.lua         #   Component override logic
  │   └── manager/
  │       ├── init.lua             #   Manager (registry + resolver + inherit)
  │       ├── event.lua            #   Event store + autocmd dispatch
  │       ├── timer.lua            #   Timer store + dispatch
  │       └── hook.lua             #   Hook implementation
  │
  ├── components/                  # Built-in components
  │   ├── mode.lua, file.lua, git/
  │   ├── diagnostic.lua, lsp.lua, cursor.lua
  │   ├── encoding.lua, datetime.lua, indent.lua
  │   ├── battery.lua, os_uname.lua, nvim_dap.lua
  │   ├── search.lua, selection.lua, weather.lua
  │   └── ai/copilot.lua, ai/windsurf.lua
  │
  ├── constant/
  │   ├── default.lua              # Default component list
  │   ├── id.lua                   # Default ID mapping
  │   └── color.lua                # Color palette
  │
  └── utils/
      ├── init.lua                 # resolve(), debounce()
      ├── persist.lua              # Serialization (bytecode)
      ├── bitmask.lua              # Bitmask operations
      ├── hash/init.lua            # Hashing (xxhash, fvn1a)
      ├── lazy_require.lua         # Lazy loading
      ├── notifier.lua             # Notifications
      ├── tbl.lua                  # Table utilities
      ├── benchmark.lua            # Benchmarking
      └── debounce.lua             # Debounce utility
```
