local nvim_exec2 = vim.api.nvim_exec2
local nvim_buf_set_lines = vim.api.nvim_buf_set_lines
local nvim_win_get_cursor = vim.api.nvim_win_get_cursor
local nvim_win_set_cursor = vim.api.nvim_win_set_cursor
local nvim_get_option_value = vim.api.nvim_get_option_value
local nvim_list_bufs = vim.api.nvim_list_bufs
local nvim_buf_is_loaded = vim.api.nvim_buf_is_loaded

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
---@return os_name
local function get_os()
   local os = jit.os
   if os == "Linux" then
      return "linux"
   elseif os == "OSX" then
      return "macos"
   elseif os == "Windows" then
      return "windows"
   end
   return "unsupported"
end

---Returns system architecture
---@return arch
local function get_arch()
   local arch = jit.arch
   if arch == "x64" then
      return "x64"
   elseif arch:match("^arm") then
      local os = jit.os
      if os == "OSX" or os == "Linux" then
         return "arm"
      else
         return "unsupported"
      end
   end
   return "unsupported"
end

local system_info = nil
---Returns system information
---@return system_info
function M.get_system_info()
   if not system_info then
      local os = get_os()
      local arch = get_arch()

      system_info = {
         os = os,
         arch = arch,
      }
   end

   return system_info
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

---Returns true if file encoding in the current buffer is utf-8 or latin1
---@param bufnr bufnr
---@return boolean
function M.is_utf8_or_latin1(bufnr)
   local encoding = vim.bo[bufnr].fileencoding
   return encoding == "" or encoding == "utf-8" or encoding == "latin1"
end

---Returns iterator over numbers of all loaded buffers.
---@return Iter
function M.loaded_bufs()
   return vim.iter(nvim_list_bufs()):filter(nvim_buf_is_loaded)
end

---Returns iterator over numbers of all normal buffers.
---@return Iter
function M.normal_bufs()
   return vim.iter(nvim_list_bufs()):filter(M.is_normal_buf)
end

---Returns iterator over numbers of all buffers.
---@return Iter
function M.all_bufs()
   return vim.iter(nvim_list_bufs())
end

return M
