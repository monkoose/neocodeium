local stdio = require("neocodeium.utils.stdio")

local dir = vim.env.HOME .. "/.codeium"
local conf = { dir = dir, file = dir .. "/config.json" }

---Returns content of the json file in a `dir` directory as decoded json.
---Returns empty table if config.json does not exist or cannot be decoded.
---@param config_path? filepath
---@return table
function conf.load(config_path)
   config_path = config_path or conf.file
   local json_str = stdio.read(config_path)
   local ok, config = pcall(vim.json.decode, json_str)
   return ok and config or {}
end

return conf
