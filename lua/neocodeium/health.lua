local stdio = require("neocodeium.utils.stdio")
local api_key = require("neocodeium.api_key")
local binary = require("neocodeium.binary")
local server = require("neocodeium.server")
local utils = require("neocodeium.utils")

local fn = vim.fn
local health = vim.health

local M = {}

local function system_info()
   health.start("System information:")
   local sys_info = utils.get_system_info()
   health.info(
      string.format(
         "*%s* *(%s)*\nIf it is not correctly detected, then consider to report a bug at\n%s",
         sys_info.os,
         sys_info.arch,
         "https://github.com/monkoose/neocodeium/issues"
      )
   )
end

local function check_curl()
   if stdio.executable("curl") then
      health.ok("*curl* is installed")
   else
      health.error("*curl* is missing")
   end
end

local function check_api_key()
   if api_key.get() then
      health.ok("*API* *key* is present")
   else
      health.error("*API* *key* is missing", "Please run `:NeoCodeium auth` to set it")
   end
end

local function check_bin()
   local bin = binary.new()
   if bin.path and stdio.executable(bin.path) then
      health.ok("*Server* *binary* exists: " .. fn.fnamemodify(bin.path, ":~"))
   else
      health.error("*Server* *binary* is missing")
   end
end

local function check_server()
   if server.pid and server.port then
      health.ok(
         string.format("*Server* is running on port %s with pid %s", server.port, server.pid)
      )
   else
      if not server.pid then
         health.error("*Server* has not been started")
      elseif not server.port then
         health.error(
            "*Server* *port* is not detected",
            "Finding a port can take some time (up to 20 seconds).\nPlease try `:checkhealth` again later."
         )
      end
   end
end

function M.check()
   system_info()
   health.start("Checks:")
   check_curl()
   check_api_key()
   check_bin()
   check_server()
end

return M
