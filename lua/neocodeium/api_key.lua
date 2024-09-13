local conf = require("neocodeium.utils.conf")
local echo = require("neocodeium.utils.echo")

---@type string?
local api_key = conf.load().api_key

local M = {}

---Checks if api key is set
---@return string|nil
function M.check()
   if not api_key then
      echo.warn("No API key found. Run `:NeoCodeium auth` to set it")
      return
   end

   return api_key
end

---@return string|nil
function M.get()
   return api_key
end

---@param value string
function M.set(value)
   api_key = value
end

return M
