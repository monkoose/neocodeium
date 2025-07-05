-- Imports ------------------------------------------------- {{{1

local options = require("neocodeium.options").options
local server = require("neocodeium.server")
local doc = require("neocodeium.doc")
local log = require("neocodeium.log")
local utils = require("neocodeium.utils")
local state = require("neocodeium.state")
local STATUS = require("neocodeium.enums").STATUS

local nvim_create_autocmd = vim.api.nvim_create_autocmd
local nvim_create_augroup = vim.api.nvim_create_augroup
local nvim_win_get_cursor = vim.api.nvim_win_get_cursor
local nvim_get_option_value = vim.api.nvim_get_option_value

-- Chat ---------------------------------------------------- {{{1

local chat = {}
local request_data = {}

-- Refresh chat content on buffer change.
nvim_create_autocmd("BufEnter", {
   group = nvim_create_augroup("neocodeium_chat", {}),
   callback = function()
      if server.port then
         pcall(chat.refresh_context)
      end
   end,
})

-- Chat methods -------------------------------------------- {{{1

---Opens chat in browser.
---@param response table
function chat.launch(response)
   local metadata = server.metadata
   local processes = vim.json.decode(response.out[1])
   local chat_port = processes["chatClientPort"]
   local ws_port = processes["chatWebServerPort"]

   -- possible, server is not ready
   if not (chat_port and ws_port) then
      log.error(
         "Server not ready. Chat client port or web server port is missing.",
         { type = log.BOTH }
      )
      return
   end

   local url = vim.iter({
      api_key = metadata.api_key,
      ide_name = metadata.ide_name,
      ide_version = metadata.ide_version,
      extension_name = metadata.extension_name,
      extension_version = metadata.extension_version,
      web_server_url = "ws://127.0.0.1:" .. ws_port,
      has_enterprise_extension = not utils.is_empty(options.server.api_url),
      locale = "en",
      ide_telemetry_enabled = true,
      has_index_service = true,
      app_name = "Neovim",
      spen_file_pointer_enabled = true,
      diff_view_enabled = true,
   }):fold("http://127.0.0.1:" .. chat_port .. "/?", function(acc, key, value)
      return acc .. key .. "=" .. tostring(value) .. "&"
   end)

   vim.ui.open(url)
   vim.schedule(function()
      log.info("Chat has been opened in the browser", { type = log.ECHO })
   end)
end

--- XXX: should it change workspace?
---Sends a request to the server to refresh context.
function chat.refresh_context()
   if state:get_status() == STATUS.enabled then
      local cursor = nvim_win_get_cursor(0)
      local ft = nvim_get_option_value("filetype", { buf = 0 })
      request_data.active_document = doc.get(0, ft, -1, cursor)
      server:request("RefreshContextForIdeAction", request_data)
   end
end

---Sends a request to the server to add a tracked workspace.
function chat.add_tracked_workspace()
   server:request("AddTrackedWorkspace", { workspace = state.project_root })
end

return chat

-- vim: fdm=marker
