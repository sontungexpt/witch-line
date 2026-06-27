## witch-line

The best statusline plugin for neovim. It's very lightweight and super fast.

This plugin lazy load as much as possible

## Navigation

- 💬 [A Few Words to Say](#a-few-words-to-say)
  - 💡 [Concept Ideas](#concept-ideas)
- 🪄 [Preview](#preview)
- ✨ [Features](#-features)
  - 📝 [TODO](#todo)
  - 📊 [Compare with other statusline plugins](#compare-with-other-statusline-plugins)
  - 📈 [Benchmarks](#benchmarks)
- ⚙️ [Installation](#installation)
- 🚀 [Usage](#usage)
  - 🧱 [Laststatus](#laststatus)
  - 🧩 [Options](#options)
  - 🪄 [Commands](#commands)
- 🧾 [Default Components Reference](#-default-components-reference)
  - 🔖 [Default Components](#-default-components)
  - 🛠️ [Customizable Fields for Components](#️-customizable-fields-for-components)
- 🧠 [Component Structure](#-component-structure)
- 📚 [Public APIs](#-public-apis)
- 🤝 [Community Help & Contributions Wanted](#-community-help--contributions-wanted)
- 📜 [License](#-license)

## A few words to say

🎉 The default component is written for my personal use. So maybe you need to
create your own component. I'm very happy to see your component. So if you have
any idea to create a new component, please open an issue or pull request.

### Concept ideas

- I like the reference concept in any database structure based on id. So I use the same concept in this plugin for component system. You can reference other component by id to share some field like events, style, static, context, hidden, min_screen_width. This will help you to create a component based on other component without duplicate code.

- Spoiler this plugin also provide nested tables to inherit from parent by recursively for anyone enjoy with creating a component based on other component by nested table like [heirline](https://github.com/rebelot/heirline.nvim). But I think the reference concept is better. And the statusline is a flat structure and readable.

#### Understand Concept

What's is the reference concept.

- I assume that almost people know about [heirline](https://github.com/rebelot/heirline.nvim). It's a well-being statusline framework based on recursion with many nested tables to inherit the value. It's good. But to be honestly, i think it's quite redundant, and some time make the component biggest and hard to maintain. We always retain the deepest nested level is less than 3 for avoiding aweful behavior and hard to control. And almost popular component isn't necessary to create more than 2 level inheritance. So why not make some changes with a flatten component list. That's why reference concept appears.

Reference is not a new topic. You meet it in many cases such example: in database a document, a table reference to another by id. In rust we has borrowing, or in C/C++ we has pointer. And now, I move this concept to witch-line component.

See the magic:

```lua
  -- We move from
  -- heirline
  local Comp = {
    style = {
      fg= ...
    },
    {
      provider= ...
    },
    {
      provider= ...
    },
  }


  -- to witch-line
  -- You can see the difference and detail about ref field and inherit field in [COOKBOOK](./docs/COOKBOOK.md)
  local Parent = {
    id = "A"
    style = ...
  }
  local Child1 = {
    id = "B",
    ref = { -- ref particular field only
      style = "A"
    }
  }

  local Child2 = {
    id  = "C",
    inherit = "A"
  }



```

## Preview

- Basic style (No separator, I aprreciate basic but you can create it or do many things else by yourself (like add separator) or you can create new PR for your feature you wantc)

<img width="1920" height="1047" alt="image" src="https://github.com/user-attachments/assets/87b8f955-34e6-4410-a2a0-83359f249cfc" />

- Individual statusline for each window.

<img width="1918" height="1013" alt="image" src="https://github.com/user-attachments/assets/3ef62280-500c-4266-91d4-2f03d9c08dfb" />

- Individual component value for each window.

<img width="1917" height="1041" alt="image" src="https://github.com/user-attachments/assets/6a588a6b-df7b-4749-87c2-fb625133760a" />

- Video:

https://github.com/user-attachments/assets/241d091f-bfdb-4935-b33d-8c8a2626c2a4

## ✨ Features

`witch-line` is a fast, lightweight, and fully customizable statusline plugin for Neovim. It focuses on modularity, caching, and performance. Below are the key features:

- ⚡ **Blazing Fast**: Optimized with internal caching and minimal redraws to keep your statusline snappy and efficient. Just config for first time and **every thing** will be cache and run super fast later.

- 🧩 **Modular Components**: Define reusable and nested components using a simple configuration format.

- 🎛 **Abstract Components**: Support for abstract components that can be composed and reused without rendering directly.

- 🎨 **Flexible Layouts**: Arrange statusline components in any order, across multiple layers or segments.

- 🔁 **Reactive Updates**: Smart detection of buffer/file changes to update only when necessary.

- 📁 **Context-Aware Disabling**: Automatically disable the statusline for specific `filetypes` or `buftypes` (e.g. terminal, help, etc).

- 🧠 **Config Hashing**: Detect if user config has changed via xxh32 hashing, ensuring minimal reinitialization.

- 💾 **Persistent Caching**: Cache user configurations and state across sessions using a simple key-value system.

- 🧪 **Testable & Maintainable**: Designed with testability and clear API boundaries in mind.

- 🛠 **Extensible**: Easily extend with custom components.

This plugin is ideal for developers who want full control over the look and feel of their statusline, without sacrificing performance or flexibility.

---

### TODO

- Laststatus

  - [x] Support for laststatus = 1
  - [x] Support for laststatus = 2
  - [x] Support for laststatus = 3
  - [x] Support for laststatus = 0

- Cache

  - [x] Implement caching mechanism (serialization + deserialization)
  - [x] Cache all needed data
  - [x] Use checksum to detect config changes with xxh32
  - [x] Lazy compile function of component
  - [x] Detect default component changed automatically when plugin was updated
  - [ ] Support up-value for component function caching
  - [ ] Support paritial cache loading

- Customization

  - [x] Support user-defined component
  - [x] Support override default component by user value

- Component

  - [x] Only update component when needed
  - [x] Implement component system
  - [x] Support abstract component
  - [x] Support nested component
  - [x] Support ref field to reference other component
  - [x] Support inherit field to inherit from other component
  - [x] Support static field to store static data
  - [x] Support context field to store context data
  - [x] Support events field to trigger component update
  - [x] Support timing field to update component periodically
  - [x] Support lazy field to lazy load component
  - [x] Support padding field to add padding around component
  - [x] Support style field to override component style
  - [x] Support left_style field to override left part style
  - [x] Support right_style field to override right part style
  - [x] Support left field to add left content
  - [x] Support right field to add right content
  - [x] Support min_screen_width field to hide component if screen width is less than this value
  - [x] Support hidden field to hide component based on condition
  - [x] Support init function to initialize component
  - [x] Support pre_update function to run before update function
  - [x] Support post_update function to run after update function
  - [x] Support update function to generate component content
  - [x] Support ref field to reference other component fields (events, style, static, context, hidden, min_screen_width)
  - [x] Support version field to manage component cache
  - [x] Support flexible field to hide component based on priority when space is limited
  - [x] Support on_click function to handle click events
  - [x] Support win_individual field to enable individual value for each window
  - [ ] Support coroutine for update function

- Hide Automatically

  - [x] Implement disable system
  - [x] Support disable for specific filetypes
  - [x] Support disable for specific buftypes
  - [ ] Support for laststatus = 1, 2

- Commands

  - [x] Implement `:Witchline clear_cache` command to clear cache
  - [x] Implement `:Witchline inspect` command to inspect some information

- Testing

  - [ ] Write unit tests for core functionality
  - [ ] Write performance benchmarks

- Themes

  - [x] Auto adjust color of components based on theme

- Bug fixs (Will fix soon this important)

  - [x] A probably inheritance logic when conflicting between parent and child happens

### Compare with other statusline plugins

---

### Benchmarks

Cold startup time measured with the plugin's default config in a headless Neovim session.
Each plugin is loaded in a separate process (`nvim --headless -u bench.lua`) to ensure a clean cold-start measurement.

| Plugin     | Cold Startup (ms) |
| ---------- | ----------------- |
| witch-line | ~3.3              |
| lualine    | ~6.3              |
| heirline   | n/a (unavailable) |

> **Environment**: Neovim nightly, Linux, 5 runs per plugin with cache disabled for witch-line.
> Heirline was not installed in the test environment, so no data is available.

---

## Installation

```lua
    -- lazy
    {
        "sontungexpt/witch-line",
        dependencies = {
            "nvim-tree/nvim-web-devicons",
        },
        lazy = false, -- Almost component is lazy load by default. So you can set lazy to false
        opts = {},
    },
```

## Usage

### Laststatus

You should set `laststatus` by yourself. I recommend you set `laststatus` to `3` to be better.

```lua
vim.o.laststatus = 3
```

### Options

You can setup the plugin by calling the `setup` function and passing in a table of options.

```lua
require("witch-line").setup({
  --- @type CombinedComponent[]
  abstracts = {
    "wl.file.name",
    {
      id = "file", -- Abstract component for file-related info
      padding = { left = 1, right = 1 }, -- Padding around the component
      static = { some_key = "some_value" }, -- Static metadata
      style = { fg = "#ffffff", bg = "#000000", bold = true }, -- Style override
      min_screen_width = 80,          -- Hide if screen width < 80
    },
  },

  --- @type CombinedComponent[]
  statusline = {
    --- The global statusline components
    --- Set it to `nil` if you want to use default components in example
    global = {
        "wl.mode",
        "wl.file.name",
        "wl.git.branch",
        {
          id = "component_id",               -- Unique identifier
          padding = { left = 1, right = 1 }, -- Padding around the component
          static = { some_key = "some_value" }, -- Static metadata
          win_individual = false,
          timing = false,                 -- No timing updates
          style = { fg = "#ffffff", bg = "#000000", bold = true }, -- Style override
          min_screen_width = 80,          -- Hide if screen width < 80
          hidden = function()               -- Hide condition
            return vim.bo.buftype == "nofile"
          end,
          left_style = { fg = "#ff0000" }, -- Left style override
          update = function(self, ctx, static, session_id) -- Main content generator
            return vim.fn.expand("%:t")
          end,
          ref = {                       -- References to other components
            events = { "wl.file.name" },
            style = "wl.file.name",
            static = "wl.file.name",
          },
        },
    },

    -- @type fun(winid): CombinedComponent[]|nil
    win = nil
  },

  cache = {
      -- You can disable cache here.
      -- If you enable cache you can not use any up-value in your component functions otherwise your
      -- cache will be broken.
      enabled = true,
      -- Show notification when cache is cleared. Default true.
      notification = true,
      -- Strip debug info when caching dumped functions. Default false. Faster but harder to debug.
      func_strip = false,
  },

  disabled = {
    filetypes = { "help", "TelescopePrompt" },
    buftypes = { "nofile", "terminal" },
  },

  --- Whether to automatically adjust the theme.
  --- If it is set to false the `auto_theme` field of the component will be ignored.
  --- Default: true.
  --- You can toggle it by `:Witchline toggle_auto_theme`
  auto_theme = true

})

```

#### Top level options

| Field        | Type                                                                     | Description                                                                                                               |
| ------------ | ------------------------------------------------------------------------ | ------------------------------------------------------------------------------------------------------------------------- |
| `abstracts`  | `CombinedComponent[]`                                                    | A list of abstract components registered before everything else. Used for component references and dependency resolution. |
| `statusline` | `{ global: CombinedComponent[], win?: fun(winid): CombinedComponent[] }` | Defines the global statusline and optional per-window statusline overrides.                                               |
| `cache`      | `{ full_scan: boolean, notification: boolean, func_strip: boolean }`     | Cache behavior and optimizations.                                                                                         |
| `disabled`   | `{ filetypes: string[], buftypes: string[] }`                            | Filetypes/buftypes where the plugin should be disabled.                                                                   |

#### statusline

| Key      | Type                              | Description                                                                                                                                                                            |
| -------- | --------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `global` | `CombinedComponent[]\|nil`        | Global statusline components. Set to `nil` if you want to use default components in example.                                                                                           |
| `win`    | `fun(winid): CombinedComponent[]` | Per-window statusline components. When using this field, you must set `laststatus` to `2` or `1`, and you must add all neccesary components to the `abstracts` field to let it's work. |

Example config using `win` option

```lua
require("witch-line").setup({
    abstracts = {
        "wl.battery", -- pre register battery to use in win option
        -- require("your custom component")
    }
    statusline = {
        global = {
            "wl.file.name",
            "wl.git.branch",
            --- require("your custom component")
            --- Other components
        }
        win = function(winid
          --- Only show battery in NvimTree window
          local filetype = vim.bo[vim.api.nvim_win_get_buf(winid)].filetype
          if filetype == "NvimTree" then
            return {
                "wl.battery",
                -- require("your custom component")
            }
          end
        end
    }

})
```

#### cache

| Key            | Type      | Default | Description                                                   |
| -------------- | --------- | ------- | ------------------------------------------------------------- |
| `enabled`      | `boolean` | `true`  | Enable caching.                                               |
| `notification` | `boolean` | `true`  | Shows a notification when the cache is cleared.               |
| `func_strip`   | `boolean` | `false` | Strips debug info from dumped functions to reduce cache size. |

#### disabled

| Key         | Type       | Description                                    |
| ----------- | ---------- | ---------------------------------------------- |
| `filetypes` | `string[]` | Filetypes where the plugin should be disabled. |
| `buftypes`  | `string[]` | Buftypes where the plugin should be disabled.  |

### Commands

The plugin provides the following commands:

- `:Witchline clear_cache` - Clear the plugin's cache.
- `:Witchline inspect` - Use for debugging and inspecting internal state.
- `:Witchline toggle_auto_theme` - Toggle automatic theme adjustment.

## 🧾 Default Components Reference

This section describes the built-in components available in the plugin, their structure, and how to use them.
Each component is referenced by name and can be composed to build a flexible and performant statusline.

---

### 🔖 Default Components

| Name                  | Module File       | Description                               |
| --------------------- | ----------------- | ----------------------------------------- |
| `mode`                | `mode.lua`        | Shows the current Neovim mode             |
| `file.name`           | `file.lua`        | Displays the filename                     |
| `file.icon`           | `file.lua`        | Displays an icon for the file             |
| `file.modifier`       | `file.lua`        | Indicates if the file has unsaved changes |
| `file.size`           | `file.lua`        | Shows the file size                       |
| `%=`                  | _(builtin)_       | Separator to align left/right components  |
| `copilot`             | `ai/copilot.lua`  | Shows Copilot status (if available)       |
| `windsurf`            | `ai/windsurf.lua` | Shows Codeium status (if available)       |
| `windsurf.neocodeium` | `ai/windsurf.lua` | Shows Neocodium status (if available)     |
| `diagnostic.error`    | `diagnostic.lua`  | Shows number of error diagnostics         |
| `diagnostic.warn`     | `diagnostic.lua`  | Shows number of warning diagnostics       |
| `diagnostic.info`     | `diagnostic.lua`  | Shows number of info diagnostics          |
| `diagnostic.hint`     | `diagnostic.lua`  | Shows number of hint diagnostics          |
| `encoding`            | `encoding.lua`    | Displays file encoding (e.g., utf-8)      |
| `cursor.pos`          | `cursor.lua`      | Shows the current cursor line/column      |
| `cursor.progress`     | `cursor.lua`      | Shows the cursor position as a % progress |
| `lsp.clients`         | `lsp.lua`         | Lists active LSP clients                  |
| `git.branch`          | `git.lua`         | Shows current Git branch                  |
| `git.diff.added`      | `git.lua`         | Number of added lines in Git diff         |
| `git.diff.removed`    | `git.lua`         | Number of removed lines in Git diff       |
| `git.diff.modified`   | `git.lua`         | Number of changed lines in Git diff       |
| `datetime`            | `datetime.lua`    | Displays current date and time            |
| `battery`             | `battery.lua`     | Shows battery status (if applicable)      |
| `os_uname`            | `os_uname.lua`    | Displays the operating system name        |
| `nvim_dap`            | `nvim_dap.lua`    | Shows nvim-dap status (if available)      |
| `search.count`        | `search.lua`      | Shows number of searching value           |
| `selection.count`     | `selection.lua`   | Shows number of selection zone            |

---

### 🛠️ Customizable Fields for Components

Each component accepts a set of customization fields to control its behavior, style, visibility, and layout.

Below is a table of all supported fields and their expected types:

| Field              | Type(s)               | Description                                                                       |
| ------------------ | --------------------- | --------------------------------------------------------------------------------- |
| `padding`          | `number`, `table`     | Adds padding around the component. Can be a single number or `{ left, right }`.   |
| `static`           | `any`                 | Any static value or metadata the component wants to keep.                         |
| `timing`           | `boolean`, `number`   | Enables timing or sets a custom update interval for the component.                |
| `style`            | `function`, `table`   | Style override for the entire component output (e.g., color, bold).               |
| `min_screen_width` | `number`              | Hides the component if the screen width is below this threshold.                  |
| `hidden`           | `function`, `boolean` | Hide condition. If `true` or a function that returns `true`, hides the component. |
| `left_style`       | `function`, `table`   | Style override applied to the left part of the component.                         |
| `left`             | `string`, `function`  | Left content to be rendered. Can be a string or a generator function.             |
| `right_style`      | `function`, `table`   | Style override applied to the right part of the component.                        |
| `right`            | `string`, `function`  | Right content to be rendered. Can be a string or a generator function.            |
| `flexible`         | `number`              | Priority for hiding when space is limited. Lower numbers hide first.              |

---

You can use the `require("witch-line.builtin").comp` builtin function to create a customized version of any default component by specifying overrides for these fields.

```lua

local my_component = require("witch-line.builtin").comp("wl.file.name", {
  padding = { left = 2 },
  min_screen_width = 60,
  hidden = function()
    return vim.bo.buftype == "nofile"
  end,
  style = { fg = "#ffffff", bg = "#222222", bold = true },
})
```

Or you can also use the [0] field to override the default component.

```lua
local my_component = {
  [0] = "wl.file.name",  -- Inherit from the default file.name component
  padding = { left = 2 },
  min_screen_width = 60,
  hidden = function()
    return vim.bo.buftype == "nofile"
  end,
  style = { fg = "#ffffff", bg = "#222222", bold = true },
}
```

---

## 🧠 Component Structure

Each component is represented as a Lua table with various fields that define its behavior, appearance, and interactions. You can read the [COOKBOOK](./docs/COOKBOOK.md) for more examples of component structure.

## 📚 Public APIs

The plugin exposes a set of public APIs for advanced usage and customization. You can find the API reference in the [API.md](./docs/API.md) file.

## 🤝 Community Help & Contributions Wanted

`witch-line` is a flexible and powerful statusline plugin for Neovim, but there's still a lot of room to improve and grow. I'm actively seeking help and contributions from the community to make this project even better.

Here are a few areas where your help would be especially appreciated:

- 📘 **API Documentation**
  Help rewrite and polish the API reference into clear and professional documentation. Better docs will make it easier for others to build powerful custom setups.

- 🧬 **Serialization System**
  Design and implement a robust system to serialize and deserialize component configurations. This would help cache system work better.

- 🧪 **Component Testing Framework**
  Improve or design an ergonomic and declarative way to test components individually and ensure they behave consistently in different contexts.

- 📦 **Plugin Ecosystem**
  You can create new plugin extensions built on top of `witch-line`—such as battery indicators, LSP diagnostics, Git integrations, and more.

- 💡 **Ideas, Feedback, and Bug Reports**
  Even if you’re not a coder, suggestions, feedback, and bug reports are very welcome.

If you’re interested in helping, feel free to open an issue, start a discussion, or submit a PR. Let's build something awesome together. 🙏

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details
