local options = require("neocodeium.options").options
local utils = require("neocodeium.utils")

local fn = vim.fn
local fs = vim.fs
local uv = vim.uv

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
---@return string|nil
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

---@return string|nil
function M.get_project_root()
   return fs.root(0, options.root_dir) or uv.cwd()
end

local on_windows = utils.get_system_info().os == "windows"
---@param path? string
---@return string|nil
function M.to_uri(path)
   if not path then
      return
   end

   if on_windows then
      path = path:gsub("\\", "/")
      return "file:///" .. path
   else
      return "file://" .. path
   end
end

return M
