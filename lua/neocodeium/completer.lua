-- Imports ------------------------------------------------- {{{1

local log = require("neocodeium.log")
local doc = require("neocodeium.doc")
local utils = require("neocodeium.utils")
local options = require("neocodeium.options").options
local server = require("neocodeium.server")
local renderer = require("neocodeium.renderer")
local state = require("neocodeium.state")
local PART = require("neocodeium.enums").PART

local fn = vim.fn
local json = vim.json

local nvim_feedkeys = vim.api.nvim_feedkeys
local nvim_get_current_buf = vim.api.nvim_get_current_buf
local nvim_replace_termcodes = vim.api.nvim_replace_termcodes

-- Completer ----------------------------------------------- {{{1

---@class compl.cancel_requrest_data
---@field request_id integer

---@class Completer
---@field request_id integer
---@field request_is_valid boolean
---@field other_docs document[]
---@field cancel_requrest_data compl.cancel_requrest_data
local Completer = {
   request_id = 0,
   request_is_valid = false,
   other_docs = {},
   cancel_requrest_data = {
      request_id = -1,
   },
}

-- Auxiliary functions ------------------------------------- {{{1

---Returns inline and block texts of completion item
---@param item compl.item
---@return string, string
local function get_inline_and_block(item)
   local inline, block
   for _, part in ipairs(item.completionParts) do
      if part.type == PART.inline_mask then
         inline = (part.prefix or "") .. part.text
      elseif part.type == PART.block then
         block = part.text
      end
   end
   return inline, block
end

---Adds completion items to `state.data.items`
---@param compl_items compl.item[]
local function add_state_data_items(compl_items)
   if not compl_items then
      return
   end

   local matching_inline, matching_block = get_inline_and_block(state.data.items[1])
   for _, item in ipairs(compl_items) do
      local item_inline, item_block = get_inline_and_block(item)
      local inline_text = state.inline[1] and state.inline[1].text
      if options.single_line.enabled and inline_text == "" then
         if item_block ~= matching_block then
            table.insert(state.data.items, item)
         end
      else
         if item_inline ~= matching_inline or item_block ~= matching_block then
            table.insert(state.data.items, item)
         end
      end
   end
end

---Returns length of the common prefix of two strings
---@param s1 string
---@param s2 string
---@return integer
local function same_prefix_index(s1, s2)
   local len = math.min(#s1, #s2)
   for i = 1, len do
      if s1:sub(i, i) ~= s2:sub(i, i) then
         return i - 1
      end
   end
   return len
end

---@param len integer
---@param idx integer
---@param col col
---@return integer
local function calc_inline_delta(len, idx, col)
   local result = 0
   if col > len then
      result = col - len
   elseif col < len then
      result = idx >= len and idx - len or col - len
   end
   return result
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

function Completer:update()
   if not state.active then
      renderer:clear(true)
      return
   end

   local items = state.data.items or {}
   local index = state.data.index or 1
   local item = items[index] or {}
   local parts = item.completionParts or {}

   if utils.is_empty(parts) then
      return
   end

   -- When only block part is present and text was changed compared to when
   -- request was send dispatch a new request
   if not state.curline_text:match("^%s*$") and item.completion.text:match("^\n") then
      self:request()
      return
   end

   local inline = {} ---@type inline_content[]
   local block ---@type string?
   local lnum, col = unpack(state.pos)
   local cummulative_cols = 0
   local delta = 0

   -- Get inline content and block text
   for i, part in ipairs(parts) do
      -- process only correct parts
      if lnum == (tonumber(part.line) or 0) then
         local text = part.text

         if part.type == PART.inline then
            local prefix = part.prefix or ""
            local prefix_len = #prefix
            local column = prefix_len + cummulative_cols
            cummulative_cols = column

            if i == 1 then
               local compl_line = prefix .. text
               local match_prefix_idx = same_prefix_index(compl_line, state.curline_text)
               -- When actual text doesn't match prefix dispatch a new request
               if match_prefix_idx ~= col then
                  self:request()
                  return
               end

               delta = calc_inline_delta(prefix_len, match_prefix_idx, col)
               if delta < 0 then
                  text = prefix:sub(delta) .. text
               elseif delta > 0 then
                  text = text:sub(delta + 1)
               end
               prefix = ""
            end
            table.insert(
               inline,
               { lnum = lnum, col = column + delta, text = text, prefix = prefix }
            )
         elseif part.type == PART.block then
            block = text
         end
      else
         self:request()
         return
      end
   end

   renderer:display(inline, block)
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

   self:update()
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
   state.pending = false
   renderer:update_label()

   if not self.request_is_valid then
      return
   end
   self.request_is_valid = false

   local resp_str = table.concat(r.out)
   local ok, response = pcall(json.decode, resp_str)
   if not ok then
      log.error(
         "Invalid response from server\n"
            .. resp_str
            .. "\nstderr: "
            .. vim.inspect(r.err)
            .. "\n"
            .. debug.traceback(response)
      )
      return
   end

   if state.matching and (state.data.items and #state.data.items == 1) then
      add_state_data_items(response.completionItems)
   else
      state.data.items = response.completionItems
   end
   state.data.index = 1
   state.matching = false

   vim.schedule(function()
      self:update()
   end)
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

-- TODO: better word boundaries
---Accepts a suggestion till the end of the word.
function Completer:accept_word()
   state.matching = true
   self:accept_regex([[.\{-}\%(\>\|$\)]])
end

---Accepts a suggestion till the end of the line.
function Completer:accept_line()
   state.matching = true
   self:accept_regex([[.*]])
end

---@private
---Constructs and sends a request to the server only when in an appropriate state.
function Completer:request()
   if not (server.port and state.active) or state.pending then
      return
   end

   state.pending = true
   renderer:update_label()

   self.request_id = self.request_id + 1
   state.completion_request_data.metadata.request_id = self.request_id
   state.completion_request_data.document =
      doc.get(nvim_get_current_buf(), vim.bo.filetype, -1, state.pos)
   state.completion_request_data.other_documents = self.other_docs

   self.request_is_valid = true
   server:request("GetCompletions", state.completion_request_data, function(r)
      self:handle_response(r)
   end)
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

   if options.single_line.enabled and block and not state.block.visible then
      self:accept_line()
      return
   end

   state.accept_request_data.completion_id = curr_item.completion.completionId
   server:request("AcceptCompletion", state.accept_request_data)

   local pos ---@type pos
   local lnum = state.pos[1] + 1
   if block then
      local block_len = #block
      -- XXX: is codeium completion item still has suffix?
      local delta = curr_item.suffix and curr_item.suffix.deltaCursorOffset or 0
      local last_line = block[block_len]
      local col = #last_line + delta
      if col > 0 then
         pos = { lnum + block_len - 1, col }
      else
         pos = { lnum + block_len - 2, vim.v.maxcol }
      end
   end

   if inline and not (options.single_line.enabled and block) then
      self:accept_line()
   end
   -- scheduling prevents pasting block before accept_line(),
   -- because accept_line() using some type of scheduling too with nvim_feedkeys()
   vim.schedule(function()
      renderer:clear(true)
      if block then
         utils.set_lines(lnum, lnum, block)
         utils.set_cursor(pos)
         state.pos = pos -- required to update label position
      end
   end)
end

---Clears completion state. When `force` is true, the inline and block
---virtual text is cleared too.
---@param force? boolean
function Completer:clear(force)
   if force or options.debounce or not state.pending then
      state.pending = false
      if options.debounce then
         state:stop_debounce_timer()
      end
      -- Cancel request if there is one
      if not vim.tbl_isempty(state.data) then
         if self.request_is_valid then
            self.cancel_requrest_data.request_id = self.request_id
            server:request("CancelRequest", self.cancel_requrest_data)
            self.request_is_valid = false
         end
         if state.matching and state.data.items then
            state.data = {
               items = { state.data.items[state.data.index] },
               index = 1,
            }
         else
            state.data = {}
         end
      end
   end

   if force then
      renderer:clear(true)
   end
end

-- }}}1

return Completer

-- vim: fdm=marker
