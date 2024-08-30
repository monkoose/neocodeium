-- Imports ------------------------------------------------- {{{1

local utils = require("neocodeium.utils")
local echo = require("neocodeium.utils.echo")
local conf = require("neocodeium.utils.conf")
local log = require("neocodeium.log")
local options = require("neocodeium.options").options
local api_key = require("neocodeium.api_key")
local stdio = require("neocodeium.utils.stdio")
local server = require("neocodeium.server")
local doc = require("neocodeium.doc")

local fn = vim.fn
local json = vim.json

-- Auxiliary functions ------------------------------------- {{{1

---Opens url in default browser and notifies a user.
---@param url url
local function open_browser(url)
  local obj = vim.ui.open(url)
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

  local config_dir = conf.data_dir()
  local config_path = config_dir .. "/config.json"
  local config = conf.load(config_dir)
  config.api_key = key

  local ok, err = pcall(function()
    fn.mkdir(config_dir, "p")
    fn.writefile({ json.encode(config) }, config_path)
  end)

  if ok then
    echo.info("success. Autocompletion now should work")
  else
    echo.error("could not write api key to config.json")
    log.error("Could not write api key to config.json\n" .. err)
  end
end

function M.disable()
  options.enabled = false
end

function M.enable()
  options.enabled = true
  if not server.pid then
    server:run()
  end
end

function M.disable_buffer()
  vim.b.neocodeium_enabled = false
end

function M.enable_buffer()
  vim.b.neocodeium_enabled = true
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

function M.toggle()
  options.enabled = not options.enabled
end

local function launch_chat(response)
  local metadata = server:request_metadata()
  local processes = vim.json.decode(response.out[1])
  local chat_port = processes["chatClientPort"]
  local ws_port = processes["chatWebServerPort"]

  -- possible, server is not ready
  if not (chat_port and ws_port) then
    return
  end

  local server_opts = options.server
  local has_enterprise_extension = (server_opts.api_url and server_opts.api_url ~= "") and true
    or false

  local url = vim
    .iter({
      api_key = metadata.api_key,
      ide_name = metadata.ide_name,
      ide_version = metadata.ide_version,
      extension_name = metadata.extension_name,
      extension_version = metadata.extension_version,
      web_server_url = "ws://127.0.0.1:" .. ws_port,
      has_enterprise_extension = has_enterprise_extension,
      locale = "en",
      ide_telemetry_enabled = true,
      has_index_service = true,
      app_name = "Neovim",
      spen_file_pointer_enabled = true,
      diff_view_enabled = true,
    })
    :fold("http://127.0.0.1:" .. chat_port .. "/?", function(acc, key, value)
      return acc .. key .. "=" .. tostring(value) .. "&"
    end)

  vim.schedule(function()
    open_browser(url)
  end)
end

local function get_project_root()
  return vim.fs.root(vim.uv.cwd() or 0, options.root_dir)
end

local function refresh_context()
  local cursor = vim.api.nvim_win_get_cursor(0)
  server:request("RefreshContextForIdeAction", {
    active_document = doc.get(0, vim.filetype.match({ buf = 0 }) or "", cursor[1], cursor),
  })
end

local function add_tracked_workspace()
  local root = get_project_root()
  if root then
    server:request("AddTrackedWorkspace", { workspace = root })
  end
end

function M.open_chat()
  refresh_context()
  server:request("GetProcesses", { metadata = server:request_metadata() }, launch_chat)
  add_tracked_workspace()
end
-- }}}1

return M

-- vim: fdm=marker
