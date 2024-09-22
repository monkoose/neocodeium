-- Imports ------------------------------------------------- {{{1

local log = require("neocodeium.log")
local doc = require("neocodeium.doc")
local utils = require("neocodeium.utils")
local options = require("neocodeium.options").options
local types = require("neocodeium._types")
local server = require("neocodeium.server")
local events = require("neocodeium.events")

local fn = vim.fn
local uv = vim.uv
local json = vim.json

local nvim_feedkeys = vim.api.nvim_feedkeys
local nvim_get_current_buf = vim.api.nvim_get_current_buf
local nvim_replace_termcodes = vim.api.nvim_replace_termcodes
local nvim_get_current_line = vim.api.nvim_get_current_line
local nvim_buf_set_extmark = vim.api.nvim_buf_set_extmark
local nvim_get_hl_id_by_name = vim.api.nvim_get_hl_id_by_name
local nvim_create_namespace = vim.api.nvim_create_namespace
local nvim_buf_del_extmark = vim.api.nvim_buf_del_extmark
local nvim_buf_clear_namespace = vim.api.nvim_buf_clear_namespace

local hlgroup = nvim_get_hl_id_by_name("NeoCodeiumSuggestion")
local ns = nvim_create_namespace("neocodeium_compl")

-- Completer ----------------------------------------------- {{{1

---@enum compl.status
local status = {
   none = 0,
   pending = 1,
   completed = 2,
}

---@class inline
---@field id? integer
---@field text? string
---@field prefix? string

---@class block
---@field text? string
---@field id? integer

---@class label
---@field enabled boolean
---@field id? integer

---@class Completer
---@field pos pos
---@field tick integer
---@field clear_timer uv.uv_timer_t
---@field fulltext string
---@field label label
---@field inline inline[]
---@field block block
---@field data compl.data
---@field status compl.status
---@field debounce_timer uv.uv_timer_t
---@field request_id integer
---@field allowed_encoding boolean
---@field other_docs document[]
local Completer = {
   data = {},
   status = status.none,
   debounce_timer = assert(uv.new_timer()),
   request_id = 0,
   allowed_encoding = false,
   other_docs = {},
   pos = { 0, 0 },
   clear_timer = assert(uv.new_timer()),
   fulltext = "",
   label = { enabled = false },
   inline = {},
   block = {},
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

---@param id extmark_id
---@param text string
---@param lnum lnum
local function show_label(id, text, lnum)
   return nvim_buf_set_extmark(0, ns, lnum, 0, {
      id = id,
      virt_text = { { text, "NeoCodeiumLabel" } },
      virt_text_win_col = -1 - #text,
   })
end

---Adds virtual text into the `lnum` line number and `col` column.
---If `id` is nil then a new id will be generated.
---@param id? extmark_id
---@param str string text to display
---@param lnum lnum
---@param col col
---@return extmark_id
local function show_inline(id, str, lnum, col)
   return nvim_buf_set_extmark(0, ns, lnum, col, {
      id = id,
      virt_text_pos = "inline",
      virt_text = { { str, hlgroup } },
      undo_restore = false,
      strict = false,
   })
end

---Returns `str` with leading tabs converted to spaces.
---@param str string
---@return string
local function leading_tabs_to_spaces(str)
   ---@diagnostic disable-next-line: redundant-return-value
   return str:gsub("^\t*", function(m)
      -- faster than string.rep
      return string.sub(
         [[                                                         ]],
         1,
         #m * fn.shiftwidth()
      )
   end)
end

---Adds virtual text below the line with `lnum` number.
---If `id` is nil then a new id will be generated.
---@param id? extmark_id
---@param text string text to display, will be split into lines at "\n"
---@param lnum lnum
---@return extmark_id
local function show_block(id, text, lnum)
   local block_lines = {}
   -- XXX: should it have {trimempty = true}?
   for line in vim.gsplit(text, "\n") do
      table.insert(block_lines, { { leading_tabs_to_spaces(line), hlgroup } })
   end

   return nvim_buf_set_extmark(0, ns, lnum, 0, {
      id = id,
      virt_lines = block_lines,
      undo_restore = false,
      strict = false,
   })
end

---Deletes virtual text by it's extmark `id`
---@param id extmark_id
---@return boolean true if deleted
local function delete_virttext(id)
   return nvim_buf_del_extmark(0, ns, id)
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

---Returns `true` if completion data is present and valid.
---@return boolean
function Completer:valid()
   return self.data.items ~= nil and self.data.index ~= nil
end

---Returns current completion item or nil if there isn't one.
---@private
---@return compl.item|nil
function Completer:curr_item()
   if self:valid() and self.data.index <= #self.data.items then
      return self.data.items[self.data.index]
   end
end

---Returns `true` if completion for current buffer is enabled.
---@return boolean
function Completer:enabled()
   return self.allowed_encoding and options.status() == 0
end

function Completer:update_label()
   if utils.is_insert() and utils.is_empty(self.inline) and not self.block.text then
      vim.schedule(function()
         self:display_label()
      end)
   end
end

---@private
---@param contents inline_content[]
function Completer:display_inline(contents)
   -- clear extra inline items
   local contents_len = #contents
   local leftover_ids = #self.inline - contents_len
   if leftover_ids > 0 then
      for _ = 1, leftover_ids do
         local item = table.remove(self.inline)
         delete_virttext(item.id)
      end
   end
   -- change inline virtual text
   if contents_len > 0 then
      for i, c in ipairs(contents) do
         if not self.inline[i] then
            self.inline[i] = {}
         end
         self.inline[i].text = c.text
         self.inline[i].prefix = c.prefix
         self.inline[i].id = show_inline(self.inline[i].id, c.text, c.lnum, c.col)
      end
   end
end

---@private
---@param lnum lnum
---@param text? string
function Completer:display_block(text, lnum)
   if text then
      if not self.block.id or self.block.text ~= text then
         self.block.text = text
         self.block.id = show_block(self.block.id, text, lnum)
      end
   else
      self:clear_block()
   end
end

---@private
function Completer:display_label()
   if not (options.show_label and self.label.enabled) then
      return
   end

   local lnum = self.pos[1]
   if self.status == status.pending then
      self.label.id = show_label(self.label.id, " * ", lnum)
   elseif utils.is_empty(self.data.items) then
      self.label.id = show_label(self.label.id, " 0 ", lnum)
   else
      self.label.id = show_label(self.label.id, self.data.index .. "/" .. #self.data.items, lnum)
   end
end

---Displays completion item
function Completer:display()
   if not utils.is_insert() then
      self:clear_all(true)
      return
   end

   local lnum, col = unpack(self.pos)
   local items = self.data.items or {}
   local index = self.data.index or 1
   local item = items[index] or {}
   local parts = item.completionParts or {}

   if utils.is_empty(parts) then
      return
   end

   -- When only block part is present and text was changed compared to when
   -- request was sent, return false, so it will dispatch new request
   if not self.fulltext:match("^%s*$") and item.completion.text:match("^\n") then
      self:request()
      return
   end

   local block_text ---@type string?
   local inline_contents = {} ---@type inline_content[]
   local cummulative_cols = 0
   local delta = 0

   for i, part in ipairs(parts) do
      -- process only correct parts
      if lnum == (tonumber(part.line) or 0) then
         local text = part.text

         if part.type == types.part.inline then
            local prefix = part.prefix or ""
            local prefix_len = #prefix
            local column = prefix_len + cummulative_cols
            cummulative_cols = column

            if i == 1 then
               local compl_line = prefix .. text
               local match_prefix_idx = same_prefix_index(compl_line, self.fulltext)
               -- When actual text doesn't match prefix return false, so it will
               -- dispatch new request for the completion
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
               inline_contents,
               { lnum = lnum, col = column + delta, text = text, prefix = prefix }
            )
         elseif part.type == types.part.block then
            block_text = text
         end
      end
   end

   self.clear_timer:stop()
   self:display_inline(inline_contents)
   self:display_block(block_text, lnum)
   if block_text or #inline_contents > 0 then
      self:display_label()
   end
   events.emit("NeoCodeiumCompletionDisplayed", nil, true)
end

---@private
function Completer:start_clear_timer()
   if not self.clear_timer:is_active() then
      self.clear_timer:start(
         350,
         0,
         vim.schedule_wrap(function()
            self:clear_all()
         end)
      )
   end
end

---@private
function Completer:update_forward_line()
   if self.block.text and self.block.text ~= "" then
      -- find if block.text has multiple lines
      local index = self.block.text:find("\n")
      self.inline = { { prefix = "" } }
      local lnum, col = unpack(self.pos)
      if index then
         -- starting index `self.pos[2] + 1` is start of the line with indentation
         -- prevents shifting of the inline text
         self.inline[1].text = self.block.text:sub(col + 1, index - 1)
         self.block.text = self.block.text:sub(index + 1)
         -- self.block.id already exists, no need to set it
         show_block(self.block.id, self.block.text, lnum)
      else
         self.inline[1].text = self.block.text:sub(col + 1)
         self:clear_block()
         -- required to update label position
         nvim_buf_set_extmark(0, ns, self.pos[1], 0, {
            id = self.label.id,
            virt_text = { { " 0 ", "NeoCodeiumLabel" } },
            virt_text_win_col = -4,
         })
      end
      self.inline[1].id = show_inline(nil, self.inline[1].text, lnum, col)
   end
   self:start_clear_timer()
end

---@private
function Completer:update_backward_line()
   if #self.inline == 1 then
      if self.block.text then
         self.block.text = self.inline[1].text .. "\n" .. self.block.text
      else
         self.block.text = self.inline[1].text
      end
      self:clear_inline()
      -- self.block.id could be nil, so we need to set it
      self.block.id = show_block(self.block.id, self.block.text, self.pos[1])
   end
   self:start_clear_timer()
end

---@param prev_pos pos
---@param new_fulltext string
function Completer:update_horz_move(prev_pos, new_fulltext)
   local lnum, col = unpack(self.pos)
   local prev_col = prev_pos[2]
   local horz_move = col - prev_col
   local first_inline = self.inline[1]

   if horz_move >= 0 then -- added some text
      if horz_move > #first_inline.text then
         self:clear_inline()
         self:start_clear_timer()
      else
         local prefix = first_inline.text:sub(1, horz_move)
         self.inline[1].text = first_inline.text:sub(horz_move + 1)
         show_inline(first_inline.id, first_inline.text, lnum, col)
         if new_fulltext:sub(prev_col) ~= prefix then
            self:start_clear_timer()
         end
      end
   else -- deleted some text
      if self.fulltext:match("^%s*$") then
         self:clear_inline()
         self:start_clear_timer()
      else
         local prefix = self.fulltext:sub(col + 1, col - horz_move)
         self.inline[1].text = prefix .. first_inline.text
         show_inline(first_inline.id, first_inline.text, lnum, col)
         self.clear_timer:stop()
         self:start_clear_timer()
      end
   end
end

function Completer:update()
   local prev_pos = self.pos
   self.pos = utils.get_cursor()
   local vert_move = self.pos[1] - prev_pos[1]

   if self.tick == vim.b.changedtick or math.abs(vert_move) > 1 then
      self.clear_timer:stop()
      self:clear_all()
      self.fulltext = nvim_get_current_line()
   else
      local fulltext = nvim_get_current_line()
      if vert_move == 1 then
         self.clear_timer:stop()
         self:update_forward_line()
      elseif vert_move == -1 then
         self.clear_timer:stop()
         self:update_backward_line()
      else -- cursor movement happened on the same line
         if not self.inline[1] then
            self:clear_inline()
         else
            self:update_horz_move(prev_pos, fulltext)
         end
      end
      self.fulltext = fulltext
   end

   self.tick = vim.b.changedtick
end

---Clears the block virtual text and removes block.id cache
function Completer:clear_block()
   if self.block.id == nil then
      return
   end

   delete_virttext(self.block.id)
   self.block.text = nil
   self.block.id = nil
end

---Clears the inline virtual text and resets `self.inline` to empty table
function Completer:clear_inline()
   for _, item in ipairs(self.inline) do
      delete_virttext(item.id)
   end
   self.inline = {}
end

---Clears the label virtual text and removes label.id cache
function Completer:clear_label()
   if self.label.id == nil then
      return
   end

   delete_virttext(self.label.id)
   self.label.id = nil
end

---Clears plugin's namespace and resets cache
---@param with_reset? boolean
function Completer:clear_all(with_reset)
   if with_reset then
      self.clear_timer:stop()
      nvim_buf_clear_namespace(0, ns, 0, -1)
      self.label.id = nil
      self.inline = {}
      self.block.id = nil
      self.block.text = nil
      self.fulltext = ""
      events.emit("NeoCodeiumCompletionCleared", nil, true)
   else
      -- self:clear_label()
      self:clear_inline()
      self:clear_block()
   end
end

---Cycles completions by amount `n`, wraps around if necessary.
---Use negative value to cycle backwards.
---@param n integer amount to cycle
function Completer:cycle(n)
   local curr_item = self:curr_item()
   if not curr_item then
      return
   end

   self.data.index = self.data.index + (n or 1)
   local items_len = #self.data.items
   -- wrap on boundaries
   if self.data.index > items_len then
      self.data.index = 1
   elseif self.data.index < 1 then
      self.data.index = items_len
   end

   vim.schedule(function()
      self:display()
   end)
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
   -- finish if the context has changed
   if vim.tbl_isempty(self.data) then
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

   self.data.items = response.completionItems
   self.data.index = 1

   vim.schedule(function()
      self:display()
   end)
end

---Accepts a suggestion till regex match end.
---@private
---@param regex string
function Completer:accept_regex(regex)
   if not utils.is_insert() then
      return
   end

   local text = ""
   for _, item in ipairs(self.inline) do
      text = text .. item.prefix .. item.text
   end

   if text ~= "" then
      text = fn.matchstr(text, regex)
      if #self.inline > 1 then
         local text_len = #text
         local combined_text = self.inline[1].text
         if text_len > #combined_text then
            local combined_prefix = ""
            for i = 2, #self.inline do
               local item = self.inline[i]
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
      text = self.block.text or ""
      if text == "" then
         return
      end

      text = vim.split(text, "\n")[1]
      text = fn.matchstr(text, regex)
      local lnum1 = self.pos[1] + 1
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
   if
      not server.port
      or self.status == status.pending
      or not (self:enabled() and utils.is_insert())
   then
      return
   end

   self.status = status.pending
   self:update_label()

   self.request_id = self.request_id + 1
   local curr_bufnr = nvim_get_current_buf()
   local pos = self.pos
   local metadata = server.metadata
   metadata.request_id = self.request_id
   local data = {
      metadata = metadata,
      editor_options = get_editor_opts(),
      document = doc.get(curr_bufnr, vim.bo.filetype, -1, pos),
      other_documents = self.other_docs,
   }

   server:request("GetCompletions", data, function(r)
      self.status = status.completed
      self:update_label()
      self:handle_response(r)
   end)

   -- setting 'duplicate' id so it can be processed correctly by
   -- handle_response() and clear() methods
   self.data.id = self.request_id
end

---Clears completion state. When `force` is true, the inline and block
---virtual text is cleared too.
---@param force? boolean
function Completer:clear(force)
   if force or options.debounce or self.status ~= status.pending then
      self.status = status.none
      if options.debounce and self.debounce_timer:is_active() then
         self.debounce_timer:stop()
      end
      -- Cancel request if there is one
      if not vim.tbl_isempty(self.data) then
         if self.data.id and self.data.id > 0 then
            server:request("CancelRequest", { request_id = self.data.id })
         end
         self.data = {}
      end
   end

   if force then
      self:clear_all(true)
   end
end

---Initiates a completion.
---@param omit_manual? boolean
function Completer:initiate(omit_manual)
   self:update()
   self:clear()

   if options.manual and not omit_manual then
      self:clear_all()
      return
   end

   if options.debounce then
      if self.debounce_timer:is_active() then
         self.debounce_timer:stop()
      end
      self.debounce_timer:start(
         120,
         0,
         vim.schedule_wrap(function()
            self:request()
         end)
      )
   else
      vim.schedule(function()
         self:request()
      end)
   end
end

---Completes the current suggestion.
function Completer:accept()
   if not utils.is_insert() then
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
      if part.type == types.part.inline then
         inline = true
      elseif part.type == types.part.block then
         block = vim.split(part.text, "\n")
      end
   end

   if not (inline or block) then
      return
   end

   server:request("AcceptCompletion", {
      metadata = server.metadata,
      completion_id = curr_item.completion.completionId,
   })

   local pos ---@type pos
   local lnum = self.pos[1] + 1
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
      self:clear_all(true)
      if block then
         utils.set_lines(lnum, lnum, block)
         utils.set_cursor(pos)
         -- required to update label position
         self.pos = pos
      end
   end)
end
-- }}}1

return Completer

-- vim: fdm=marker
