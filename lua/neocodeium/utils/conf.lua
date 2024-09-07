local stdio = require("neocodeium.utils.stdio")
local M = {}

---Returns codeium config directory
---@return filepath
function M.dir()
   local config_dir = vim.env.XDG_CONFIG_HOME or vim.env.HOME .. "/.config"
   return config_dir .. "/codeium"
end

---Returns codeium data directory
---@return filepath
function M.data_dir()
   local data_dir = vim.env.XDG_DATA_HOME
   if data_dir then
      return data_dir .. "/codeium"
   else
      return vim.env.HOME .. "/.codeium"
   end
end

---Returns content of config.json in a `dir` directory as decoded json.
---Returns empty table if config.json does not exist or cannot be decoded.
---@param dir filepath
---@return json_tbl
function M.load(dir)
   local json_str = stdio.read(dir .. "/config.json")
   local ok, config = pcall(vim.json.decode, json_str)
   return ok and config or {}
end

return M
