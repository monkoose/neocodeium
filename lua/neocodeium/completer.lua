-- Imports ------------------------------------------------- {{{1

local log = require("neocodeium.log")
local doc = require("neocodeium.doc")
local utils = require("neocodeium.utils")
local options = require("neocodeium.options").options
local server = require("neocodeium.server")
local renderer = require("neocodeium.renderer")
local state = require("neocodeium.state")
local PART = require("neocodeium.enums").PART
local REQUEST_STATUS = require("neocodeium.enums").REQUEST_STATUS

local fn = vim.fn
local json = vim.json

local nvim_feedkeys = vim.api.nvim_feedkeys
local nvim_get_current_buf = vim.api.nvim_get_current_buf
local nvim_replace_termcodes = vim.api.nvim_replace_termcodes

-- Completer ----------------------------------------------- {{{1

---@class cancel_requrest_data
---@field request_id integer

---@class Completer
---@field request_id integer
---@field other_docs document[]
---@field cancel_requrest_data cancel_requrest_data
local Completer = {
   request_id = 0,
   other_docs = {},
   cancel_requrest_data = {
      request_id = -1,
   },
}

-- Auxiliary functions ------------------------------------- {{{1

---Returns values of `'shiftwidth'` and `'expandtab'` in the current buffer.
---@return editor_options
local function get_editor_opts()
   return {
      tab_size = fn.shiftwidth(),
      insert_spaces = vim.bo.expandtab,
   }
end

-- Completer methods --------------------------------------- {{{1

---Returns current completion item or nil if there isn't one.
---@private
---@return compl.item|nil
function Completer:curr_item()
   if state:valid() and state.data.index <= #state.data.items then
      return state.data.items[state.data.index]
   end
end

function Completer:scheduled_display()
   vim.schedule(function()
      local resend_request = renderer:display()
      if resend_request then
         self:request()
      end
   end)
end

---Returns `true` if completion for current buffer is enabled.
---@return boolean
function Completer:enabled()
   return state.allowed_encoding and options.status() == 0
end

---Cycles completions by amount `n`, wraps around if necessary.
---Use negative value to cycle backwards.
---@param n integer amount to cycle
function Completer:cycle(n)
   local curr_item = self:curr_item()
   if not curr_item then
      return
   end

   state.data.index = state.data.index + (n or 1)
   local items_len = #state.data.items
   -- wrap on boundaries
   if state.data.index > items_len then
      state.data.index = 1
   elseif state.data.index < 1 then
      state.data.index = items_len
   end

   self:scheduled_display()
end

---Cycles completions or request to complete if there isn't one.
---@param n integer amount to cycle
function Completer:cycle_or_complete(n)
   if self:curr_item() then
      self:cycle(n)
   else
      -- `true` requires to skip early return in self:initiate(), which prevents suggestion
      -- to show up when manual completion is enabled
      self:initiate(true)
   end
end

---Handles a response from the server.
---@private
---@param r response
function Completer:handle_response(r)
   state.request_status = REQUEST_STATUS.completed
   renderer:update_label()

   -- finish if the context has changed
   if vim.tbl_isempty(state.data) then
      return
   end

   local resp_str = table.concat(r.out)
   local ok, response = pcall(json.decode, resp_str)
   if not ok then
      log.error("Invalid response from server")
      log.error(resp_str)
      log.error("stderr: " .. vim.inspect(r.err))
      log.error(debug.traceback(response))
      return
   end

   state.data.items = response.completionItems
   state.data.index = 1

   self:scheduled_display()
end

---Accepts a suggestion till regex match end.
---@private
---@param regex string
function Completer:accept_regex(regex)
   if not state.active then
      return
   end

   local text = ""
   for _, item in ipairs(state.inline) do
      text = text .. item.prefix .. item.text
   end

   if text ~= "" then
      text = fn.matchstr(text, regex)
      if #state.inline > 1 then
         local text_len = #text
         local combined_text = state.inline[1].text
         if text_len > #combined_text then
            local combined_prefix = ""
            for i = 2, #state.inline do
               local item = state.inline[i]
               combined_text = combined_text .. item.prefix
               local combined_len = #combined_text
               if text_len >= combined_len then
                  combined_prefix = combined_prefix .. item.prefix
                  combined_text = combined_text .. item.text
               else
                  local index = text_len - combined_len
                  combined_prefix = combined_prefix .. item.prefix:sub(1, index)
                  break
               end
            end
            local prefix_chars = fn.strchars(combined_prefix)
            if prefix_chars > 0 then
               local dels =
                  nvim_replace_termcodes(string.rep("<Del>", prefix_chars), true, false, true)
               nvim_feedkeys(dels, "n", false)
            end
         end
      end
   else
      text = state.block.text or ""
      if text == "" then
         return
      end

      text = vim.split(text, "\n")[1]
      text = fn.matchstr(text, regex)
      local lnum1 = state.pos[1] + 1
      utils.set_lines(lnum1, lnum1, { "" })
      utils.set_cursor({ lnum1, 0 })
   end
   nvim_feedkeys(text, "nt", true)
end

---Accepts a suggestion till the end of the word.
function Completer:accept_word()
   self:accept_regex([[.\{-}\%(\>\|$\)]])
end

---Accepts a suggestion till the end of the line.
function Completer:accept_line()
   self:accept_regex([[.*]])
end

---@private
---Constructs and sends a request to the server only when in an appropriate state.
function Completer:request()
   if not (server.port and state.active) or state.request_status == REQUEST_STATUS.pending then
      return
   end

   state.request_status = REQUEST_STATUS.pending
   renderer:update_label()

   self.request_id = self.request_id + 1
   state.completion_request_data.metadata.request_id = self.request_id
   state.completion_request_data.document =
      doc.get(nvim_get_current_buf(), vim.bo.filetype, -1, state.pos)
   state.completion_request_data.other_documents = self.other_docs
   state.completion_request_data.editor_options = get_editor_opts()

   server:request("GetCompletions", state.completion_request_data, function(r)
      self:handle_response(r)
   end)

   -- setting 'duplicate' id so it can be processed correctly by
   -- self:handle_response() and renderer:clear() methods
   state.data.id = self.request_id
end

function Completer:scheduled_request()
   vim.schedule(function()
      self:request()
   end)
end

---Initiates a completion.
---@param omit_manual? boolean
function Completer:initiate(omit_manual)
   renderer:update()
   self:clear()

   if options.manual and not omit_manual then
      renderer:clear()
      return
   end

   if options.debounce then
      state:stop_debounce_timer()
      state.debounce_timer:start(120, 0, function()
         self:scheduled_request()
      end)
   else
      self:scheduled_request()
   end
end

---Completes the current suggestion.
function Completer:accept()
   if not state.active then
      return
   end

   local curr_item = self:curr_item()
   if not curr_item then
      return
   end

   local parts = curr_item.completionParts or {}
   local block ---@type string[]
   local inline = false

   for _, part in ipairs(parts) do
      if part.type == PART.inline then
         inline = true
      elseif part.type == PART.block then
         block = vim.split(part.text, "\n")
      end
   end

   if not (inline or block) then
      return
   end

   state.accept_request_data.completion_id = curr_item.completion.completionId
   server:request("AcceptCompletion", state.accept_request_data)

   local pos ---@type pos
   local lnum = state.pos[1] + 1
   if block then
      local block_len = #block
      local delta = curr_item.suffix and curr_item.suffix.deltaCursorOffset or 0
      local last_line = block[block_len]
      local col = #last_line + delta
      if col > 0 then
         pos = { lnum + block_len - 1, col }
      else
         pos = { lnum + block_len - 2, vim.v.maxcol }
      end
   end

   if inline then
      self:accept_line()
   end
   -- scheduling prevents pasting block before accept_line(),
   -- because accept_line() using some type of scheduling too with nvim_feedkeys()
   vim.schedule(function()
      renderer:clear(true)
      if block then
         utils.set_lines(lnum, lnum, block)
         utils.set_cursor(pos)
         -- required to update label position
         state.pos = pos
      end
   end)
end

---Clears completion state. When `force` is true, the inline and block
---virtual text is cleared too.
---@param force? boolean
function Completer:clear(force)
   if force or options.debounce or state.request_status ~= REQUEST_STATUS.pending then
      state.request_status = REQUEST_STATUS.none
      if options.debounce then
         state:stop_debounce_timer()
      end
      -- Cancel request if there is one
      if not vim.tbl_isempty(state.data) then
         if state.data.id and state.data.id > 0 then
            self.cancel_requrest_data.request_id = state.data.id
            server:request("CancelRequest", self.cancel_requrest_data)
         end
         state.data = {}
      end
   end

   if force then
      renderer:clear(true)
   end
end

-- }}}1

return Completer

-- vim: fdm=marker
