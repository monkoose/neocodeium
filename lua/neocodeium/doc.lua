-- Imports ------------------------------------------------- {{{1

local filetype = require("neocodeium.filetype")
local options = require("neocodeium.options").options
local stdio = require("neocodeium.utils.stdio")
local utils = require("neocodeium.utils")
local state = require("neocodeium.state")
local STATUS = require("neocodeium.enums").STATUS

local nvim_buf_get_lines = vim.api.nvim_buf_get_lines
local nvim_buf_get_name = vim.api.nvim_buf_get_name
local nvim_get_option_value = vim.api.nvim_get_option_value
local nvim_buf_get_var = vim.api.nvim_buf_get_var

-- Public API ---------------------------------------------- {{{1

---@alias docdata table<bufnr, { data: document, tick: integer }>

---@class Doc
---@field cached_data docdata # Persistent cache of the buffers data.
local M = { cached_data = {} }

---Returns document data.
---@param buf bufnr
---@param ft string buffer filetype
---@param max_lines integer maximum lines to process, -1 for all lines
---@param pos pos
---@return document
function M.get(buf, ft, max_lines, pos)
   local text = table.concat(nvim_buf_get_lines(buf, 0, max_lines, false), "\n")
   local first_ft = ft:gsub("%..*", "")
   local name = nvim_buf_get_name(buf)
   local lang ---@type string
   if first_ft == "" then
      lang = "plaintext"
   else
      lang = filetype.aliases[first_ft] or first_ft
   end

   return {
      text = text,
      editor_language = ft == "" and "unspecified" or ft,
      language = filetype.language[lang] or filetype.language.unspecified,
      cursor_position = { row = pos[1], col = pos[2] },
      absolute_uri = stdio.to_uri(name),
      workspace_uri = state.project_root_uri,
      line_ending = "\n",
   }
end

---Returns docs for all loaded buffers.
---@param cur_bufnr integer current buffer number
---@return document[]
function M.get_all_loaded(cur_bufnr)
   if options.max_lines == 0 then
      return {}
   end

   local doc_data
   local docs = {}
   local pos = { 0, 0 }
   for b in utils.loaded_bufs() do
      local buf_ft = nvim_get_option_value("filetype", { buf = b })
      if
         b ~= cur_bufnr
         and buf_ft ~= ""
         and utils.is_normal_buf(b)
         and state:get_status(b) == STATUS.enabled
         and nvim_buf_get_name(b):find(state.project_root, 1, true)
      then
         local buf_cache = M.cached_data[b]
         local buf_tick = nvim_buf_get_var(b, "changedtick") ---@type integer
         -- use new data only when buffer's content has changed, otherwise use cached data
         if not buf_cache or buf_tick ~= buf_cache.tick then
            doc_data = M.get(b, buf_ft, options.max_lines, pos)
            table.insert(docs, doc_data)
            M.cached_data[b] = {
               data = doc_data,
               tick = buf_tick,
            }
         else
            table.insert(docs, M.cached_data[b].data)
         end
      end
   end

   return docs
end
-- }}}1

return M

-- vim: fdm=marker
