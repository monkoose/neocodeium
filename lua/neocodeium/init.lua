-- Imports ------------------------------------------------- {{{1

local uv = vim.uv
local nvim_get_hl = vim.api.nvim_get_hl
local nvim_set_hl = vim.api.nvim_set_hl
local nvim_create_autocmd = vim.api.nvim_create_autocmd
local nvim_get_current_buf = vim.api.nvim_get_current_buf
local nvim_create_user_command = vim.api.nvim_create_user_command

-- Auxiliary functions ------------------------------------- {{{1

local augroup = vim.api.nvim_create_augroup("neocodeium", {})

---@param events string|table
---@param opts table
local function create_autocmd(events, opts)
  nvim_create_autocmd(
    events,
    vim.tbl_extend("keep", opts, {
      group = augroup,
    })
  )
end

local function set_highlights()
  nvim_set_hl(0, "NeoCodeiumSuggestion", {
    fg = "#808080",
    ctermfg = 244,
    default = true,
  })

  local label_fg = nvim_get_hl(0, { name = "DiagnosticInfo" }).fg
  nvim_set_hl(0, "NeoCodeiumLabel", {
    fg = label_fg or "#808080",
    bold = true,
    ctermfg = 244,
    reverse = true,
    default = true,
  })
end

-- Autocmds ------------------------------------------------ {{{1

local function enable_autocmds()
  local completer = require("neocodeium.completer")
  local renderer = require("neocodeium.renderer")
  local doc = require("neocodeium.doc")

  -- TODO: find a proper name
  local function allow_encoding()
    local encoding = vim.o.encoding
    return encoding == "utf-8" or encoding == "latin1"
  end

  completer.allowed_encoding = allow_encoding()
  local other_timer = assert(uv.new_timer())

  create_autocmd("BufEnter", {
    callback = function()
      completer.allowed_encoding = allow_encoding()
      other_timer:stop()
      other_timer:start(
        1,
        0,
        vim.schedule_wrap(function()
          completer.other_docs = doc.get_all_loaded(nvim_get_current_buf())
        end)
      )
    end,
  })

  create_autocmd("OptionSet", {
    pattern = "encoding",
    callback = function()
      completer.allowed_encoding = allow_encoding()
    end,
  })

  local function allow_label()
    return vim.wo.number or vim.wo.relativenumber
  end

  create_autocmd("ModeChanged", {
    pattern = "*:i*",
    once = true,
    callback = function()
      renderer.label.enabled = allow_label()
    end,
  })

  create_autocmd("WinEnter", {
    callback = function()
      renderer.label.enabled = allow_label()
    end,
  })

  create_autocmd("OptionSet", {
    pattern = "number,relativenumber",
    callback = function()
      renderer.label.enabled = allow_label()
    end,
  })

  create_autocmd("ModeChanged", {
    pattern = "i*:*",
    callback = function()
      completer:clear(true)
    end,
  })

  create_autocmd("BufLeave", {
    callback = function()
      completer:clear(true)
    end,
  })

  create_autocmd({ "CursorMovedI", "CompleteChanged" }, {
    callback = function()
      completer:initiate()
    end,
  })

  create_autocmd("ModeChanged", {
    pattern = "*:i*",
    callback = function()
      completer:initiate()
    end,
  })

  create_autocmd({ "ColorScheme" }, { callback = set_highlights })

  create_autocmd("VimLeavePre", {
    callback = function()
      local Server = require("neocodeium.server")
      Server:stop()
    end,
  })
end

-- API ----------------------------------------------------- {{{1

local M = {}

function M.setup(opts)
  require("neocodeium.options").setup(opts)

  local options = require("neocodeium.options").options
  local commands = require("neocodeium.commands")
  local server = require("neocodeium.server")
  local completer = require("neocodeium.completer")

  if options.enabled then
    if vim.v.vim_did_enter == 1 then
      server:run()
    else
      nvim_create_autocmd("VimEnter", {
        callback = function()
          server:run()
        end,
      })
    end
  end

  set_highlights()
  enable_autocmds()

  -- User command
  nvim_create_user_command("NeoCodeium", function(t)
    commands.run(t.args)
  end, {
    nargs = 1,
    complete = commands.complete,
  })

  function M.get_status()
    if completer:enabled() then
      return " ON"
    else
      return "OFF"
    end
  end
end

function M.complete()
  require("neocodeium.completer"):accept()
end

function M.clear()
  require("neocodeium.completer"):clear(true)
end

function M.cycle(n)
  require("neocodeium.completer"):cycle(n)
end

function M.cycle_or_complete(n)
  require("neocodeium.completer"):cycle_or_complete(n)
end

function M.complete_word()
  require("neocodeium.completer"):complete_word()
end

function M.complete_line()
  require("neocodeium.completer"):complete_line()
end
-- }}}1

return M

-- vim: fdm=marker
