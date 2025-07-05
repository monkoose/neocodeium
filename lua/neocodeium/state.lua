local options = require("neocodeium.options").options
local utils = require("neocodeium.utils")
local stdio = require("neocodeium.utils.stdio")
local STATUS = require("neocodeium.enums").STATUS

local uv = vim.uv
local fn = vim.fn

local nvim_get_option_value = vim.api.nvim_get_option_value

---@class inline
---@field id? integer
---@field text? string
---@field prefix? string

---@class block
---@field text? string
---@field visible? boolean
---@field id? integer

---@class State
---@field active boolean
---@field chat_enabled boolean
---@field request_data request_data
---@field accept_request_data accept_request_data
---@field completion_request_data state.completion_request_data
---@field pending boolean
---@field matching boolean
---@field pos pos
---@field data compl.data
---@field inline inline[]
---@field block block
---@field debounce_timer uv.uv_timer_t
---@field curline_text string
---@field project_root filepath
---@field project_root_uri url
---@field cwd filepath
local State = {
   active = false,
   chat_enabled = false,
   request_data = {}, ---@diagnostic disable-line: missing-fields
   accept_request_data = {}, ---@diagnostic disable-line: missing-fields
   ---@diagnostic disable-next-line: missing-fields
   completion_request_data = {
      editor_options = {
         tab_size = fn.shiftwidth(),
         insert_spaces = vim.bo.expandtab,
      },
   },
   pending = false,
   matching = false,
   pos = { 0, 0 },
   data = {},
   inline = {},
   block = {},
   debounce_timer = assert(uv.new_timer()),
   curline_text = "",
   project_root = stdio.get_project_root(),
   project_root_uri = stdio.to_uri(stdio.get_project_root()),
   cwd = fn.getcwd(),
}

---Returns `true` if completion data is present and valid.
---@return boolean
function State:valid()
   return self.data.items ~= nil and self.data.index ~= nil
end

function State:stop_debounce_timer()
   if self.debounce_timer:is_active() then
      self.debounce_timer:stop()
   end
end

---@param bufnr? bufnr
---@return integer
function State:get_status(bufnr)
   bufnr = bufnr or 0
   if not options.enabled then
      return STATUS.disabled
      -- Buffer variable should enable neocodeium even if it is disabled
      -- by 'options.filetypes' or 'options.filter()' or in special buftypes
   elseif vim.b[bufnr].neocodeium_enabled then
      return STATUS.enabled
   elseif vim.b[bufnr].neocodeium_enabled == false then
      return STATUS.buf_disabled
   elseif not vim.b[bufnr].neocodeium_allowed_encoding then
      return STATUS.encoding_disabled
   elseif options.disable_in_special_buftypes and not utils.is_normal_buf(bufnr) then
      return STATUS.special_buf_disabled
      -- The same as vim.b[bunfr].neocodeium_enabled == nil and ...
   elseif options.filetypes[nvim_get_option_value("filetype", { buf = bufnr })] == false then
      return STATUS.filetype_disabled
   elseif options.filter and options.filter(bufnr) == false then
      return STATUS.filter_disabled
   else
      return STATUS.enabled
   end
end

function State:update_editor_options()
   self.completion_request_data.editor_options.tab_size = fn.shiftwidth()
   self.completion_request_data.editor_options.insert_spaces = vim.bo.expandtab
end

function State:update_project_root()
   local cwd = fn.getcwd()
   if self.cwd ~= cwd then
      self.cwd = cwd
      local root = stdio.get_project_root()
      self.project_root = root
      self.project_root_uri = stdio.to_uri(root)
   end
end

return State
