-- Imports ------------------------------------------------- {{{1

local uv = vim.uv
local fn = vim.fn

local nvim_get_hl = vim.api.nvim_get_hl
local nvim_set_hl = vim.api.nvim_set_hl
local nvim_create_autocmd = vim.api.nvim_create_autocmd
local nvim_get_current_buf = vim.api.nvim_get_current_buf
local nvim_create_user_command = vim.api.nvim_create_user_command
local nvim_get_autocmds = vim.api.nvim_get_autocmds

-- Auxiliary functions ------------------------------------- {{{1

local augroup = vim.api.nvim_create_augroup("neocodeium", {})
local other_docs_timer = assert(uv.new_timer())
local pummenu_timer = assert(uv.new_timer())

---@param events string|table
---@param opts table
---@return integer
local function create_autocmd(events, opts)
   return nvim_create_autocmd(
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

   nvim_set_hl(0, "NeoCodeiumSingleLineLabel", {
      fg = "#808080",
      ctermfg = 244,
      bold = true,
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
   local state = require("neocodeium.state")
   local utils = require("neocodeium.utils")
   local options = require("neocodeium.options").options
   local events = require("neocodeium.events")
   local STATUS = require("neocodeium.enums").STATUS

   local function set_allowed_encoding()
      local buffers = options.disable_in_special_buftypes and utils.normal_bufs()
         or utils.all_bufs()
      for b in buffers do
         vim.b[b].neocodeium_allowed_encoding = utils.is_utf8_or_latin1(b)
      end
   end

   if vim.v.vim_did_enter == 1 then
      set_allowed_encoding()
      set_highlights()
   else
      create_autocmd("VimEnter", {
         once = true,
         callback = function()
            set_allowed_encoding()
            set_highlights()
         end,
      })
   end

   create_autocmd({ "BufAdd" }, {
      callback = function(ev)
         vim.b[ev.buf].neocodeium_allowed_encoding = utils.is_utf8_or_latin1(ev.buf)
      end,
   })

   create_autocmd("BufEnter", {
      callback = function()
         state:update_editor_options()
         other_docs_timer:stop()
         other_docs_timer:start(
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
      callback = function(ev)
         vim.b[ev.buf].neocodeium_allowed_encoding = utils.is_utf8_or_latin1(ev.buf)
      end,
   })

   local function nu_or_rnu()
      return vim.wo.number or vim.wo.relativenumber
   end

   if options.show_label then
      local mode_changed_id
      local function insert_enter_once()
         mode_changed_id = create_autocmd("ModeChanged", {
            pattern = "*:i*",
            once = true,
            callback = function()
               renderer.label.enabled = nu_or_rnu()
            end,
         })
      end

      insert_enter_once()

      create_autocmd({ "WinEnter", "BufEnter" }, {
         callback = function()
            if not nvim_get_autocmds({})[1] then
               insert_enter_once()
            end
         end,
      })

      create_autocmd("OptionSet", {
         pattern = "number,relativenumber",
         callback = function()
            renderer.label.enabled = nu_or_rnu()
         end,
      })
   end

   create_autocmd("OptionSet", {
      pattern = "shiftwidth,expandtab",
      callback = function(ev)
         if ev.buf == nvim_get_current_buf() then
            state:update_editor_options()
         end
      end,
   })

   create_autocmd("ModeChanged", {
      pattern = "i*:[^i]*",
      callback = function()
         completer:clear(true)
         state.active = false
         events.emit("NeoCodeiumLabelUpdated", "   ", true)
      end,
   })

   create_autocmd("BufLeave", {
      callback = function()
         completer:clear(true)
      end,
   })

   local function is_noselect()
      local completeopt = vim.o.completeopt
      return completeopt:find("noselect") and -1 or 0
   end

   local default_selected_compl = is_noselect()
   local selected_compl = default_selected_compl

   create_autocmd("OptionSet", {
      pattern = "completeopt",
      callback = function()
         default_selected_compl = is_noselect()
      end,
   })

   -- Make neocodeium less disruptive when using pummenu
   create_autocmd("TextChangedP", {
      callback = function()
         local cur_selected = fn.complete_info({ "selected" }).selected
         if selected_compl == cur_selected then
            completer:initiate()
         else
            selected_compl = cur_selected
            completer:clear(true)
            renderer:display_label()
            pummenu_timer:stop()
            pummenu_timer:start(
               400,
               0,
               vim.schedule_wrap(function()
                  if fn.pumvisible() == 1 then
                     completer:initiate()
                  end
               end)
            )
         end
      end,
   })

   create_autocmd("CursorMovedI", {
      callback = function()
         completer:initiate()
         if fn.pumvisible() == 0 then
            selected_compl = default_selected_compl
         end
      end,
   })

   create_autocmd("InsertEnter", {
      callback = function()
         -- do not run in Replace mode
         if vim.v.insertmode ~= "i" then
            return
         end

         if state:get_status() == STATUS.enabled then
            state.active = true
         else
            state.active = false
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

   create_autocmd("BufUnload", {
      desc = "Clear documents cache on buffer unload",
      callback = function(args)
         doc.cached_data[args.buf] = nil
      end,
   })

   create_autocmd("DirChanged", {
      desc = "Update project's root directory",
      callback = function()
         state:update_project_root()
      end,
   })

   create_autocmd("WinEnter", {
      desc = "Update project's root directory",
      callback = function()
         state:update_project_root()
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
   local state = require("neocodeium.state")

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
         local log = require("neocodeium.log")
         log.warn("Command '" .. cmd .. "' not found", { type = log.ECHO })
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

      return state:get_status(), server_status
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
   return require("neocodeium.state"):valid()
end

function M.chat()
   return require("neocodeium.commands").chat()
end
-- }}}1

return M

-- vim: fdm=marker
