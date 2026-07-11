## witch-line

A fast, lightweight statusline plugin for Neovim. Components are flat Lua tables that reference each other by ID instead of nesting — readable, composable, and easy to maintain.

## Navigation

- [Concept](#concept)
- [Preview](#preview)
- [Features](#features)
- [Installation](#installation)
- [Usage](#usage)
  - [Options](#options)
  - [Commands](#commands)
- [Default Components](#default-components)
- [Customization](#customization)
- [Public APIs](#public-apis)
- [Contributing](#contributing)
- [License](#license)

## Concept

Most statusline frameworks (like [heirline](https://github.com/rebelot/heirline.nvim)) build components by nesting tables for inheritance. This works, but deeply nested structures are hard to read and maintain.

witch-line uses a flat component list with ID-based references instead:

```lua
-- heirline: nested
local Comp = {
  style = { fg = "..." },
  {
    provider = ...,
  },
}

-- witch-line: flat + ref
local Parent = {
  id = "parent",
  style = { fg = "#fff" },
}

local Child = {
  id = "child",
  ref = { style = "parent" },  -- read-only delegation
}

-- or inherit: copy + override
local Child2 = {
  id = "child2",
  inherit = "parent",          -- copy fields, child values win
}
```

The `ref` field creates a live dependency — when the parent updates, the child picks it up automatically. No manual propagation needed.

See the [COOKBOOK](./docs/COOKBOOK.md) for the full reference.

## Preview

<img width="1920" height="1047" alt="Basic statusline" src="https://github.com/user-attachments/assets/87b8f955-34e6-4410-a2a0-83359f249cfc" />

Per-window statusline with individual component values:

<img width="1918" height="1013" alt="Per-window statusline" src="https://github.com/user-attachments/assets/3ef62280-500c-4266-91d4-2f03d9c08dfb" />

https://github.com/user-attachments/assets/241d091f-bfdb-4935-b33d-8c8a2626c2a4

## Features

- **Fast** — minimal redraws, lazy module loading, cached highlight resolution.
- **Flat component system** — define components as plain tables, reference by ID instead of nesting.
- **Abstract components** — provider-only components that supply data without rendering.
- **Flexible layouts** — arrange components freely; higher `flexible` values hide first when space is tight.
- **Reactive updates** — components update only when their events fire or dependencies change.
- **Per-window statusline** — each window can have its own layout and values.
- **Auto-disable** — automatically hide the statusline for specific filetypes/buftypes.
- **Theme-aware** — component colors adapt to the current colorscheme.
- **Testable** — 492 assertions across unit, integration, and benchmark suites.

## Installation

```lua
-- lazy.nvim
{
  "sontungexpt/witch-line",
  dependencies = { "nvim-tree/nvim-web-devicons" },
  lazy = false,
  opts = {},
}
```

## Usage

### Laststatus

Set `laststatus` to `3` (global) or `2` (per-window):

```lua
vim.o.laststatus = 3
```

### Options

```lua
require("witch-line").setup({
  statusline = {
    global = {
      "wl.mode",
      "wl.file.name",
      "wl.git.branch",
      "%=",
      "wl.diagnostic.error",
      "wl.diagnostic.warn",
      "wl.lsp.clients",
      "wl.encoding",
      "wl.cursor.pos",
    },
    -- Per-window override (requires laststatus = 2)
    win = function(winid)
      local ft = vim.bo[vim.api.nvim_win_get_buf(winid)].filetype
      if ft == "NvimTree" then
        return { "wl.battery" }
      end
    end,
  },
  disabled = {
    filetypes = { "help", "TelescopePrompt" },
    buftypes = { "nofile", "terminal" },
  },
  auto_theme = true,
})
```

| Field | Type | Description |
|---|---|---|
| `statusline.global` | `CombinedComponent[]` | Components for the global statusline. Omit to use defaults. |
| `statusline.win` | `fun(winid): CombinedComponent[]` | Per-window override. Requires `laststatus = 2`. |
| `disabled.filetypes` | `string[]` | Filetypes where the statusline is disabled. |
| `disabled.buftypes` | `string[]` | Buftypes where the statusline is disabled. |
| `auto_theme` | `boolean` | Automatically adjust colors to match the colorscheme. |

### Commands

| Command | Description |
|---|---|
| `:WitchLine toggle_theme_aware` | Toggle automatic theme adjustment |
| `:WitchLine inspect event_store` | Inspect event store |
| `:WitchLine inspect timer_store` | Inspect timer store |
| `:WitchLine inspect comp_manager comps` | Inspect registered components |
| `:WitchLine inspect comp_manager dep_store` | Inspect dependency graph |
| `:WitchLine inspect highlight rgb24bit` | Inspect RGB color cache |
| `:WitchLine inspect highlight styles` | Inspect highlight style cache |
| `:WitchLine inspect statusline` | Inspect statusline state |

## Default Components

| Name | Description |
|---|---|
| `wl.mode` | Current Neovim mode |
| `wl.file.name` | Filename |
| `wl.file.icon` | File icon |
| `wl.file.modifier` | Modified indicator |
| `wl.file.size` | File size |
| `%=` | Separator (align left/right) |
| `wl.copilot` | Copilot status |
| `wl.codeium` | Codeium status |
| `wl.codeium.neocodeium` | Neocodeium status |
| `wl.diagnostic.error` | Error diagnostic count |
| `wl.diagnostic.warn` | Warning diagnostic count |
| `wl.diagnostic.info` | Info diagnostic count |
| `wl.diagnostic.hint` | Hint diagnostic count |
| `wl.encoding` | File encoding |
| `wl.cursor.pos` | Cursor line/column |
| `wl.cursor.progress` | Cursor position as % |
| `wl.lsp.clients` | Active LSP clients |
| `wl.indent` | Indent level |
| `wl.git.branch` | Git branch |
| `wl.git.diff.added` | Lines added |
| `wl.git.diff.removed` | Lines removed |
| `wl.git.diff.modified` | Lines changed |
| `wl.datetime` | Date and time |
| `wl.battery` | Battery status |
| `wl.os_uname` | OS name |
| `wl.nvim_dap` | nvim-dap status |
| `wl.search.count` | Search match count |
| `wl.selection.count` | Selection character count |

## Customization

Create custom components by defining a table with an `id` and `update` function. See the [COOKBOOK](./docs/COOKBOOK.md) for the full field reference and examples.

```lua
require("witch-line").setup({
  statusline = {
    global = {
      "wl.mode",
      "wl.file.name",
      "%=",
      {
        id = "my.clock",
        timing = 1000,
        style = { fg = "#888" },
        update = function(self, session)
          return os.date("%H:%M")
        end,
      },
    },
  },
})
```

## Public APIs

See [API.md](./docs/API.md) for the full reference.

## Contributing

Contributions are welcome. Areas where help is especially appreciated:

- **Documentation** — improve examples, add tutorials, translate.
- **Component testing** — help improve the test framework for individual components.
- **New components** — build integrations for tools not yet covered.
- **Bug reports** — open an issue with reproduction steps.

## Benchmarks

Cold startup time with matching UI components (mode, filename, branch, diff, diagnostics, lsp, encoding, filetype, progress, location):

| Plugin | Cold Startup | Relative |
|---|---|---|
| **witch-line** | ~4.0 ms | baseline |
| lualine | ~5.3 ms | 1.3x slower |

> Measured with `nvim --headless -u bench.lua`, 5 runs each, Neovim nightly on Linux.

## License

MIT — see [LICENSE](LICENSE).
