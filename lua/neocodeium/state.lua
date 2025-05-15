local STATUS = require("neocodeium.enums").STATUS

---@class State
---@field active boolean
---@field chat_enabled boolean
---@field status state.status
local State = {
   active = false,
   chat_enabled = false,
   status = STATUS.none,
   allowed_encoding = false,
}

return State
