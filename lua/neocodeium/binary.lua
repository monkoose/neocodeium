-- Imports ------------------------------------------------- {{{1

local utils = require("neocodeium.utils")
local echo = require("neocodeium.utils.echo")
local conf = require("neocodeium.utils.conf")
local options = require("neocodeium.options").options
local stdio = require("neocodeium.utils.stdio")

local fn = vim.fn

-- Binary -------------------------------------------------- {{{1

---@class Binary
---@field version string
---@field path filepath
---@field suffix? string
---@field sha? string
local Bin = { version = "1.8.45" }

-- Auxiliary functions ------------------------------------- {{{1

---Expands langauge server binary from compressed file on Windows.
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
    self.suffix = system_info.os .. "_" .. system_info.arch
    if system_info.is_win then
      self.suffix = self.suffix .. ".exe"
    end

    self.sha = conf.load(conf.dir()).sha
    local bin_dir = conf.data_dir() .. "/bin/" .. (self.sha or self.version)
    self.path = bin_dir .. "/language_server_" .. self.suffix
  end

  return self
end

---Downloads language server binary. Should be used only after `Bin:set()`,
---so that `Bin.path`, `Bin.suffix` and `Bin.sha` are properly set.
---@async
---@param callback fun()
function Bin:download(callback)
  local url ---@type url
  if self.sha then
    url = string.format(
      "https://storage.googleapis.com/exafunction-dist/codeium/%s/language_server_%s.gz",
      self.sha,
      self.suffix
    )
  else
    local base_url = "https://github.com/Exafunction/codeium/releases/download"
    if options.server.portal_url then
      base_url = options.server.portal_url:gsub("/$", "")
    end
    url = string.format(
      "%s/language-server-v%s/language_server_%s.gz",
      base_url,
      self.version,
      self.suffix
    )
  end

  echo.info("Downloading binary...")
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

---Expands langauge server binary from compressed file.
---Returns `true` on success and `false` on failure.
---@return boolean
function Bin:expand()
  local bin_gz = self.path .. ".gz"
  echo.info("Extracting binary...")
  if utils.get_system_info().is_win then
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
