local REQUEST_STATUS = require("neocodeium.enums").REQUEST_STATUS

local uv = vim.uv

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
---@field request_status state.request_status
---@field allowed_encoding boolean
---@field pos pos
---@field data compl.data
---@field inline inline[]
---@field block block
---@field debounce_timer uv.uv_timer_t
local State = {
   active = false,
   chat_enabled = false,
   request_status = REQUEST_STATUS.none,
   allowed_encoding = false,
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

return State
