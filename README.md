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

- ⚡ **Blazing Fast**: Optimized with minimal redraws to keep your statusline snappy and efficient.

- 🧩 **Modular Components**: Define reusable and nested components using a simple configuration format.

- 🎛 **Abstract Components**: Support for abstract components that can be composed and reused without rendering directly.

- 🎨 **Flexible Layouts**: Arrange statusline components in any order, across multiple layers or segments.

- 🔁 **Reactive Updates**: Smart detection of buffer/file changes to update only when necessary.

- 📁 **Context-Aware Disabling**: Automatically disable the statusline for specific `filetypes` or `buftypes` (e.g. terminal, help, etc).

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

  - [x] Implement `:Witchline` command to inspect and toggle features

- Testing

  - [ ] Write unit tests for core functionality
  - [ ] Write performance benchmarks

- Themes

  - [x] Auto adjust color of components based on theme
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
  statusline = {
    global = {
        "wl.mode",
        "wl.file.name",
        "wl.git.branch",
        {
          id = "wl.my_comp",
          padding = { left = 1, right = 1 },
          static = { some_key = "some_value" },
          style = { fg = "#ffffff", bg = "#000000", bold = true },
          update = function(self, session)
            return vim.fn.expand("%:t")
          end,
        },
    },
    win = nil,
  },

  disabled = {
    filetypes = { "help", "TelescopePrompt" },
    buftypes = { "nofile", "terminal" },
  },

  auto_theme = true,
})
```

#### Top level options

| Field        | Type                                                                     | Description                                                                 |
| ------------ | ------------------------------------------------------------------------ | --------------------------------------------------------------------------- |
| `statusline` | `{ global: CombinedComponent[], win?: fun(winid): CombinedComponent[] }` | Defines the global statusline and optional per-window overrides.            |
| `disabled`   | `{ filetypes: string[], buftypes: string[] }`                            | Filetypes/buftypes where the plugin should be disabled.                     |
| `auto_theme` | `boolean`                                                                | Whether to automatically adjust component colors to match the colorscheme. |

#### statusline

| Key      | Type                              | Description                                                                                                                                                                            |
| -------- | --------------------------------- | -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `global` | `CombinedComponent[]\|nil`        | Global statusline components. Set to `nil` if you want to use default components in example.                                                                                           |
| `win`    | `fun(winid): CombinedComponent[]` | Per-window statusline components. When using this field, you must set `laststatus` to `2` or `1`, and you must add all neccesary components to the `abstracts` field to let it's work. |

Example config using `win` option

```lua
require("witch-line").setup({
    statusline = {
        global = {
            "wl.file.name",
            "wl.git.branch",
        },
        win = function(winid)
          local filetype = vim.bo[vim.api.nvim_win_get_buf(winid)].filetype
          if filetype == "NvimTree" then
            return { "wl.battery" }
          end
        end,
    },
})
```

#### disabled

| Key         | Type       | Description                                    |
| ----------- | ---------- | ---------------------------------------------- |
| `filetypes` | `string[]` | Filetypes where the plugin should be disabled. |
| `buftypes`  | `string[]` | Buftypes where the plugin should be disabled.  |

### Commands

The plugin provides the `:Witchline` command with subcommands:

| Command | Description |
| --- | --- |
| `:Witchline toggle_auto_theme` | Toggle automatic theme adjustment |
| `:Witchline inspect event_store` | Inspect event store |
| `:Witchline inspect timer_store` | Inspect timer store |
| `:Witchline inspect comp_manager comps` | Inspect registered components |
| `:Witchline inspect comp_manager dep_store` | Inspect dependency graph |
| `:Witchline inspect highlight rgb24bit` | Inspect RGB color cache |
| `:Witchline inspect highlight styles` | Inspect highlight style cache |
| `:Witchline inspect statusline` | Inspect statusline state |

## 🧾 Default Components Reference

This section describes the built-in components available in the plugin, their structure, and how to use them.
Each component is referenced by name and can be composed to build a flexible and performant statusline.

---

### 🔖 Default Components

| Name                       | Module File            | Description                               |
| -------------------------- | ---------------------- | ----------------------------------------- |
| `wl.mode`                  | `mode.lua`             | Shows the current Neovim mode             |
| `wl.file.name`             | `file.lua`             | Displays the filename                     |
| `wl.file.icon`             | `file.lua`             | Displays an icon for the file             |
| `wl.file.modifier`         | `file.lua`             | Indicates if the file has unsaved changes |
| `wl.file.size`             | `file.lua`             | Shows the file size                       |
| `%=`                       | _(builtin)_            | Separator to align left/right components  |
| `wl.copilot`               | `ai/copilot.lua`       | Shows Copilot status (if available)       |
| `wl.windsurf`              | `ai/windsurf.lua`      | Shows Windsurf status (if available)      |
| `wl.windsurf.neocodeium`   | `ai/windsurf.lua`      | Shows Neocodeium status (if available)    |
| `wl.diagnostic.error`      | `diagnostic.lua`       | Shows number of error diagnostics         |
| `wl.diagnostic.warn`       | `diagnostic.lua`       | Shows number of warning diagnostics       |
| `wl.diagnostic.info`       | `diagnostic.lua`       | Shows number of info diagnostics          |
| `wl.diagnostic.hint`       | `diagnostic.lua`       | Shows number of hint diagnostics          |
| `wl.encoding`              | `encoding.lua`         | Displays file encoding (e.g., utf-8)      |
| `wl.cursor.pos`            | `cursor.lua`           | Shows the current cursor line/column      |
| `wl.cursor.progress`       | `cursor.lua`           | Shows the cursor position as a % progress |
| `wl.lsp.clients`           | `lsp.lua`              | Lists active LSP clients                  |
| `wl.indent`                | `indent.lua`           | Shows the indent level                    |
| `wl.git.branch`            | `git.lua`              | Shows current Git branch                  |
| `wl.git.diff.added`        | `git.lua`              | Number of added lines in Git diff         |
| `wl.git.diff.removed`      | `git.lua`              | Number of removed lines in Git diff       |
| `wl.git.diff.modified`     | `git.lua`              | Number of changed lines in Git diff       |
| `wl.datetime`              | `datetime.lua`         | Displays current date and time            |
| `wl.battery`               | `battery.lua`          | Shows battery status (if applicable)      |
| `wl.os_uname`              | `os_uname.lua`         | Displays the operating system name        |
| `wl.nvim_dap`              | `nvim_dap.lua`         | Shows nvim-dap status (if available)      |
| `wl.search.count`          | `search.lua`           | Shows number of searching value           |
| `wl.selection.count`       | `selection.lua`        | Shows number of selection zone            |

---

### 🛠️ Customizable Fields for Components

See the [COOKBOOK](./docs/COOKBOOK.md) for the full component field reference.

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

- 🧪 **Component Testing Framework**
  Improve or design an ergonomic and declarative way to test components individually and ensure they behave consistently in different contexts.

- 📦 **Plugin Ecosystem**
  You can create new plugin extensions built on top of `witch-line`—such as battery indicators, LSP diagnostics, Git integrations, and more.

- 💡 **Ideas, Feedback, and Bug Reports**
  Even if you’re not a coder, suggestions, feedback, and bug reports are very welcome.

If you’re interested in helping, feel free to open an issue, start a discussion, or submit a PR. Let's build something awesome together. 🙏

## 📜 License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details
