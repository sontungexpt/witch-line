## witch-line

The best statusline plugin for neovim. It's very lightweight and super fast.

This plugin lazy load as much as possible

## Table of Contents

- ❓ [Features](#features)
- 👀 [Installation](#installation)
- 🤖 [Options](#options)
- 🤔 [A few words to say](#a-few-words-to-say)
- 🤩 [Preview](#preview)
- 😆 [Usage](#usage)
- ☀️ [Create new component](#create-new-component)
- 💻 [Default Components](#components)
- 📰 [Detail of each key](#detail-of-each-key)
- 😁 [Contributing](#contributing)
- ✌️ [License](#license)

## A few words to say

🎉 The default component is written for my personal use. So maybe you need to
create your own component. I'm very happy to see your component. So if you have
any idea to create a new component, please open an issue or pull request.

## Preview

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

## Installation

```lua
    -- lazy
    {
        "sontungexpt/witch-line",
        dependencies = {
            "nvim-tree/nvim-web-devicons",
        },
        event = { "BufEnter" },
        config = function(_, opts)
            require("sttusline").setup()
        end,
    },
```

## Usage

### Options

You can setup the plugin by calling the `setup` function and passing in a table of options.

```lua

require("witch-line").setup({
  --- @type Component[]
  abstract = {},
  --- @type CombinedComponent
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
      hide = function()               -- Hide condition
        return vim.bo.buftype == "nofile"
      end,
      left_style = { fg = "#ff0000" }, -- Left style override
      left = function(self, ctx, static, session_id) -- Left content generator
        return "File: " .. vim.fn.expand("%:t")
      end,
      right_style = { fg = "#00ff00" }, -- Right style override
      right = function(self, ctx, static, session_id) -- Right content generator
        return " [" .. vim.fn.expand("%:p") .. "]"
      end,
      update = function(self, ctx, static, session_id) -- Main content generator
        return vim.fn.expand("%:t")
      end,
      ref = {                       -- References to other components
        events = { "file.events" },
        style = "file.style",
        static = "file.static",
        hide = { "file.hide" },
      },
      init = function(self, static)  -- Initialization function
        -- Custom setup logic here
      end,
    },
  },
  disabled = {
    filetypes = { "help", "TelescopePrompt" },
    buftypes = { "nofile", "terminal" },
  },
})

```

### Laststatus

You should set `laststatus` by yourself. I recommend you set `laststatus` to `3` to be better.

```lua
vim.opt.laststatus = 3
```

# ✨ Default Components Reference

This section describes the built-in components available in the plugin, their structure, and how to use them.
Each component is referenced by name and can be composed to build a flexible and performant statusline.

---

## 🔖 Default Components

| Name               | Module File      | Description                               |
| ------------------ | ---------------- | ----------------------------------------- |
| `mode`             | `mode.lua`       | Shows the current Neovim mode             |
| `file.name`        | `file.lua`       | Displays the filename                     |
| `file.icon`        | `file.lua`       | Displays an icon for the file             |
| `file.modified`    | `file.lua`       | Indicates if the file has unsaved changes |
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

---

## ⚙️ Customizable Fields for Components

Each component accepts a set of customization fields to control its behavior, style, visibility, and layout.

Below is a table of all supported fields and their expected types:

| Field              | Type(s)               | Description                                                                       |
| ------------------ | --------------------- | --------------------------------------------------------------------------------- |
| `padding`          | `number`, `table`     | Adds padding around the component. Can be a single number or `{ left, right }`.   |
| `static`           | `any`                 | Any static value or metadata the component wants to keep.                         |
| `timing`           | `boolean`, `number`   | Enables timing or sets a custom update interval for the component.                |
| `style`            | `function`, `table`   | Style override for the entire component output (e.g., color, bold).               |
| `min_screen_width` | `number`              | Hides the component if the screen width is below this threshold.                  |
| `hide`             | `function`, `boolean` | Hide condition. If `true` or a function that returns `true`, hides the component. |
| `left_style`       | `function`, `table`   | Style override applied to the left part of the component.                         |
| `left`             | `string`, `function`  | Left content to be rendered. Can be a string or a generator function.             |
| `right_style`      | `function`, `table`   | Style override applied to the right part of the component.                        |
| `right`            | `string`, `function`  | Right content to be rendered. Can be a string or a generator function.            |

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

## 📂 Component Structure

Each component is represented as a Lua table with various fields that define its behavior, appearance, and interactions. Below is a detailed reference of the fields available for each component.

### 🔗 Type Aliases

| Alias           | Definition                                                                                                |
| --------------- | --------------------------------------------------------------------------------------------------------- |
| `PaddingFunc`   | `(self, ctx, static, session_id) → number ,  PaddingTable`                                                |
| `PaddingTable`  | `{ left: integer\|nil\|PaddingFunc, right: integer\|nil\|PaddingFunc }`                                   |
| `UpdateFunc`    | `(self, ctx, static, session_id) → string \| nil`                                                         |
| `StyleFunc`     | `(self, ctx, static, session_id) → vim.api.keyset.highlight`                                              |
| `SideStyleFunc` | `(self, ctx, static, session_id) → table \| SepStyle`                                                     |
| `SepStyle`      | `{ fg: string\|nil, bg: string\|nil, bold: boolean\|nil, underline: boolean\|nil, italic: boolean\|nil }` |
| `CompId`        | `string \| integer`                                                                                       |
| `SessionId`     | `SessionId`                                                                                               |

---

### 🔗 Ref Table Subfields

Each component in `witch-line` is a table with powerful customization capabilities. Here's a complete reference of available fields:

The `ref` field supports the following subfields for deferred configuration:

| Field              | Type                 | Description                                                  |
| ------------------ | -------------------- | ------------------------------------------------------------ |
| `events`           | `CompId \| CompId[]` | References components that provide events.                   |
| `user_events`      | `CompId \| CompId[]` | References components that provide user-defined events.      |
| `timing`           | `CompId \| CompId[]` | References components that provide timing updates.           |
| `style`            | `CompId`             | Reference to a component whose style will be used.           |
| `static`           | `CompId`             | Reference to a component that provides static values.        |
| `context`          | `CompId`             | Reference to a component that provides context values.       |
| `hide`             | `CompId \| CompId[]` | Reference to components that provide a hide function.        |
| `min_screen_width` | `CompId \| CompId[]` | Reference to components that provide min screen width logic. |

Example:

```lua

-- Its means that the component will references events, style, static, and hide logic from the "file" component.
-- In another word,
-- - When the component with id "file" is updated on events, this component will also be updated or if the "file" component is hidden, this component will also be hidden.
-- - The style of this component will be the same as the "file" component.
-- - The static value of this component will be the same as the "file" component.

{
  id = "my_component",
  ref = {
    events = { "file" },
    style = "file",
    static = "file",
    hide = { "file" },
  },
  update = function(self, ctx, static, session_id)
    return static.filename or "No Name"
  end,
}
```

---

### 🔧 Component Fields

| Field              | Type(s)                                                           | Description                                                                 |
| ------------------ | ----------------------------------------------------------------- | --------------------------------------------------------------------------- | ---------------------------------------------------------------------------- |
| `id`               | `CompId`                                                          | Unique identifier for the component.                                        |
| `version`          | `integer`, `string`, `nil`                                        | Version of the component for cache management.                              |
| `inherit`          | `CompId`, `nil`                                                   | ID of another component to inherit properties from.                         |
| `timing`           | `boolean`, `integer`, `nil`                                       | Enables timing updates or sets a custom interval.                           |
| `lazy`             | `boolean`, `nil`                                                  | If true, the component is loaded only when needed.                          |
| `padding`          | `number`, `table`, `PaddingFunc`, `nil`                           | Padding around the component. Can be a number, table, or function.          |
| `static`           | `any`, `nil`                                                      | Static value or metadata for the component.                                 |
| `context`          | `any`, `nil`, `fun(self, static, session_id)`                     | Context value for the component.                                            |
| `pre_update`       | `fun(self, ctx, static, session_id)`, `nil`                       | Called before the component is updated, can be used to set up the context.  |
| `post_update`      | `fun(self, ctx, static, session_id)`, `nil`                       | Called after the component is updated, can be used to clean up the context. |
| `update`           | `UpdateFunc`, `nil`                                               | Function to generate the component's content.                               |
| `style`            | `vim.api.keyset.highlight`, `table`, `StyleFunc`, `nil`           |                                                                             | Style override for the entire component output.                              |
| `min_screen_width` | `number`, `nil`, `fun(self, ctx, static, session_id) -> number`   | Hides the component if screen width is below this threshold.                |
| `hide`             | `boolean`, `fun(self, ctx, static, session_id) -> boolean`, `nil` | Hide condition. If true or a function returning true, hides the component.  |
| `left_style`       | `vim.api.keyset.highlight`, `table`, `SideStyleFunc`, `nil`       | Style override for the left part of the component.                          |
| `left`             | `string`, `UpdateFunc`, `nil`                                     | Left content to be rendered. Can be a string or generator function.         |
| `right_style`      | `vim.api.keyset.highlight`, `table`, `SideStyleFunc`, `nil`       | Style override for the right part of the component.                         |
| `right`            | `string`, `UpdateFunc`, `nil`                                     | Right content to be rendered. Can be a string or generator function.        |
| `ref`              | `table`, `nil`                                                    | References to other components for deferred configuration.                  |
| `init`             | `fun(self, ctx, static, session_id)`, `nil`                       |                                                                             | Called when the component is initialized, can be used to set up the context. |
| `events`           | `CompId`, `CompId[]`, `nil`                                       | References components that provide events.                                  |
| `user_events`      | `CompId`, `CompId[]`, `nil`                                       | References components that provide user-defined events.                     |
| `style`            | `CompId`, `nil`                                                   | Reference to a component whose style will be used.                          |

### 📚 Example Component Structure

## 🙌 Community Help & Contributions Wanted

`witch-line` is a flexible and powerful statusline plugin for Neovim, but there's still a lot of room to improve and grow. I'm actively seeking help and contributions from the community to make this project even better.

Here are a few areas where your help would be especially appreciated:

- 📘 **API Documentation**
  Help rewrite and polish the API reference into clear and professional documentation. Better docs will make it easier for others to build powerful custom setups.

- 🧬 **Serialization System**
  Design and implement a robust system to serialize and deserialize component configurations. This would help cache system worj better

- 🧪 **Component Testing Framework**
  Improve or design an ergonomic and declarative way to test components individually and ensure they behave consistently in different contexts.

- 📦 **Plugin Ecosystem**
  You can create new plugin extensions built on top of `witch-line`—such as battery indicators, LSP diagnostics, Git integrations, and more.

- 💡 **Ideas, Feedback, and Bug Reports**
  Even if you’re not a coder, suggestions, feedback, and bug reports are very welcome.

If you’re interested in helping, feel free to open an issue, start a discussion, or submit a PR. Let's build something awesome together. 🙏

## License

This project is licensed under the MIT License - see the [LICENSE](LICENSE) file for details
