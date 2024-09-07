local fn = vim.fn

local M = {}

---Returns true if file exists and is readable
---@param path filepath
---@return boolean
function M.readable(path)
   return fn.filereadable(path) == 1
end

---Returns true if command/file exists and executable
---@param cmd string
---@return boolean
function M.executable(cmd)
   return fn.executable(cmd) == 1
end

---Reads file content into string, on failure returns nil
---@param path filepath
---@return string?
function M.read(path)
   local f = io.open(path, "rb")
   if f then
      local content = f:read("*a")
      f:close()
      return content
   end
end

---Returns current script path
---@return filepath
local function script_path()
   return debug.getinfo(2, "S").source:sub(2)
end

---Returns plugin's root directory
---@return filepath
function M.root_dir()
   return fn.fnamemodify(script_path(), ":h:h:h:h")
end

return M
