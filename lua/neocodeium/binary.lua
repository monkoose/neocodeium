-- Imports ------------------------------------------------- {{{1

local utils = require("neocodeium.utils")
local echo = require("neocodeium.utils.echo")
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
---@field suffix? string
local Bin = { version = "1.46.3" }

-- Auxiliary functions ------------------------------------- {{{1

---Expands language server binary from compressed file on Windows.
---@param bin_gz filepath
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
end

-- Binary methods ------------------------------------------ {{{1

---@return Binary
function Bin.new()
   local self = setmetatable({}, { __index = Bin })

   if options.bin and stdio.readable(options.bin) then
      self.path = options.bin
   else
      local system_info = utils.get_system_info()
      if system_info.os == "unsupported" or system_info.arch == "unsupported" then
         log.error("Unsupported OS or architecture")
         echo.error("Unsupported OS or architecture")
      else
         self.suffix = system_info.os .. "_" .. system_info.arch
         if system_info.os == "windows" then
            self.suffix = self.suffix .. ".exe"
         end

         local bin_dir = conf.dir .. "/bin/" .. self.version
         self.path = bin_dir .. "/language_server_" .. self.suffix
      end
   end

   return self
end

---Downloads language server binary. Should be used only after `Bin.new()`,
---so that `Bin.path` and `Bin.suffix` are properly set.
---@async
---@param callback fun()
function Bin:download(callback)
   if not self.path then
      log.error("Binary path not set")
      echo.error("Binary path not set")
      return
   end

   local base_url = "https://github.com/Exafunction/codeium/releases/download"
   ---@type url
   local url = string.format(
      "%s/language-server-v%s/language_server_%s.gz",
      base_url,
      self.version,
      self.suffix
   )

   local bin_dir = fs.dirname(self.path)
   if bin_dir then
      fn.delete(bin_dir, "rf")
      -- TODO: handle error
      fn.mkdir(bin_dir, "p")
   end

   echo.info("Downloading binary v" .. self.version)
   vim.system(
      { "curl", "-Lo", self.path .. ".gz", url },
      { stdout = false },
      vim.schedule_wrap(function(o)
         if o.code ~= 0 then
            echo.error("failed to download binary\n" .. o.stderr)
            return
         end
         if callback then
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
      log.error("Binary path not set")
      echo.error("Binary path not set")
      return false
   end
   local bin_gz = self.path .. ".gz"
   echo.info("Extracting binary...")
   if utils.get_system_info().os == "windows" then
      powershell_expand(bin_gz)
   else
      -- Uncompress binary
      fn.system("gzip -d " .. fn.shellescape(bin_gz))
      if vim.v.shell_error ~= 0 then
         echo.error("failed to extract binary\n" .. vim.v.shell_error)
         return false
      end
      -- Make binary executable
      fn.system("chmod +x " .. fn.shellescape(self.path))
      if vim.v.shell_error ~= 0 then
         echo.error("failed to make binary executable\n" .. vim.v.shell_error)
         return false
      else
         echo.info("Binary extracted successfully")
      end
   end
   return true
end
-- }}}1

return Bin

-- vim: fdm=marker
