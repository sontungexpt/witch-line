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

- ⚡ **Blazing Fast**: Optimized with internal caching and minimal redraws to keep your statusline snappy and efficient. Just config for first time and **every thing** will be cache and run super fast  later.

- 🧩 **Modular Components**: Define reusable and nested components using a simple configuration format.

- 🎛 **Abstract Components**: Support for abstract components that can be composed and reused without rendering directly.

- 🎨 **Flexible Layouts**: Arrange statusline components in any order, across multiple layers or segments.

- 🔁 **Reactive Updates**: Smart detection of buffer/file changes to update only when necessary.

- 📁 **Context-Aware Disabling**: Automatically disable the statusline for specific `filetypes` or `buftypes` (e.g. terminal, help, etc).

- 🧠 **Config Hashing**: Detect if user config has changed via FNV-1a hashing, ensuring minimal reinitialization.

- 💾 **Persistent Caching**: Cache user configurations and state across sessions using a simple key-value system.

- 🧪 **Testable &  Maintainable**: Designed with testability and clear API boundaries in mind.

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

## Options

```lua

require("witch-line").setup({
  components = {
     "mode" ,
     "file.name", 
     "file.icon",
  },
  disabled = {
    filetypes = { "help", "TelescopePrompt" },
    buftypes = { "nofile", "terminal" },
  },
})

```

## Usage

### Laststatus

You should set `laststatus` by yourself. I recommend you set `laststatus` to `3` to be better.

```lua
vim.opt.laststatus = 3
```

### Components

We provide you some default component:

