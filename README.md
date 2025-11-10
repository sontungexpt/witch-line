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

- I like the reference concept in any database structure based on id. So I use the same concept in this plugin for component system. You can reference other component by id to share some field like events, style, static, context, hide, min_screen_width. This will help you to create a component based on other component without duplicate code.

- This plugin also support inherit field from parent by recursively. So you can create a component based on other component and override some field like [heirline](https://github.com/rebelot/heirline.nvim). But I think the reference concept is better than inherit concept because you can share some field between components. And the statusline is a flat structure so you don't need to create a nested structure like heirline.

## Preview

- Basic style (No separator, I aprreciate basic but you can create it or do many things else by yourself (like add separator) or you can create new PR for your feature you wantc)
  <img width="1899" height="128" alt="image" src="https://github.com/user-attachments/assets/6bfcc79b-5db6-4419-aced-34deef1fd8c5" />

## ✨ Features

`witch-line` is a fast, lightweight, and fully customizable statusline plugin for Neovim. It focuses on modularity, caching, and performance. Below are the key features:

- ⚡ **Blazing Fast**: Optimized with internal caching and minimal redraws to keep your statusline snappy and efficient. Just config for first time and **every thing** will be cache and run super fast later.

- 🧩 **Modular Components**: Define reusable and nested components using a simple configuration format.

- 🎛 **Abstract Components**: Support for abstract components that can be composed and reused without rendering directly.

- 🎨 **Flexible Layouts**: Arrange statusline components in any order, across multiple layers or segments.

- 🔁 **Reactive Updates**: Smart detection of buffer/file changes to update only when necessary.

- 📁 **Context-Aware Disabling**: Automatically disable the statusline for specific `filetypes` or `buftypes` (e.g. terminal, help, etc).

- 🧠 **Config Hashing**: Detect if user config has changed via FNV-1a hashing, ensuring minimal reinitialization.

- 💾 **Persistent Caching**: Cache user configurations and state across sessions using a simple key-value system.

- 🧪 **Testable & Maintainable**: Designed with testability and clear API boundaries in mind.

- 🛠 **Extensible**: Easily extend with custom components.

This plugin is ideal for developers who want full control over the look and feel of their statusline, without sacrificing performance or flexibility.

---

### TODO

- Laststatus

  - [ ] Support for laststatus = 1
  - [ ] Support for laststatus = 2
  - [x] Support for laststatus = 3
  - [x] Support for laststatus = 0

- Cache

  - [x] Implement caching mechanism (serialization + deserialization)
  - [x] Cache all needed data
  - [x] Use checksum to detect config changes with FNV-1a
  - [ ] Support up-value for component function caching
  - [ ] Support paritial cache loading
  - [ ] Detect default component changed automatically when plugin was updated

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
  - [x] Support events field to listen to other component events
  - [x] Support user_events field to listen to user-defined events
  - [x] Support timing field to update component periodically
  - [x] Support lazy field to lazy load component
  - [x] Support padding field to add padding around component
  - [x] Support style field to override component style
  - [x] Support left_style field to override left part style
  - [x] Support right_style field to override right part style
  - [x] Support left field to add left content
  - [x] Support right field to add right content
  - [x] Support min_screen_width field to hide component if screen width is less than this value
  - [x] Support hide field to hide component based on condition
  - [x] Support init function to initialize component
  - [x] Support pre_update function to run before update function
  - [x] Support post_update function to run after update function
  - [x] Support update function to generate component content
  - [x] Support ref field to reference other component fields (events, style, static, context, hide, min_screen_width)
  - [x] Support version field to manage component cache
  - [x] Support flexible field to hide component based on priority when space is limited
  - [x] Support on_click function to handle click events
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

- Theme

  - [ ] Create a theme systems
  - [ ] Auto adjust color of components based on theme

### Compare with other statusline plugins

---

### Benchmarks

The benchmarks of 11 runs:

This is just an example because I don't have much time to make each statusline with the same ui.
And i'm not sure is it the best config for each statusline.

I just run with the default config of each plugin.

If some one remake your current statusline with "witch-line", could you send me the config of each statusline to make it properly?

The benchmarks is run with `nvim -u` with only the statusline plugin loaded.

| Plugin     | Load Time (ms) | Avg Update Time (ms) |
| ---------- | -------------- | -------------------- |
| witch-line | 21.7409090909  |                      |
| lualine    | 86.0590909     |                      |

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
  abstract = {
    "file.name",
    {
      id = "file", -- Abstract component for file-related info
      padding = { left = 1, right = 1 }, -- Padding around the component
      static = { some_key = "some_value" }, -- Static metadata
      style = { fg = "#ffffff", bg = "#000000", bold = true }, -- Style override
      min_screen_width = 80,          -- Hide if screen width < 80
    },
  },
  --- @type CombinedComponent[]
  components = {
    "mode",
    "file.name",
    "file.icon",
    {
      id = "component_id",               -- Unique identifier
      padding = { left = 1, right = 1 }, -- Padding around the component
      static = { some_key = "some_value" }, -- Static metadata
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
        events = { "file.name" },
        style = "file.name",
        static = "file.name",
      },
    },
  },
  disabled = {
    filetypes = { "help", "TelescopePrompt" },
    buftypes = { "nofile", "terminal" },
  },
})

