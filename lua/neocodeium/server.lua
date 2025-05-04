-- Imports ------------------------------------------------- {{{1

local utils = require("neocodeium.utils")
local log = require("neocodeium.log")
local api_key = require("neocodeium.api_key")
local options = require("neocodeium.options").options
local stdio = require("neocodeium.utils.stdio")
local echo = require("neocodeium.utils.echo")
local events = require("neocodeium.events")
local Bin = require("neocodeium.binary")

local fn = vim.fn
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
---@field chat_enabled boolean
---@field callback? fun()
local Server = {
   bin = Bin.new(),
   is_restart = false,
   chat_enabled = false,
   metadata = {
      api_key = api_key.get(),
      ide_name = "neovim",
      ide_version = Bin.version,
      extension_name = "neocodeium",
      extension_version = Bin.version,
   },
}

-- Auxiliary functions ------------------------------------- {{{1

---@param path filepath
---@return filepath|nil
local function find_port_file(path)
   return fs.find(function(name)
      return name:match("^%d%d%d%d%d?$")
   end, { path = path, type = "file" })[1]
end

---@param t table list to append data
---@return fun(_, data?: string)
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
   local manager_dir = fn.tempname() .. "/codeium/manager"
   fn.mkdir(manager_dir, "p")

   local args = {
      "--api_server_url",
      api_url or "https://server.codeium.com",
      "--manager_dir",
      manager_dir,
   }

   if not utils.is_empty(options.server.api_url) then
      table.insert(args, "--enterprise_mode")
   end

   if not utils.is_empty(options.server.portal_url) then
      table.insert(args, "--portal_url")
      table.insert(args, options.server.portal_url)
   end

   if self.chat_enabled then
      table.insert(args, "--enable_local_search")
      table.insert(args, "--enable_index_service")
      table.insert(args, "--search_max_workspace_file_count=5000")
      table.insert(args, "--enable_chat_web_server")
      table.insert(args, "--enable_chat_client")
   end

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
         events.emit("NeoCodeiumServerStopped")
         self.pid = nil
         self.port = nil
         if self.is_restart then
            self.is_restart = false
            self:run()
         end
      end)
   )

   events.emit("NeoCodeiumServerConnecting")

   local function log_data(err, data)
      if err then
         return
      end

      if data then
         log.info(data)
      end
   end

   stdout:read_start(log_data)
   stderr:read_start(log_data)

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

   if not api_key.check() then
      return
   end

   if stdio.executable(self.bin.path) then
      self:start()
   else
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
   end
end

---Restarts the server
function Server:restart()
   if self.handle and not uv.is_closing(self.handle) then
      echo.info("restarting the server...", options.silent)
      self.is_restart = true
      self:stop()
   else
      echo.info("starting the server...", options.silent)
      self:run()
   end
end

---Sends request to the server
---@param type request_type
---@param data request_data
---@param on_exit? fun(response: response)
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
      if self.callback then
         self.callback()
         self.callback = nil
      end
      events.emit("NeoCodeiumServerConnected")

      timer:stop()
      local interval = 10000 -- 10 seconds
      -- constantly send heartbeats
      timer:start(interval, interval, function()
         self:request("Heartbeat", { metadata = self.metadata })
      end)
   end
end
-- }}}1

return Server

-- vim: fdm=marker
