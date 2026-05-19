local conf = require("neocodeium.utils.conf")
local log = require("neocodeium.log")

---@type string?
local windsurf_api_key = conf.load().api_key

local M = {}

---Checks if api key is set
---@return string|nil
function M.check()
   if not windsurf_api_key then
      log.warn("No API key found. Run `:NeoCodeium auth` to set it", { type = log.BOTH })
      return
   end

   return windsurf_api_key
end

---@return string|nil
function M.get()
   return windsurf_api_key
end

---@param value string
function M.set(value)
   windsurf_api_key = value
end

return M
