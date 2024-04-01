local conf = require("neocodeium.utils.conf")
local echo = require("neocodeium.utils.echo")

---@type string?
local api_key = conf.load(conf.data_dir()).api_key

local M = {}

---Checks if api key is set
function M.check()
  if not api_key then
    echo.warn("No API key found. Run `:NeoCodeium auth` to set it")
  end
end

---@return string?
function M.get()
  return api_key
end

---@param value string
function M.set(value)
  api_key = value
end

return M
