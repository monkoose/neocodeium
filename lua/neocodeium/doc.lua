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

---Returns document data for the buffer `bufnr`.
---@param bufnr bufnr
---@return document|nil
local function get_buf_doc(bufnr)
   local buf_cache = M.cached_data[bufnr]
   local buf_tick = nvim_buf_get_var(bufnr, "changedtick") ---@type integer
   -- use new data only when buffer's content has changed, otherwise use cached data
   if buf_cache and buf_tick == buf_cache.tick then
      return M.cached_data[bufnr].data
   end

   local buf_ft = nvim_get_option_value("filetype", { buf = bufnr })
   if
      buf_ft ~= ""
      and utils.is_normal_buf(bufnr)
      and state:get_status(bufnr) == STATUS.enabled
      and nvim_buf_get_name(bufnr):find(state.project_root, 1, true)
   then
      local doc_data = M.get(bufnr, buf_ft, options.max_lines, { 0, 0 })
      M.cached_data[bufnr] = {
         data = doc_data,
         tick = buf_tick,
      }
      return doc_data
   end
end

---Returns docs for all loaded buffers.
---@param cur_bufnr integer current buffer number
---@return document[]
function M.get_all_loaded(cur_bufnr)
   if options.max_lines == 0 then
      return {}
   end

   local docs = {}
   for b in utils.loaded_bufs() do
      -- Skip current buffer, because it's already processed
      if b ~= cur_bufnr then
         local doc_data = get_buf_doc(b)
         if doc_data then
            table.insert(docs, doc_data)
         end
      end
   end

   return docs
end
-- }}}1

return M

-- vim: fdm=marker
