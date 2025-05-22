-- Imports ------------------------------------------------- {{{1

local utils = require("neocodeium.utils")
local conf = require("neocodeium.utils.conf")
local options = require("neocodeium.options").options
local stdio = require("neocodeium.utils.stdio")
local log = require("neocodeium.log")

local fn = vim.fn
local fs = vim.fs

-- Binary -------------------------------------------------- {{{1

---@class Binary
---@field version string
---@field path filepath
---@field name? string
local Bin = { version = "1.46.3" }

-- Auxiliary functions ------------------------------------- {{{1

---Checks if binary was expanded successfully.
---@return boolean
local function is_expanded_successfully()
   if vim.v.shell_error ~= 0 then
      log.error("Failed to extract binary.", { type = log.BOTH })
      return false
   end
   return true
end

---Expands language server binary from compressed file on Windows.
---Returns `true` if expansion was successful.
---@param bin_gz filepath
---@return boolean
local function powershell_expand(bin_gz)
   utils.with_shell(function()
      vim.o.shell = "powershell"
      vim.o.shellpipe = "|"
      vim.o.shellredir = "| Out-File -Encoding UTF8"
      vim.o.shellquote = ""
      vim.o.shellxquote = ""
      vim.o.shellcmdflag = "-NoLogo -NoProfile -ExecutionPolicy RemoteSigned -Command"
      fn.system(
         "& { . "
            .. fn.shellescape(stdio.root_dir() .. "/powershell/gzip.ps1")
            .. "; Expand-File "
            .. fn.shellescape(bin_gz)
            .. " }"
      )
   end)
   return is_expanded_successfully()
end

---Expands language server binary from compressed file on POSIX.
---Returns `true` if expansion was successful.
---@param bin_path filepath
local function posix_expand(bin_path)
   -- Uncompress binary
   fn.system("gzip -d " .. fn.shellescape(bin_path .. ".gz"))
   if not is_expanded_successfully() then
      return false
   end
   -- Make binary executable
   fn.system("chmod +x " .. fn.shellescape(bin_path))
   if vim.v.shell_error ~= 0 then
      log.error("Failed to make binary executable\n" .. vim.v.shell_error, { type = log.BOTH })
      return false
   end
   return true
end

-- Binary methods ------------------------------------------ {{{1

---@return Binary
function Bin.new()
   local self = setmetatable({}, { __index = Bin })

   if options.bin and stdio.readable(options.bin) then
      self.path = options.bin
      return self
   end

   local system_info = utils.get_system_info()
   if system_info.os == "unsupported" or system_info.arch == "unsupported" then
      log.error("Unsupported OS or architecture", { type = log.BOTH })
   else
      self.name = "language_server_" .. system_info.os .. "_" .. system_info.arch
      if system_info.os == "windows" then
         self.name = self.name .. ".exe"
      end
      self.path = fs.joinpath(conf.dir, "bin", self.version, self.name)
   end
   return self
end

---Downloads language server binary. Should be used only after `Bin.new()`,
---so that `Bin.path` and `Bin.suffix` are properly set.
---@async
---@param callback fun()
function Bin:download(callback)
   if not self.path then
      log.error("Binary path not set", { type = log.BOTH })
      return
   end

   local base_url = "https://github.com/Exafunction/codeium/releases/download"
   ---@type url
   local url = string.format("%s/language-server-v%s/%s.gz", base_url, self.version, self.name)

   local bin_dir = fs.dirname(self.path)
   if bin_dir then
      fn.delete(bin_dir, "rf")
      if fn.mkdir(bin_dir, "p") == 0 then
         log.error("Failed to create directory " .. bin_dir, { type = log.BOTH })
      end
   end

   log.info("Downloading binary v" .. self.version, { type = log.ECHO })
   vim.system(
      { "curl", "-Lo", self.path .. ".gz", url },
      { stdout = false },
      vim.schedule_wrap(function(o)
         if o.code ~= 0 then
            log.error("Failed to download binary\n" .. o.stderr, { type = log.BOTH })
         elseif callback then
            callback()
         end
      end)
   )
end

---Expands language server binary from compressed file.
---Returns `true` on success and `false` on failure.
---@return boolean
function Bin:expand()
   if not self.path then
      log.error("Binary path not set", { type = log.BOTH })
      return false
   end

   local bin_gz = self.path .. ".gz"
   log.info("Extracting binary...", { type = log.ECHO })

   local ok
   if utils.get_system_info().os == "windows" then
      ok = powershell_expand(bin_gz)
   else
      ok = posix_expand(self.path)
   end

   if ok then
      log.info("Binary extracted successfully", { type = log.ECHO })
   end

   return ok
end
-- }}}1

return Bin

-- vim: fdm=marker
