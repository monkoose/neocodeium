local options = require("neocodeium.options").options
local LEVEL = require("neocodeium.enums").LEVEL

local fn = vim.fn
local uv = vim.uv

---Log file
local logfile = fn.tempname() .. "-neocodeium.log"
local min_log_level = vim.env.NEOCODEIUM_LOG_LEVEL or options.log_level
---@type integer
local o644 = tonumber(644, 8) ---@diagnostic disable-line: assign-type-mismatch

local M = {
   BOTH = 0,
   FILE = 1,
   ECHO = 2,
}

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

local function scheduled_echo(msg, lvl, opts)
   opts = opts or {}
   local silent = opts.silent or false
   local log_type = opts.type or M.FILE
   if not (silent or log_type == M.FILE) then
      vim.schedule(function()
         vim.cmd.redraw()
         vim.notify("NeoCodeium: " .. msg, lvl)
      end)
   end
end

---@param lvl level
---@return fun(msg: string, opts?: { silent?: boolean, type?: integer })
local function log(lvl)
   if lvl >= LEVEL[min_log_level] then
      return function(msg, opts)
         local log_type = (opts and opts.type) or M.FILE
         if log_type == M.FILE or log_type == M.BOTH then
            uv.fs_open(logfile, "a", o644, function(_, fd)
               if fd then
                  uv.fs_write(fd, append_newline(msg), -1, function()
                     uv.fs_close(fd)
                  end)
               end
            end)
         end
         if log_type == M.ECHO or log_type == M.BOTH then
            scheduled_echo(msg, lvl, opts)
         end
      end
   elseif lvl >= LEVEL.info then
      return function(msg, opts)
         scheduled_echo(msg, lvl, opts)
      end
   else
      return function(_, _) end
   end
end

---Returns log file path
---@return filepath
function M.get_log_file()
   return logfile
end

M.trace = log(LEVEL.trace) ---@type fun(msg: string, opts?: table)
M.debug = log(LEVEL.debug) ---@type fun(msg: string, opts?: table)
M.info = log(LEVEL.info) ---@type fun(msg: string, opts?: table)
M.warn = log(LEVEL.warn) ---@type fun(msg: string, opts?: table)
M.error = log(LEVEL.error) ---@type fun(msg: string, opts?: table)

return M
