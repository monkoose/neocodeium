<div align="center">
    <img width="450" alt="NeoCodeium" src="https://github.com/user-attachments/assets/f31d5035-ca1c-43f1-b309-fb523ecdfe48"/>
    <p>⚡ Free AI completion plugin powered by <a href="https://codeium.com">codeium</a> ⚡</p>
</div>

---

NeoCodeium is a plugin that provides AI completion powered by [Codeium]. The
primary reason for creating NeoCodeium was to address the issue of flickering
suggestions in the official plugin which was particularly annoying when dealing
with multi-line virtual text. Additionally, I desired a feature that would
allow accepting Codeium suggestions to be repeatable using the `.` command
because I use it as my main completion plugin and only manually invoke
nvim-cmp.

<details>
<summary>Differences with <a href="https://github.com/Exafunction/codeium.vim">codeium.vim</a></summary>

- Supports only Neovim (written in Lua)
- Flickering has been removed in most scenarios, resulting in a snappier experience
- Completions on the current line can now be repeated using the `.` key
- Performance improvements have been achieved through cache techniques
- The suggestion count label is displayed in the number column, making it closer to the context
- Default keymaps have been removed
- ~~Possibility to complete only word/line of the suggestion~~ (codeium.vim added this feature in [9fa0dee](https://github.com/Exafunction/codeium.vim/commit/9fa0dee67051d8e5d334f7f607e6bab1d6a46d1a))
- No debounce by default, allowing suggestions to appear while typing (this behavior can be disabled with `debounce = true` in the setup)

</details>

> [!Warning]
> While using this plugin, your code is constantly being sent to
> Codeium servers by their own language server in order to evaluate and return
> completions. Before using make sure you have read and accept the [Codeium
> Privacy Policy](https://codeium.com/privacy-policy). NeoCodeium has the
> ability to disable the server globally or for individual buffers. This plugin
> does not send any data to the server from disabled buffers, but the Codeium
> server is still running behind the scenes and we cannot guarantee that it
> doesn't send information while running.

### ⚡️ Requirements

- Neovim >= **0.10.0**

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
On Windows WSL `wslview` `(sudo apt install wslu)` should be installed to properly open the browser.

### 🚀 Usage

#### 📒 API

In addition to the already mentioned `accept()` function, the plugin also provides a few others:

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

-- Same as `cycle()`, but also tries to show a suggestion if none is visible.
-- Mostly useful with the enabled `manual` option
neocodeium.cycle_or_complete(n)

-- Checks if a suggestion's virtual text is visible or not (useful for some complex mappings)
neocodeium.visible()
```

#### 🪄 Tips

<details>
<summary><b>Using alongside nvim-cmp</b></summary>

If you are using NeoCodeium with `manual = false` (the default), it is
recommended to set nvim-cmp to manual completion and clear NeoCodeium
suggestions on opening of the nvim-cmp pop-up menu. You can achieve this with
following code in the place where nvim-cmp is configured:

```lua
local cmp = require("cmp")
local neocodeium = require("neocodeium")
local commands = require("neocodeium.commands")

cmp.event:on("menu_opened", function()
    neocodeium.clear()
end)

neocodeium.setup({
    filter = function()
        return not cmp.visible()
    end,
})

cmp.setup({
    completion = {
        autocomplete = false,
    },
})
```

If you want to use autocompletion with nvim-cmp, then it is recommended to use
NeoCodeium with `manual = true`, add a binding for triggering NeoCodeium
completion, and make sure to close the nvim-cmp window when completions are
rendered. You can achieve this with the following code where you setup
NeoCodeium:

```lua
local neocodeium = require("neocodeium")

neocodeium.setup({
  manual = true, -- recommended to not conflict with nvim-cmp
})

-- create an autocommand which closes cmp when ai completions are displayed
vim.api.nvim_create_autocmd("User", {
  pattern = "NeoCodeiumCompletionDisplayed",
  callback = function() require("cmp").abort() end
})

-- set up some sort of keymap to cycle and complete to trigger completion
vim.keymap.set("i", "<A-e>", function() neocodeium.cycle_or_complete() end)
-- make sure to have a mapping to accept a completion
vim.keymap.set("i", "<A-f>", function() neocodeium.accept() end)
```
</details>

<details>
<summary><b>Disable in Telescope prompt and DAP REPL</b></summary>

```lua
require("neocodeium").setup({
    filetypes = {
        ...
        TelescopePrompt = false,
        ["dap-repl"] = false,
    },
})
```
</details>

<details>
<summary><b>Enable NeoCodeium only in specified filetypes</b></summary>

```lua
local filetypes = { 'lua', 'python' }
neocodeium.setup({
  -- function accepts one argument `bufnr`
  filter = function(bufnr)
    if vim.tbl_contains(filetypes, vim.api.nvim_get_option_value('filetype',  { buf = bufnr})) then
        return true
    end
    return false
  end
})
```
</details>

#### ⌨️ Keymaps

NeoCodeium doesn’t provide any keymaps, which means you’ll need to add them
yourself. While [codeium.vim] and
[copilot.vim](https://github.com/github/copilot.vim) set the `<Tab>` key as the
default key for accepting a suggestion, we recommend avoiding it as it has some
downsides to consider (although nothing is stopping you from using it):
- **Risk of Interference:** There’s a high chance of it conflicting with other
  plugins (such as snippets, nvim-cmp, etc.).
- **Not Consistent:** It doesn’t work in the `:h command-line-window`.
- **Indentation Challenges:** It is harder to indent with the tab at the start
  of a line.

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
- `:NeoCodeium[!] disable` - disables completions. With the bang also stops the codeium server.
- `:NeoCodeium enable` - enables NeoCodeium completion.
- `:NeoCodeium[!] toggle` - toggles NeoCodeium completion. Convey the bang to disable command.
- `:NeoCodeium disable_buffer` - disables NeoCodeium completion in the current buffer.
- `:NeoCodeium enable_buffer` - enables NeoCodeium completion in the current buffer.
- `:NeoCodeium toggle_buffer` - toggles NeoCodeium completion in the current buffer.
- `:NeoCodeium open_log` - opens new tab with the log output. More information is in the [logging](#logging) section.
- `:NeoCodeium chat` - opens browser with the Codeium Chat.
- `:NeoCodeium restart` - restarts Codeium server (useful if the server stops responding for any reason).

You can also use the same commands in your Lua scripts by calling:

```lua
require("neocodeium.commands").<command_name>()`
-- Examples
-- disable completions
require("neocodeium.commands").disable()
-- disable completions and stop the server
require("neocodeium.commands").disable(true)
```

#### 📆 User Events

NeoCodeium triggers several user events which can be used to trigger code. These can be used to optimize when statusline elements are updated, creating mappings only when the server is available, or modifying completion engine settings when AI completion is started or displaying hints.

- `NeoCodeiumServerConnecting` - triggers when a connection to the Codeium server is starting
- `NeoCodeiumServerConnected` - triggers when a successful connection to the Codeium server is made
- `NeoCodeiumServerStopped` - triggers when the Codeium server is stopped
- `NeoCodeiumEnabled` - triggers when the NeoCodeium plugin is enabled globally
- `NeoCodeiumDisabled` - triggers when the NeoCodeium plugin is disabled globally
- `NeoCodeiumBufEnabled` - triggers when the NeoCodeium plugin is enabled for a buffer
- `NeoCodeiumBufDisabled` - triggers when the NeoCodeium plugin is disabled for a buffer
- `NeoCodeiumCompletionDisplayed` - triggers when NeoCodeium successfully displays a completion item as virtual text
- `NeoCodeiumCompletionCleared` - triggers when NeoCodeium clears virtual text and completions

#### 🚃 Statusline

`require("neocodeium").get_status()` can be used to get the some useful information about the current state.
The best use case for this output is to implement custom statusline component.
This function returns two numbers:

1. Status of the plugin

        0 - Enabled
        1 - Globally disabled with `:NeoCodeium disable`, `:NeoCodeium toggle` or with `options.enabled = false`
        2 - Buffer is disabled with `:NeoCodeium disable_buffer`
        3 - Buffer is disableld when it's filetype is matching `options.filetypes = { some_filetyps = false }`
        4 - Buffer is disabled when `options.enalbed` is a function and it returns `false`
        5 - Buffer has wrong encoding (codeium can accept only UTF-8 and LATIN-1 encodings)

2. Server status

        0 - Server is on (running)
        1 - Connecting to the server (not working status)
        2 - Server is off (stopped)

To use output from `get_status()` for in-time update it is required to invoke this function
from [events](https://github.com/monkoose/neocodeium?tab=readme-ov-file#-user-events)

**Statusline Examples**

<details>
<summary>Without statusline plugins</summary>

```lua
-- function to process get_status() and set buffer variable to that data.
local neocodeium = require("neocodeium")
local function get_neocodeium_status(ev)
    local status, server_status = neocodeium.get_status()
    -- process this data, convert it to custom string/icon etc and set buffer variable
    if status == 0 then
        vim.api.nvim_buf_set_var(ev.buf, "neocodeium_status", "OK")
    else
        vim.api.nvim_buf_set_var(ev.buf, "neocodeium_status", "OFF")
    end
    vim.cmd.redrawstatus()
end

-- Then only some of event fired we invoked this function
vim.api.nvim_create_autocmd("User", {
    -- group = ..., -- set some augroup here
    pattern = {
        "NeoCodeiumServer*",
        "NeoCodeium*Enabled",
        "NeoCodeium*Disabled",
    }
    callback = get_neocodeium_status,
})

-- add neocodeium_status to your statusline
vim.opt.statusline:append("%{get(b:, 'neocodeium_status', '')%}")
```
</details>

<details>
<summary>Heirline.nvim</summary>

```lua
local NeoCodeium = {
  static = {
    symbols = {
      status = {
        [0] = "󰚩 ", -- Enabled
        [1] = "󱚧 ", -- Disabled Globally
        [2] = "󱙻 ", -- Disabled for Buffer
        [3] = "󱙺 ", -- Disabled for Buffer filetype
        [4] = "󱙺 ", -- Disabled for Buffer with enabled function
        [5] = "󱚠 ", -- Disabled for Buffer encoding
      },
      server_status = {
        [0] = "󰣺 ", -- Connected
        [1] = "󰣻 ", -- Connecting
        [2] = "󰣽 ", -- Disconnected
      },
    },
  },
  update = {
    "User",
    pattern = { "NeoCodeiumServer*", "NeoCodeium*{En,Dis}abled" },
    callback = function() vim.cmd.redrawstatus() end,
  },
  provider = function(self)
    local symbols = self.symbols
    local status, server_status = require("neocodium").get_status()
    return symbols.status[status] .. symbols.server_status[server_status]
  end,
  hl = { fg = "yellow" },
}
```
</details>

#### 🎨 Highlight groups

NeoCodeium offers a couple of highlight groups. Feel free to adjust them to
your preference and to match your chosen color scheme:
- `NeoCodeiumSuggestion` - virtual text color of the plugin suggestions (default: `#808080`)
- `NeoCodeiumLabel` - color of the label that indicates the number of suggestions (default: inverted DiagnosticInfo)

#### 📄 Logging

While running, NeoCodeium logs some messages into a temporary file. It can be
viewed with the `:NeoCodeium open_log` command. By default only errors and
warnings are logged.

You can set the logging level to one of `trace`, `debug`, `info`, `warn` or
`error` by exporting the `NEOCODEIUM_LOG_LEVEL` environment variable.

Example:
```sh
NEOCODEIUM_LOG_LEVEL=info nvim
```

### ⚒️ Setup

NeoCodeium comes with the following default options:

```lua
-- NeoCodeium Configuration
require("neocodeium").setup({
  -- If `false`, then would not start codeium server (disabled state)
  -- You can manually enable it at runtime with `:NeoCodeium enable`
  enabled = true,
  -- Path to a custom Codeium server binary (you can download one from:
  -- https://github.com/Exafunction/codeium/releases)
  bin = nil,
  -- When set to `true`, autosuggestions are disabled.
  -- Use `require'neodecodeium'.cycle_or_complete()` to show suggestions manually
  manual = false,
  -- Information about the API server to use
  server = {
    -- API URL to use (for Enterprise mode)
    api_url = nil,
    -- Portal URL to use (for registering a user and downloading the binary)
    portal_url = nil,
  },
  -- Set to `false` to disable showing the number of suggestions label in the line column
  show_label = true,
  -- Set to `true` to enable suggestions debounce
  debounce = false,
  -- Maximum number of lines parsed from loaded buffers (current buffer always fully parsed)
  -- Set to `0` to disable parsing non-current buffers (may lower suggestion quality)
  -- Set it to `-1` to parse all lines
  max_lines = 10000,
  -- Set to `true` to disable some non-important messages, like "NeoCodeium: server started..."
  silent = false,
  -- Set to a function that returns `true` if a buffer should be enabled
  -- and `false` if the buffer should be disabled
  -- You can still enable disabled by this option buffer with `:NeoCodeium enable_buffer`
  filter = function(bufnr) return true end,
  -- Set to `false` to disable suggestions in buffers with specific filetypes
  -- You can still enable disabled by this option buffer with `:NeoCodeium enable_buffer`
  filetypes = {
    help = false,
    gitcommit = false,
    gitrebase = false,
    ["."] = false,
  },
  -- List of directories and files to detect workspace root directory for Codeium chat
  root_dir = { ".bzr", ".git", ".hg", ".svn", "_FOSSIL_", "package.json" }
})
```

#### 💬 Chat

You can chat with AI in the browser with the `:NeoCodeium chat` command. The
first time you open it, it requires the server to restart with some
chat-specific flags, so be patient (this usually doesn't take more than a few
seconds). After that, it should open a chat window in the browser with the
context of the current buffer. Here, you can ask some specific questions about
your code base. When you switch buffers, this context should be updated
automatically (it takes some time). You can see current chat context in the
left bottom corner.

### 🚗 Roadmap

- [x] Add vimdoc help
- [x] Add the command to open buffer with the log output
- [x] Add :checkhealth
- [x] Add support for Codeium Chat (in browser only)
- [ ] Completely decouple renderer from completer.
Add an custom renderer setup option.
Renderer is already pretty much decoupled, but still transforms data it receives and
so completer receives from it more data than required. Its API should
consist of: display(), update() and clear() methods and do not pass any data to
the completer. Not sure if someone will use it, but there are always some enthusiasts and hackers.
With this feature implementing some custom renderer (like for any extendable completion engine) would be easy.
Provide an example of custom renderer with built-in completion (omnifunc).

### 💐 Credits

- [codeium.vim] - The main source for understanding how to use Codeium.

### 🌟 License

MIT license

[codeium.vim]: https://github.com/Exafunction/codeium.vim
[Codeium]: https://codeium.com
