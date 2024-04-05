-- Imports ------------------------------------------------- {{{1

local log = require("neocodeium.log")
local api_key = require("neocodeium.api_key")
local options = require("neocodeium.options").options
local stdio = require("neocodeium.utils.stdio")
local echo = require("neocodeium.utils.echo")
local utils = require("neocodeium.utils")
local Bin = require("neocodeium.binary")

local vf = vim.fn
local uv = vim.uv
local fs = vim.fs
local json = vim.json

-- Server -------------------------------------------------- {{{1

---@class Server
---@field bin Binary
---@field port? string
---@field handle? uv.uv_process_t
---@field pid? integer
---@field is_restart boolean
local Server = {
  bin = Bin.new(),
  is_restart = false,
}

-- Auxiliary functions ------------------------------------- {{{1

---@param path filepath
---@return filepath?
local function find_port_file(path)
  return fs.find(function(name)
    return name:match("^%d%d%d%d%d?$")
  end, { path = path, type = "file" })[1]
end

---@param t table list to append data
---@return fun(_, data: string?)
local function data_appender(t)
  return function(_, data)
    if data then
      t[#t + 1] = data
    end
  end
end

-- Server methods ------------------------------------------ {{{1

---Spawns a process for the server and sets Server.handle.
---@private
function Server:start()
  local timer = assert(uv.new_timer())
  local api_url = options.server.api_url
  local manager_dir = vf.tempname() .. "/codeium/manager"
  vf.mkdir(manager_dir, "p")

  local args = {
    "--api_server_url",
    api_url and api_url .. " --enterprise_mode" or "https://server.codeium.com",
    "--manager_dir",
    manager_dir,
  }

  log.info("Starting server with manager_dir " .. manager_dir)

  local stdin = assert(uv.new_pipe())
  local stdout = assert(uv.new_pipe())
  local stderr = assert(uv.new_pipe())

  self.handle, self.pid = uv.spawn(
    self.bin.path,
    ---@diagnostic disable-next-line: missing-fields
    {
      args = args,
      stdio = { stdin, stdout, stderr },
    },
    vim.schedule_wrap(function(_, _)
      timer:stop()
      timer:close()
      uv.close(stdin)
      uv.close(stdout)
      uv.close(stderr)
      if self.handle then
        uv.close(self.handle)
        self.handle = nil
      end
      log.info("Server stopped")
      self.pid = nil
      self.port = nil
      if self.is_restart then
        self.is_restart = false
        self:run()
      end
    end)
  )

  -- Timer to find and connect to the server port
  timer:start(
    500,
    300,
    vim.schedule_wrap(function()
      self:init(timer, manager_dir)
    end)
  )
end

---Launches the server; if server binary is not found, downloads it first.
function Server:run()
  if self.handle and not uv.is_closing(self.handle) then
    return
  end

  api_key.check()

  if stdio.executable(self.bin.path) then
    self:start()
  else
    local bin_dir = fs.dirname(self.bin.path)
    if bin_dir then
      vf.delete(bin_dir, "rf")
      vf.mkdir(bin_dir, "p")
    end

    self.bin:download(function()
      if self.bin:expand() then
        self:start()
      end
    end)
  end
end

---Properly stops the server, executing self.handle on_exit callback.
function Server:stop()
  if self.pid then
    uv.kill(self.pid, "sigint")
    echo.info("server stopped", options.silent)
  else
    echo.warn("server is not running")
  end
end

---Restarts the server
function Server:restart()
  if self.handle and not uv.is_closing(self.handle) then
    self.is_restart = true
    self:stop()
  else
    self:run()
  end
end

---Sends request to the server
---@param type request_type
---@param data request_data
---@param on_exit fun(response: response)?
function Server:request(type, data, on_exit)
  ---@type url
  local uri = "http://127.0.0.1:"
    .. self.port
    .. "/exa.language_server_pb.LanguageServerService/"
    .. type
  local cmd_args = { uri, "-H", "Content-Type: application/json", "-d@-" }
  -- Because response from the server can be splitted into multiple chunks
  -- we collecting them in this table
  local response = { out = {}, err = {} }

  -- Because requests are sent a lot do not assert return
  -- value of new_pipe() for some speed gain. In theory this
  -- shouldn't be a problem.
  local stdin = uv.new_pipe() --[[@as uv.uv_pipe_t]]
  local stdout = uv.new_pipe() --[[@as uv.uv_pipe_t]]
  local stderr = uv.new_pipe() --[[@as uv.uv_pipe_t]]

  local handle
  handle = uv.spawn("curl", { ---@diagnostic disable-line: missing-fields
    args = cmd_args,
    stdio = { stdin, stdout, stderr },
  }, function(_, _)
    uv.close(stdin)
    uv.close(stdout)
    uv.close(stderr)
    if on_exit then
      on_exit(response)
    end
    if handle then
      uv.close(handle)
    end
  end)

  stdout:read_start(data_appender(response.out))
  stderr:read_start(data_appender(response.err))

  -- Write encoded data and close stdin
  local ok, encoded_data = pcall(json.encode, data)
  if ok and encoded_data then
    uv.write(stdin, encoded_data)
  end
  uv.shutdown(stdin, function() end)
end

---Attempts to find server port and then after finding one
---constantly send heartbeat requests to the server
---@private
---@param timer uv.uv_timer_t
---@param manager_dir string
function Server:init(timer, manager_dir)
  local port_file = find_port_file(manager_dir)
  if port_file then
    local port = fs.basename(port_file)
    log.info("Found port: " .. port)
    echo.info("server started on port " .. port, options.silent)
    self.port = port

    timer:stop()
    local interval = 10000
    -- constantly send heartbeats
    timer:start(interval, interval, function()
      self:request("Heartbeat", { metadata = self:request_metadata() })
    end)
  end
end

local neovim_version = utils.get_neovim_version()

---Returns request metadata
---@return request_metadata
function Server:request_metadata()
  return {
    api_key = api_key.get(),
    ide_name = "neovim",
    ide_version = neovim_version,
    extension_name = "neocodeium",
    extension_version = self.bin.version,
  }
end
-- }}}1

return Server

-- vim: fdm=marker
