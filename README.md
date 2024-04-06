<div align="center">
    <img width="450" alt="NeoCodeium" src="https://github.com/monkoose/neocodeium/assets/6261276/67e53b7d-0029-41c0-a903-af0cdf88a65d"/>
    <p>⚡ Free AI completion plugin powered by <a href="https://codeium.com">codeium</a> ⚡</p>
</div>

---
<details>

<summary>Motivation and differences with <a href="https://github.com/Exafunction/codeium.vim">codeium.vim</a></summary>

**Motivation**

The primary reason for creating NeoCodeium was to address the
issue of flickering suggestions in the official plugin. This flickering was
particularly annoying when dealing with multiline virtual text. Additionally,
I desired a feature that would allow accepted Codeium suggestions to be
repeatable using the `.`, because I use it as my main completion plugin and
only manually invoke nvim-cmp.

**Differences**

- Supports only neovim (written in lua).
- Flickering has been removed in most scenarios, resulting in a snappier experience.
- Completions on the current line can now be repeated using the `.` key.
- Performance improvements have been achieved through cache techniques.
- The suggestion count label is displayed in the number column, making it closer to the context.
- Default keymaps have been removed.
- Possibility to complete only word/line of the suggestion.
- By default, there is no debounce, allowing suggestions to appear while
  typing. If you don't like this behavior, set `debounce = true` in the setup.

</details>

> [!Warning]
> Currently, it only works on neovim's nightly build.

