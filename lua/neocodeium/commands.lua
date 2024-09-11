-- Imports ------------------------------------------------- {{{1

local utils = require("neocodeium.utils")
local echo = require("neocodeium.utils.echo")
local conf = require("neocodeium.utils.conf")
local log = require("neocodeium.log")
local options = require("neocodeium.options").options
local api_key = require("neocodeium.api_key")
local stdio = require("neocodeium.utils.stdio")
local server = require("neocodeium.server")

local fn = vim.fn
local json = vim.json

-- Auxiliary functions ------------------------------------- {{{1

---Opens url in the default browser and notifies a user.
---@param url url
local function open_browser(url)
   vim.ui.open(url)
   echo.info(
      "browser should have been opened with the URL (if it doesn't, then open the URL manually):\n"
         .. url
         .. "\nLogin and copy a token on the page.\n\n"
   )
end

---Returns user input hiding text with * characters.
---@param msg string
---@return string
local function secret_input(msg)
   fn.inputsave()
   local result = fn.inputsecret(msg)
   fn.inputrestore()
   return result
end

---Fetches and returns codeium api key from the web.
---Returns nil on failure.
---@return string|nil
local function request_api_key()
   local api_url = options.server.api_url
   local register_user_url = api_url
         and api_url .. "/exa.seat_management_pb.SeatManagementService/RegisterUser"
      or "https://api.codeium.com/register_user/"

   local curl_with_args = {
      "curl",
      "-sS",
      register_user_url,
      "--header",
      "Content-Type:application/json",
      "--data",
   }

   local system = function(cmd)
      local str_cmd = table.concat(cmd, " ")
      return fn.system(str_cmd)
   end

   local on_windows = utils.get_system_info().is_win
   local ssl_error = "The revocation function was unable to check revocation for the certificate."
   local auth_token = secret_input("Paste your token here (it would be hidden): ")
   for _ = 1, 3 do
      if auth_token == "" then
         return
      end

      local json_token = fn.shellescape(json.encode({ firebase_id_token = auth_token }) or "")
      local cmd = vim.iter(curl_with_args):totable()
      table.insert(cmd, json_token)

      local response = system(cmd)
      if on_windows and response:find(ssl_error) then
         vim.cmd.redraw()
         vim.input({
            prompt = "For Windows systems behind a corporate proxy there "
               .. "may be trouble verifying the SSL certificates. "
               .. "Would you like to try auth without checking SSL certificate revocation? (Y/n): ",
            default = "y",
         }, function(input)
            local lower_input = input:lower()
            if lower_input == "y" or lower_input == "yes" then
               table.insert(cmd, 2, "--ssl-no-revoke")
               response = system(cmd)
            end
         end)
      end

      local ok, decoded_response = pcall(json.decode, response)
      if ok then
         local key = decoded_response.api_key
         if key and key ~= "" then
            return key
         end
      end

      echo.warn("Unexpected response: " .. response)
      auth_token = secret_input("Invalid token, please paste again: ")
   end
end

-- Commands ------------------------------------------------ {{{1

local M = {}

-- TODO: make disable and enable commands remove autocmds

function M.auth()
   local url = table.concat({
      options.server.portal_url or "https://www.codeium.com",
      "/profile?response_type=token",
      "&redirect_uri=vim-show-auth-token",
      "&state=a",
      "&scope=openid%20profile%20email",
      "&redirect_parameters_type=query",
   })

   open_browser(url)
   local key = request_api_key()
   if not key then
      echo.error("could not retrieve api key\nAuthentication is canceled")
      return
   end

   api_key.set(key)

   local config = conf.load()
   config.api_key = key

   local ok, err = pcall(function()
      fn.mkdir(conf.dir, "p")
      fn.writefile({ json.encode(config) }, conf.file)
   end)

   if ok then
      echo.info("success. Autocompletion now should work")
   else
      echo.error("could not write api key to config.json")
      log.error("Could not write api key to config.json\n" .. err)
   end
end

function M.disable(bang)
   options.enabled = false
   if bang and server.pid then
      server:stop()
      echo.info("the server has been halted")
   end
   utils.event("Disabled")
end

function M.enable()
   options.enabled = true
   utils.event("Enabled")
   if not server.pid then
      server:run()
   end
end

function M.toggle(bang)
   if options.enabled then
      M.disable(bang)
   else
      M.enable()
   end
end

function M.disable_buffer()
   vim.b.neocodeium_enabled = false
   utils.event("BufDisabled")
end

function M.enable_buffer()
   vim.b.neocodeium_enabled = true
   utils.event("BufEnabled")
end

function M.toggle_buffer()
   if vim.b.neocodeium_enabled == false then
      M.enable_buffer()
   else
      M.disable_buffer()
   end
end

function M.open_log()
   local log_file = log.get_log_file()
   if stdio.readable(log_file) then
      vim.cmd.tabedit(log_file)
      vim.bo.buftype = "nofile"
      vim.bo.bufhidden = "wipe"
      vim.bo.modifiable = false
      vim.wo.wrap = true
   else
      echo.warn("log file is empty")
   end
end

function M.restart()
   server:restart()
end

function M.chat()
   local chat = require("neocodeium.chat")
   local function launch_chat()
      chat.refresh_context()
      server:request("GetProcesses", { metadata = server:request_metadata() }, chat.launch)
      chat.add_tracked_workspace()
   end

   if server.chat_enabled and server.port then
      launch_chat()
   else
      server.callback = launch_chat
      server.chat_enabled = true
      server:restart()
   end
end
-- }}}1

return M

-- vim: fdm=marker
