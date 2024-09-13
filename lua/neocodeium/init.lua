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
   local events = require("neocodeium.events")
   local event = events.event

   local function utf8_or_latin1()
      local encoding = vim.o.fileencoding
      return encoding == "" or encoding == "utf-8" or encoding == "latin1"
   end

   completer.allowed_encoding = utf8_or_latin1()
   local other_timer = assert(uv.new_timer())

   create_autocmd("BufEnter", {
      callback = function()
         completer.allowed_encoding = utf8_or_latin1()
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
      pattern = "fileencoding",
      callback = function()
         completer.allowed_encoding = utf8_or_latin1()
      end,
   })

   local function nu_or_rnu()
      return vim.wo.number or vim.wo.relativenumber
   end

   create_autocmd("ModeChanged", {
      pattern = "*:i*",
      once = true,
      callback = function()
         renderer.label.enabled = nu_or_rnu()
      end,
   })

   create_autocmd("WinEnter", {
      callback = function()
         renderer.label.enabled = nu_or_rnu()
      end,
   })

   create_autocmd("OptionSet", {
      pattern = "number,relativenumber",
      callback = function()
         renderer.label.enabled = nu_or_rnu()
      end,
   })

   create_autocmd("ModeChanged", {
      pattern = "i*:[^i]*",
      callback = function()
         completer:clear(true)
      end,
   })

   create_autocmd("BufLeave", {
      callback = function()
         completer:clear(true)
      end,
   })

   create_autocmd({ "CursorMovedI" }, {
      callback = function()
         completer:initiate()
      end,
   })

   create_autocmd("InsertEnter", {
      callback = function()
         if completer:enabled() then
            events.emit(event.status, completer.status, true)
         end
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
            once = true,
            callback = function()
               server:run()
            end,
         })
      end
   end

   set_highlights()
   enable_autocmds()

   -- User command

   ---Returns list of :NeoCodeium commands for completion
   ---@param arg_lead string
   ---@return table
   local function complete_commands(arg_lead)
      local result = {}
      for cmd in pairs(commands) do
         if vim.startswith(cmd, arg_lead) then
            table.insert(result, cmd)
         end
      end
      table.sort(result)

      return result
   end

   ---Calls a function mapped to the command
   ---@param cmd string
   local function run_command(cmd, bang)
      local func = commands[cmd]
      if func then
         func(bang)
      else
         local echo = require("neocodeium.utils.echo")
         echo.warn("command '" .. cmd .. "' not found")
      end
   end

   nvim_create_user_command("NeoCodeium", function(t)
      run_command(t.args, t.bang)
   end, {
      nargs = 1,
      bang = true,
      complete = complete_commands,
   })

   function M.get_status()
      local server_status
      if server.port then
         server_status = 0 -- ON
      elseif server.pid then
         server_status = 1 -- CONNECTING
      else
         server_status = 2 -- OFF
      end

      if not completer.allowed_encoding then
         return 5, server_status -- disabled by wrong encoding
      end

      return options.status(), server_status
   end
end

function M.accept()
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

function M.accept_word()
   require("neocodeium.completer"):accept_word()
end

function M.accept_line()
   require("neocodeium.completer"):accept_line()
end

---Returns true if a suggestion's virtual text is visible
---@return boolean
function M.visible()
   return require("neocodeium.completer"):valid()
end

function M.chat()
   return require("neocodeium.commands").chat()
end
-- }}}1

return M

-- vim: fdm=marker