```

### Commands

The plugin provides the following commands:

- `:Witchline clear_cache` - Clear the plugin's cache.
- `:Witchline inspect` - Use for debugging and inspecting internal state.

## 🧾 Default Components Reference

This section describes the built-in components available in the plugin, their structure, and how to use them.
Each component is referenced by name and can be composed to build a flexible and performant statusline.

---

### 🔖 Default Components

| Name               | Module File      | Description                               |
| ------------------ | ---------------- | ----------------------------------------- |
| `mode`             | `mode.lua`       | Shows the current Neovim mode             |
| `file.name`        | `file.lua`       | Displays the filename                     |
| `file.icon`        | `file.lua`       | Displays an icon for the file             |
| `file.modified`    | `file.lua`       | Indicates if the file has unsaved changes |
| `file.size`        | `file.lua`       | Shows the file size                       |
| `%=`               | _(builtin)_      | Separator to align left/right components  |
| `copilot`          | `copilot.lua`    | Shows Copilot status (if available)       |
| `diagnostic.error` | `diagnostic.lua` | Shows number of errors in current buffer  |
| `diagnostic.warn`  | `diagnostic.lua` | Shows number of warnings                  |
| `diagnostic.info`  | `diagnostic.lua` | Shows info-level diagnostics              |
| `encoding`         | `encoding.lua`   | Displays file encoding (e.g., utf-8)      |
| `cursor.pos`       | `cursor.lua`     | Shows the current cursor line/column      |
| `cursor.progress`  | `cursor.lua`     | Shows the cursor position as a % progress |
| `lsp.clients`      | `lsp.lua`        | Lists active LSP clients                  |
| `git.branch`       | `git.lua`        | Shows current Git branch                  |
| `git.added`        | `git.lua`        | Number of added lines in Git diff         |
| `git.removed`      | `git.lua`        | Number of removed lines in Git diff       |
| `git.modified`     | `git.lua`        | Number of changed lines in Git diff       |
| `datetime`         | `datetime.lua`   | Displays current date and time            |
| `battery`          | `battery.lua`    | Shows battery status (if applicable)      |
| `os_uname`         | `os_uname.lua`   | Displays the operating system name        |
| `nvim_dap`         | `nvim_dap.lua`   | Shows nvim-dap status (if available)      |

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

local my_component = require("witch-line.builtin").comp("file.name", {
  padding = { left = 2 },
  min_screen_width = 60,
  hide = function()
    return vim.bo.buftype == "nofile"
  end,
  style = { fg = "#ffffff", bg = "#222222", bold = true },
})
```

Or you can also use the [0] field to override the default component.

```lua
local my_component = {
  [0] = "file.name",  -- Inherit from the default file.name component
  padding = { left = 2 },
  min_screen_width = 60,
  hide = function()
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
