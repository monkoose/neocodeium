local options = require("neocodeium.options").options
local utils = require("neocodeium.utils")
local REQUEST_STATUS = require("neocodeium.enums").REQUEST_STATUS

local uv = vim.uv

local nvim_get_option_value = vim.api.nvim_get_option_value

---@class inline
---@field id? integer
---@field text? string
---@field prefix? string

---@class block
---@field text? string
---@field id? integer

---@class State
---@field active boolean
---@field chat_enabled boolean
---@field request_status request_status
---@field request_data request_data
---@field accept_request_data accept_request_data
---@field completion_request_data completion_request_data
---@field pos pos
---@field data compl.data
---@field inline inline[]
---@field block block
---@field debounce_timer uv.uv_timer_t
local State = {
   active = false,
   chat_enabled = false,
   request_status = REQUEST_STATUS.none,
   request_data = {}, ---@diagnostic disable-line: missing-fields
   accept_request_data = {}, ---@diagnostic disable-line: missing-fields
   completion_request_data = {}, ---@diagnostic disable-line: missing-fields
   pos = { 0, 0 },
   data = {},
   inline = {},
   block = {},
   debounce_timer = assert(uv.new_timer()),
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
      return 1 -- globally disabled
      -- Buffer variable should enable neocodeium even if it is disabled
      -- by 'options.filetypes' or 'options.filter()' or in special buftypes
   elseif vim.b[bufnr].neocodeium_enabled then
      return 0 -- enabled
   elseif vim.b[bufnr].neocodeium_enabled == false then
      return 2 -- locally disabled
   elseif not vim.b[bufnr].neocodeium_allowed_encoding then
      return 5 -- disabled by wrong encoding
   elseif options.disable_in_special_buftypes and not utils.is_normal_buf(bufnr) then
      return 6 -- disabled in special buftypes
      -- The same as vim.b[bunfr].neocodeium_enabled == nil and ...
   elseif options.filetypes[nvim_get_option_value("filetype", { buf = bufnr })] == false then
      return 3 -- disabled by 'options.filetypes'
   elseif options.filter and options.filter(bufnr) == false then
      return 4 -- disabled by 'options.filter()'
   else
      return 0 -- enabled
   end
end

return State
