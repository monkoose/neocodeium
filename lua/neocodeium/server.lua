-- Imports ------------------------------------------------- {{{1

local utils = require("neocodeium.utils")
local log = require("neocodeium.log")
local api_key = require("neocodeium.api_key")
local options = require("neocodeium.options").options
local stdio = require("neocodeium.utils.stdio")
local events = require("neocodeium.events")
local Bin = require("neocodeium.binary")
local state = require("neocodeium.state")

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
---@field startup_callback? fun()
---@field metadata request_metadata
local Server = {
   bin = Bin.new(),
   is_restart = false,
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

   if state.chat_enabled then
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

   ---@diagnostic disable-next-line: assign-type-mismatch
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
      log.info("Restarting the server...", { type = log.ECHO, silent = options.silent })
      self.is_restart = true
      self:stop()
   else
      log.info("Starting the server...", { type = log.ECHO, silent = options.silent })
      self:run()
   end
end

---Sends request to the server
---@param type request_type
---@param data table
---@param on_exit? fun(response: string)
function Server:request(type, data, on_exit)
   if not self.port then
      return
   end

   local port_number = tonumber(self.port)
   if not port_number then
      log.error("Failed to parse port number: " .. self.port)
      return
   end

   local ok, body = pcall(json.encode, data)
   if not ok then
      log.error("Failed to encode request data: " .. tostring(body))
      return
   end

   local header = table.concat({
      "POST /exa.language_server_pb.LanguageServerService/" .. type .. " HTTP/1.1",
      "Host: 127.0.0.1:" .. self.port,
      "Content-Type: application/json",
      "Content-Length: " .. #body,
      "Connection: close",
      "\r\n",
   }, "\r\n")

   local client, tcp_err = uv.new_tcp()
   if not client then
      log.error("Failed to create TCP client: " .. tcp_err)
      return
   end

   client:connect("127.0.0.1", port_number, function(err)
      if err then
         client:close()
         log.info("Failed to connect to the server: " .. err)
         return
      end

      local _, write_err = client:write({ header, body })
      if write_err then
         client:close()
         log.info("Sending request failed: " .. write_err)
         return
      end

      local response_chunks = {}

      client:read_start(function(read_err, chunk)
         if read_err then
            log.info("Invalid response from the server:\n" .. read_err)
            client:close()
         elseif chunk then
            if on_exit then
               table.insert(response_chunks, chunk)
            end
         else -- EOF
            client:close()
            if on_exit then
               local response = table.concat(response_chunks)
               local header_end = response:find("\r\n\r\n", 1, true)
               if header_end then
                  on_exit(response:match("{.*}", header_end + 4))
               end
            end
         end
      end)
   end)
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
      log.info("Server started on port " .. port, { type = log.BOTH, silent = options.silent })

      state.request_data.metadata = self.metadata
      state.accept_request_data.metadata = self.metadata
      state.completion_request_data.metadata = self.metadata

      self.port = port
      if self.startup_callback then
         self.startup_callback()
         self.startup_callback = nil
      end
      events.emit("NeoCodeiumServerConnected")

      timer:stop()
      local interval = 10000 -- 10 seconds
      -- constantly send heartbeats
      timer:start(interval, interval, function()
         self:request("Heartbeat", state.request_data)
      end)
   end
end
-- }}}1

return Server

-- vim: fdm=marker
