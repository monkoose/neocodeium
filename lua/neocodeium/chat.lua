local options = require("neocodeium.options").options
local server = require("neocodeium.server")
local doc = require("neocodeium.doc")
local echo = require("neocodeium.utils.echo")

local fs = vim.fs
local uv = vim.uv

local nvim_create_autocmd = vim.api.nvim_create_autocmd
local nvim_create_augroup = vim.api.nvim_create_augroup
local nvim_win_get_cursor = vim.api.nvim_win_get_cursor
local nvim_get_option_value = vim.api.nvim_get_option_value

local chat = {}

-- Refresh chat content on buffer change
nvim_create_autocmd("BufEnter", {
   group = nvim_create_augroup("neocodeium_chat", {}),
   callback = function()
      if server.port then
         pcall(chat.refresh_context)
      end
   end,
})

---@return string|nil
local function get_project_root()
   return fs.root(uv.cwd() or 0, options.root_dir)
end

---Opens chat in browser
---@param response table
function chat.launch(response)
   local metadata = server:request_metadata()
   local processes = vim.json.decode(response.out[1])
   local chat_port = processes["chatClientPort"]
   local ws_port = processes["chatWebServerPort"]

   -- possible, server is not ready
   if not (chat_port and ws_port) then
      return
   end

   local has_enterprise_extension = false
   if options.server.api_url and options.server.api_url ~= "" then
      has_enterprise_extension = true
   end

   local url = vim.iter({
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
   }):fold("http://127.0.0.1:" .. chat_port .. "/?", function(acc, key, value)
      return acc .. key .. "=" .. tostring(value) .. "&"
   end)

   vim.ui.open(url)
   vim.schedule(function()
      echo.info("chat has been opened in the browser")
   end)
end

---Sends a request to the server to refresh context
function chat.refresh_context()
   if options.status(0) == 0 then
      local cursor = nvim_win_get_cursor(0)
      local ft = nvim_get_option_value("filetype", { buf = 0 })
      server:request("RefreshContextForIdeAction", { active_document = doc.get(0, ft, -1, cursor) })
   end
end

---Sends a request to the server to add a tracked workspace
function chat.add_tracked_workspace()
   local root = get_project_root()
   if root then
      server:request("AddTrackedWorkspace", { workspace = root })
   end
end

return chat