| **Component**         | **Description**                                              |
| --------------------- | ------------------------------------------------------------ |
| `datetime`            | Show datetime                                                |
| `mode`                | Show current mode                                            |
| `filename`            | Show current filename                                        |
| `git-branch`          | Show git branch                                              |
| `git-diff`            | Show git diff                                                |
| `diagnostics`         | Show diagnostics                                             |
| `lsps-formatters`     | Show lsps, formatters(support for null-ls and conform)       |
| `copilot`             | Show copilot status                                          |
| `copilot-loading`     | Show copilot loading                                         |
| `indent`              | Show indent                                                  |
| `encoding`            | Show encoding                                                |
| `pos-cursor`          | Show position of cursor                                      |
| `pos-cursor-progress` | Show position of cursor with progress                        |
| `os-uname`            | Show os name                                                 |
| `filesize`            | Show filesize                                                |
| `battery`             | Show battery (support for linux only because i'm linux user) |

To use default component use should add name of component to components options
or you can add a table with the first value is the name of component and second
value is the table that you want to override default component

##### Use default component with default configs

```lua
    require("sttusline").setup {
        components = {
            "mode", -- use default component with default configs
        },
    }
```

##### Use default component and override default configs

**NOTE**: The override component must be a table with the first value is the name of
default component and the second value is the table with `any key that a new component can have.
All keys is list [here](#create-new-component)

😊 How to know what configs you can override? You can see the [default component
configs](https://github.com/sontungexpt/sttusline/tree/table_version/lua/sttusline/components) and override any thing
you want event the core of the component

```lua
    require("sttusline").setup {
        components = {
            {
                -- use mode component with override configs
                "mode",
                {
                    -- The table with any key that you want to override
                    -- Example you want to mode component update after 1 second
                    -- But the default config is not update after 1 second
                    -- So you can override the timing key, easy right?
                    timing = true,
                }
            },

            {
                -- use filename component with override configs
                "filename",
                -- this is the list of all keys that you can override
                -- you can override any key that a new component can have
                {
                    name = "component_name",
                    update_group = "group_name",
                    event = {}, -- The component will be update when the event is triggered
                    user_event = { "VeryLazy" },
                    -- timing = 200
                    timing = false,
                    lazy = true,
                    space ={}
                    configs = {},
                    padding = 1, -- { left = 1, right = 1 }
                    separator = { left = "", right = "" },
                    colors = {}, -- { fg = colors.black, bg = colors.white }
                    init = function(config, space) end,
                    update = function(configs, space)return "" end,
                    condition = function(configs, space)return true end,
                    on_highlight= function(configs, space) end,
                }
            },
        },
    }
```

### Add the empty space between components

To add the empty space between components, you need to add `%=` to `components` option in `setup` function

```lua
    require("sttusline").setup {
        components = {
            -- ... your components
            "%=", -- add the empty space
            -- ... your components
        },
    }
```

Example: If you do this, the statusline will become

```lua
    require("sttusline").setup {
        components = {
            "mode",
            "os-uname",
            "filename",
            "git-branch",
            "git-diff",
            "%=",
            "lsps-formatters",
            "%=",
            "indent",
            "encoding",
            "pos-cursor",
            "pos-cursor-progress",
        },
    }
```

![empty-component](./docs/readme/empty-component.png)

#### Create new component

```lua
    require("sttusline").setup {
        components = {
            -- ...
            {
                -- new component
                name = "component_name",
                update_group = "group_name",
                event = {}, -- The component will be update when the event is triggered
                user_event = { "VeryLazy" },
                timing = false, -- The component will be update every time interval
                lazy = true,
                space ={}
                configs = {},
                padding = 1, -- { left = 1, right = 1 }
                colors = {}, -- { fg = colors.black, bg = colors.white }
                separator = { left = "", right = "" },
                init = function(configs, space) end,
                update = function(configs, space)return "" end,
                condition = function(config, space)return true end,
                on_highlight= function(configs, space) end,
            }
        },
    }
```

 ## 🔧 Component Reference

Each component in `witch-line` is a table with powerful customization capabilities. Here's a complete reference of available fields:

| **Field**           | **Type**                                                                 | **Description**                                                                                         |
|---------------------|--------------------------------------------------------------------------|---------------------------------------------------------------------------------------------------------|
| `id`                | `string`, `number`                                                       | Unique identifier for the component.                                                                   |
| `inherit`           | `string`, `number`, `nil`                                                | Inherit fields from another component by ID.                                                           |
| `init`              | `fun(raw_self: Component)`                                               | Called once when the component is initialized.                                                         |
| `pre_update`        | `fun(self, ctx, static)`                                                 | Called before the update method.                                                                       |
| `update`            | `string`, `fun(self, ctx, static): string`, `nil`                        | Called to update the component. Should return the display string.                                      |
| `post_update`       | `fun(self, ctx, static)`                                                 | Called after the update, used for cleanup or state updates.                                            |
| `hide`              | `fun(self, ctx, static): boolean`                                        | Return `true` to hide the component dynamically.                                                       |
| `left`              | `string`, `fun(self, ctx, static): string`, `nil`                        | Left content of the component (static or dynamic).                                                     |
| `right`             | `string`, `fun(self, ctx, static): string`, `nil`                        | Right content of the component (static or dynamic).                                                    |
| `left_style`        | `table`, `fun(self, ctx, static): table`, `nil`                          | Style for the left section (foreground, background, bold, etc.).                                       |
| `right_style`       | `table`, `fun(self, ctx, static): table`, `nil`                          | Style for the right section.                                                                           |
| `padding`           | `integer`, `{left, right}`, `fun(...)`                                   | Padding around the component. Supports static or dynamic values.                                       |
| `style`             | `highlight`, `fun(self, ctx, static): highlight`                         | Main style applied to the whole component. Uses Neovim highlight options.                              |
| `static`            | `any`                                                                    | A static table available during all lifecycle methods.                                                 |
| `context`           | `fun(self, static): any`                                                 | Function to generate the `ctx` passed to `update` and lifecycle functions.                             |
| `timing`            | `boolean`, `integer`                                                     | If `true` or a number, the component updates on a time interval.                                       |
| `lazy`              | `boolean`                                                                | If `true`, component is lazily initialized.                                                            |
| `min_screen_width`  | `number`, `fun(self, ctx, static): number`, `nil`                        | Minimum screen width required to render the component.                                                 |
| `events`            | `string[]`                                                               | List of Neovim events that will trigger updates.                                                       |
| `user_events`       | `string[]`                                                               | List of user-defined events to trigger updates.                                                        |
| `ref`               | `Ref`                                                                    | A reference table for reusing logic and values across multiple components.                             |

---

### 🔗 Ref Table Subfields

The `ref` field supports the following subfields for deferred configuration:

- `events`
- `user_events`
- `timing`
- `style`
- `static`
- `context`
- `min_screen_width`
- `hide`

These allow reusing logic/configuration between components or lazily loading behavior.

---

### 📚 Example

```lua
{
  id = "mode",
  events = { "ModeChanged" },
  update = function()
    return vim.fn.mode()
  end,
  style = { fg = "#ffffff", bg = "#005f87", bold = true },
  padding = { left = 1, right = 1 },
  hide = function()
    return vim.bo.filetype == "NvimTree"
  end,
}.

---

### 📚 Example

```lua
{
  id = "mode",
  events = { "ModeChanged" },
  update = function()
    return vim.fn.mode()
  end,
  style = { fg = "#ffffff", bg = "#005f87", bold = true },
  padding = { left = 1, right = 1 },
  hide = function()
    return vim.bo.filetype == "NvimTree"
  end,
}

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