> [!Note]
> The plugin is beta quality. Has not been tested on Windows at all (the code for its support was adopted from [codeium.vim]).
>
> Please report any issues on the [GitHub repository](https://github.com/monkoose/neocodeium/issues).

### 📦 Installation

Here’s an example for 💤[lazy](https://github.com/folke/lazy.nvim) plugin manager. If you're using
a different plugin manager, please refer to its documentation for installation instructions.

```lua
-- add this to the file where you setup your other plugins:
{
  "monkoose/neocodeium",
  event = "VeryLazy",
  config = function()
    local neocodeium = require("neocodeium")
    neocodeium.setup()
    vim.keymap.set("i", "<A-f>", neocodeium.accept)
  end,
}

```

Now you can use `Alt-f` in insert mode to accept codeium suggestions.

**Note:** To obtain an API token, you’ll need to run `:NeoCodeium auth`.

### 🚀 Usage

#### 📒 API
In addition to the already mentioned `accept()` function, the plugin also provides a few other:

```lua
local neocodeium = require("neocodeium")

-- Accepts the suggestion
neocodeium.accept()

-- Accepts only part of the suggestion if the full suggestion doesn't make sense
neocodeium.accept_word()
neocodeium.accept_line()

-- Clears the current suggestion
neocodeium.clear()

-- Cycles through suggestions by `n` (1 by default) items. Use a negative value to cycle in reverse order
neocodeium.cycle(n)

-- Same as `cycle()`, but also tries to show suggestions if none is visible.
-- Mostly useful with the enabled `manual` option
neocodeium.cycle_or_complete(n)
```

#### ⌨️ Keymaps

NeoCodeium doesn’t enforce any keymaps, that means you’ll need to add them
yourself. While [codeium.vim] and
[copilot.vim](https://github.com/github/copilot.vim) set the `<Tab>` keymap as
the default key for accepting a suggestion, but `<Tab>` has some downsides to
consider (but nothing stops you from using it):
- **Risk of Interference:** There’s a high chance of it conflicting with other plugins (such as snippets, nvim-cmp, etc.).
- **Not Consistent:** It doesn’t work in the `:h command-line-window`.
- **Indentation Challenges:** It is harder to indent with the tab at the start of a line.

Suggested keymaps:

```lua
vim.keymap.set("i", "<A-f>", function()
    require("neocodeium").accept()
end)
vim.keymap.set("i", "<A-w>", function()
    require("neocodeium").accept_word()
end)
vim.keymap.set("i", "<A-a>", function()
    require("neocodeium").accept_line()
end)
vim.keymap.set("i", "<A-e>", function()
    require("neocodeium").cycle_or_complete()
end)
vim.keymap.set("i", "<A-r>", function()
    require("neocodeium").cycle_or_complete(-1)
end)
vim.keymap.set("i", "<A-c>", function()
    require("neocodeium").clear()
end)
```

#### 🔤 Commands

NeoCodeium provides `:NeoCodeium` user command, which has some useful actions:
- `:NeoCodeium auth` - authenticates the user and saves the API token.
- `:NeoCodeium disable` - disables NeoCodeium completion.
- `:NeoCodeium enable` - enables NeoCodeium completion.
- `:NeoCodeium toggle` - toggles NeoCodeium completion.
- `:NeoCodeium disable_buffer` - disables NeoCodeium completion in the current buffer.
- `:NeoCodeium enable_buffer` - enables NeoCodeium completion in the current buffer.
- `:NeoCodeium open_log` - opens split with the log output. More info in the [logging](#logging) section.
- `:NeoCodeium restart` - restarts Codeium server (useful when server stops responding for any reason).

You can also use such commands in your lua scripts by calling
`require("neocodeium.commands").<command_name>()`.

#### 🎨 Highlight groups

NeoCodeium offers a couple of highlight groups. Feel free to adjust them to
your preference and to match your choosen color scheme:
- `NeoCodeiumSuggestion` - virtual text color of the plugin suggestions (default: `#808080`)
- `NeoCodeiumLabel` - color of the label that indicates the number of suggestions (default: inverted DiagnosticInfo)

#### using with nvim-cmp

If you are using NeoCodeium with `manual = false` (it is default), it would be
useful to set nvim-cmp to manual completion then and clear NeoCodeium
suggestions on opening nvim-cmp popup menu. You can achieve this with following
code in the place where nvim-cmp is configured:

```lua
local cmp = require("cmp")
local neocodeium = require("neocodeium")
local commands = require("neocodeium.commands")

cmp.event:on("menu_opened", function()
    commands.disable()
    neocodeium.clear()
end)

cmp.event:on("menu_closed", function()
    commands.enable()
end)

cmp.setup({
    completion = {
        autocomplete = false,
    },
})
```

#### 📄 Logging

While runnging NeoCodeium logs some messages into a temporary file. It can be
viewed with `:NeoCodeium open_log` command. By default only errors and warnings
are logged.

You can set the logging level to one of `trace`, `debug`, `info`, `warn`, `error` by
exporting `NEOCODEIUM_LOG_LEVEL` environment variable.

Example:
```sh
NEOCODEIUM_LOG_LEVEL=info nvim
```

### ⚒️ Setup

NeoCodeium comes with the following default options:

```lua
-- NeoCodeium Configuration
require("neocodeium").setup({
  -- Enable NeoCodeium on startup
  enabled = true,
  -- Path to a custom Codeium server binary (you can download one from: https://github.com/Exafunction/codeium/releases)
  bin = nil,
  -- When set to `true`, autosuggestions are disabled. Use `require'neodecodeium'.cycle_or_complete()` to show suggestions manually
  manual = false,
  -- Information about the API server to use
  server = {
    -- API URL to use (for Enterprise mode)
    api_url = nil,
    -- Portal URL to use (for registering a user and downloading the binary)
    portal_url = nil,
  },
  -- Set to `false` to disable showing the number of suggestions label at the line column
  show_label = true,
  -- Set to `true` to enable suggestions debounce
  debounce = false,
  -- Maximum number of lines parsed from non-current loaded buffers
  -- Set to `0` to disable parsing non-current buffers (may lower suggestion quality)
  -- Set it to `-1` to parse all lines
  max_lines = 10000,
  -- Set to `true` to disable some not important messages, like "NeoCodeium: server started..."
  silent = false,
  -- Set to `false` to disable suggestions in buffers with specific filetypes
  filetypes = {
    help = false,
    gitcommit = false,
    gitrebase = false,
    ["."] = false,
  },
})
```

### 🚗 Roadmap

- [x] Add vimdoc help
- [x] Add command to open buffer with the log output
- [x] Add :checkhealth
- [ ] Add support for Codeium Chat
- [ ] Add new renderer with floating windows instead of virtual text

### 💐 Credits

- [codeium.vim] - The main source for understanding how to use Codeium.

### 🌟 License

MIT license

[codeium.vim]: https://github.com/Exafunction/codeium.vim
