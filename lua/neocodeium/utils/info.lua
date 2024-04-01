local echo = require("neocodeium.utils.echo")
local stdio = require("neocodeium.utils.stdio")

local json = vim.json

local M = {}

---Returns server's binary information
---@return binary_info
function M.binary()
  local info_file = stdio.root_dir() .. "/binary.json"
  local enc_info = stdio.read(info_file)
  if not enc_info then
    echo.error("failed to read server info file: " .. info_file)
    return {}
  end

  local ok, info = pcall(json.decode, enc_info)
  if not ok then
    echo.error("failed to decode server info file\n" .. info)
    return {}
  end

  return info
end

return M
