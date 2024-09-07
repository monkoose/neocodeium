local options = require("neocodeium.options").options
local types = require("neocodeium.types")

local fn = vim.fn
local uv = vim.uv

---Log file
local logfile = fn.tempname() .. "-neocodeium.log"
local min_log_level = vim.env.NEOCODEIUM_LOG_LEVEL or "warn"

---Appends newline to `msg` if it doesn't end with it
---@param msg string
---@return string
local function append_newline(msg)
   if vim.endswith(msg, "\n") then
      return msg
   else
      return msg .. "\n"
   end
end

---@param lvl level
---@return fun(msg: string)
local function log(lvl)
   if lvl >= types.level[min_log_level] then
      local o644 = tonumber(644, 8) ---@diagnostic disable-line: param-type-mismatch
      return function(msg)
         uv.fs_open(logfile, "a", o644, function(_, fd)
            if fd then
               uv.fs_write(fd, append_newline(msg), -1, function()
                  uv.fs_close(fd)
               end)
            end
         end)
      end
   end

   return function(_) end
end

local M = {}

---Returns log file path
---@return filepath
function M.get_log_file()
   return logfile
end

M.trace = log(types.level.trace) ---@type fun(msg: string)
M.debug = log(types.level.debug) ---@type fun(msg: string)
M.info = log(types.level.info) ---@type fun(msg: string)
M.warn = log(types.level.warn) ---@type fun(msg: string)
M.error = log(types.level.error) ---@type fun(msg: string)

return M
