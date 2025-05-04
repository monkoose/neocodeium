local uv = vim.uv

local nvim_exec2 = vim.api.nvim_exec2
local nvim_buf_set_lines = vim.api.nvim_buf_set_lines
local nvim_win_get_cursor = vim.api.nvim_win_get_cursor
local nvim_win_set_cursor = vim.api.nvim_win_set_cursor
local nvim_get_option_value = vim.api.nvim_get_option_value

local M = {}

---Executes ex command and returns any output
---@param cmd ex_cmd
---@return string
function M.exec(cmd)
   local ok, result = pcall(nvim_exec2, cmd, { output = true })
   if not ok then
      error(result)
   end

   return result.output
end

---Returns cursor position in the current window
---Unlike `vim.api.nvim_win_get_cursor()`, it returns 0-based indexes
---@return pos
function M.get_cursor()
   local cursor = nvim_win_get_cursor(0)
   return { cursor[1] - 1, cursor[2] }
end

---Sets cursor position in the current window
---Unlike `vim.api.nvim_win_set_cursor()`, it accepts 0-based indexes
---@param pos pos
function M.set_cursor(pos)
   nvim_win_set_cursor(0, { pos[1] + 1, pos[2] })
end

---Wrapper for `vim.api.nvim_buf_set_lines()` for current buffer
---@param lnum lnum start of the range
---@param end_lnum lnum end of the range
---@param replacement string[]
function M.set_lines(lnum, end_lnum, replacement)
   nvim_buf_set_lines(0, lnum, end_lnum, false, replacement)
end

---Returns true if current mode is insert or false otherwise.
---@return boolean
function M.is_insert()
   -- `vim.api` required so stub would work in tests
   return vim.api.nvim_get_mode().mode == "i"
end

---Returns OS name
---@param uname uv.os_uname.info
---@return os_name
local function get_os(uname)
   local os = uname.sysname
   if os == "Linux" then
      os = "linux"
   elseif os == "Darwin" then
      os = "macos"
   elseif os == "Windows_NT" or os:match("MINGW32_NT") then
      os = "windows"
   else
      os = "unknown"
   end

   return os
end

---Returns system architecture
---@param os os_name
---@param machine string
---@return arch
local function get_arch(os, machine)
   local function is_arm()
      if machine:match("^arm") or machine:match("^aarch64") then
         return true
      end
   end

   if (os == "linux" or os == "macos") and is_arm() then
      return "arm"
   end

   return "x64"
end

local system_info_cache = nil
---Returns system information
---@return system_info
function M.get_system_info()
   if not system_info_cache then
      local uname = uv.os_uname()
      local os = get_os(uname)
      local arch = get_arch(os, uname.machine)

      system_info_cache = {
         os = os,
         arch = arch,
         is_arm = arch == "arm",
         is_unix = os == "linux" or os == "macos",
         is_win = os == "windows",
      }
   end

   return system_info_cache
end

---Executes a function and restores original shell options afterwards
---@param func fun(...)
function M.with_shell(func, ...)
   local shell = vim.o.shell
   local shellpipe = vim.o.shellpipe
   local shellredir = vim.o.shellredir
   local shellquote = vim.o.shellquote
   local shellxquote = vim.o.shellxquote
   local shellcmdflag = vim.o.shellcmdflag

   func(...)

   vim.o.shell = shell
   vim.o.shellpipe = shellpipe
   vim.o.shellredir = shellredir
   vim.o.shellquote = shellquote
   vim.o.shellxquote = shellxquote
   vim.o.shellcmdflag = shellcmdflag
end

---Returns true if `val` is nil or empty
---@param val? string|any[]
---@return boolean
function M.is_empty(val)
   return val == nil or #val == 0
end

---Returns true if buffer with `bufnr` is not a special buffer.
---@param bufnr bufnr
---@return boolean
function M.is_normal_buf(bufnr)
   return nvim_get_option_value("buftype", { buf = bufnr }) == ""
end

return M
