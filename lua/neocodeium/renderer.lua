-- Imports ------------------------------------------------- {{{1

local options = require("neocodeium.options").options
local events = require("neocodeium.events")
local server = require("neocodeium.server")
local state = require("neocodeium.state")
local utils = require("neocodeium.utils")
local PART = require("neocodeium.enums").PART
local REQUEST_STATUS = require("neocodeium.enums").REQUEST_STATUS

local fn = vim.fn
local uv = vim.uv

local nvim_buf_set_extmark = vim.api.nvim_buf_set_extmark
local nvim_buf_del_extmark = vim.api.nvim_buf_del_extmark
local nvim_buf_clear_namespace = vim.api.nvim_buf_clear_namespace
local nvim_get_current_line = vim.api.nvim_get_current_line

local hlgroup = vim.api.nvim_get_hl_id_by_name("NeoCodeiumSuggestion")
local ns = vim.api.nvim_create_namespace("neocodeium_compl")

-- Renderer ------------------------------------------------ {{{1

---@class label
---@field enabled boolean
---@field id? integer

---@class cancel_requrest_data
---@field request_id integer

---@class Renderer
---@field clear_timer uv.uv_timer_t
---@field label label
---@field fulltext string
---@field changedtick integer
---@field cancel_requrest_data cancel_requrest_data
local Renderer = {
   clear_timer = assert(uv.new_timer()),
   label = { enabled = false },
   fulltext = "",
   changedtick = -1,
   cancel_requrest_data = {
      request_id = -1,
   },
}

-- Auxiliary functions ------------------------------------- {{{1

---Deletes virtual text by it's extmark `id`
---@param id extmark_id
---@return boolean true if deleted
local function delete_virttext(id)
   return nvim_buf_del_extmark(0, ns, id)
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
   str = str:gsub("^\t*", function(m)
      return string.rep(" ", #m * fn.shiftwidth())
   end)
   return str
end

---Adds virtual text below the line with `lnum` number.
---If `id` is nil then a new id will be generated.
---@param id? extmark_id
---@param text string text to display, will be split into lines at "\n"
---@param lnum lnum
---@return extmark_id
local function show_block(id, text, lnum)
   local block_lines = {}
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

-- Renderer methods ---------------------------------------- {{{1

function Renderer:update_label()
   vim.schedule(function()
      if state.active and utils.is_empty(state.inline) and not state.block.text then
         self:display_label()
      end
   end)
end

---@private
function Renderer:start_clear_timer()
   if not self.clear_timer:is_active() then
      self.clear_timer:start(350, 0, function()
         self:clear_all(false, true)
      end)
   end
end

---@private
---@param contents inline_content[]
function Renderer:display_inline(contents)
   -- clear extra inline items
   local contents_len = #contents
   local leftover_ids = #state.inline - contents_len
   if leftover_ids > 0 then
      for _ = 1, leftover_ids do
         local item = table.remove(state.inline)
         delete_virttext(item.id)
      end
   end
   -- change inline virtual text
   if contents_len > 0 then
      for i, c in ipairs(contents) do
         if not state.inline[i] then
            state.inline[i] = {}
         end
         state.inline[i].text = c.text
         state.inline[i].prefix = c.prefix
         state.inline[i].id = show_inline(state.inline[i].id, c.text, c.lnum, c.col)
      end
   end
end

---@private
---@param lnum lnum
---@param text? string
function Renderer:display_block(text, lnum)
   if text then
      if not state.block.id or state.block.text ~= text then
         state.block.text = text
         state.block.id = show_block(state.block.id, text, lnum)
      end
   else
      self:clear_block()
   end
end

---@private
function Renderer:display_label()
   if not (options.show_label and self.label.enabled) then
      return
   end

   local lnum = state.pos[1]
   if state.request_status == REQUEST_STATUS.pending then
      self.label.id = show_label(self.label.id, " * ", lnum)
   elseif utils.is_empty(state.data.items) then
      self.label.id = show_label(self.label.id, " 0 ", lnum)
   else
      self.label.id = show_label(self.label.id, state.data.index .. "/" .. #state.data.items, lnum)
   end
end

---Displays completion item, if request to the server should be resend returns true
---@return boolean
function Renderer:display()
   if not state.active then
      self:clear_all(true)
      return false
   end

   local lnum, col = unpack(state.pos)
   local items = state.data.items or {}
   local index = state.data.index or 1
   local item = items[index] or {}
   local parts = item.completionParts or {}

   if utils.is_empty(parts) then
      return false
   end

   -- When only block part is present and text was changed compared to when
   -- request was sent, return false, so it will dispatch new request
   if not self.fulltext:match("^%s*$") and item.completion.text:match("^\n") then
      return true
   end

   local block_text ---@type string?
   local inline_contents = {} ---@type inline_content[]
   local cummulative_cols = 0
   local delta = 0

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
               local match_prefix_idx = same_prefix_index(compl_line, self.fulltext)
               -- When actual text doesn't match prefix return false, so it will
               -- dispatch new request for the completion
               if match_prefix_idx ~= col then
                  return true
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
         elseif part.type == PART.block then
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
   return false
end

---Clears the block virtual text and removes block.id cache
function Renderer:clear_block()
   if state.block.id == nil then
      return
   end

   delete_virttext(state.block.id)
   state.block.text = nil
   state.block.id = nil
end

---Clears the inline virtual text and resets `state.inline` to empty table
function Renderer:clear_inline()
   for _, item in ipairs(state.inline) do
      delete_virttext(item.id)
   end
   state.inline = {}
end

---Clears the label virtual text and removes label.id cache
function Renderer:clear_label()
   if self.label.id == nil then
      return
   end

   delete_virttext(self.label.id)
   self.label.id = nil
end

---Clears completion state. When `force` is true, the inline and block
---virtual text is cleared too.
---@param force? boolean
function Renderer:clear(force)
   if force or options.debounce or state.request_status ~= REQUEST_STATUS.pending then
      state.request_status = REQUEST_STATUS.none
      if options.debounce and state.debounce_timer:is_active() then
         state.debounce_timer:stop()
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
      self:clear_all(true)
   end
end

---Clears plugin's namespace and resets cache
---@param with_reset? boolean
---@param scheduled? boolean
function Renderer:clear_all(with_reset, scheduled)
   if with_reset then
      self.clear_timer:stop()
      self.label.id = nil
      state.inline = {}
      state.block.id = nil
      state.block.text = nil
      self.fulltext = ""
      if scheduled then
         vim.schedule(function()
            nvim_buf_clear_namespace(0, ns, 0, -1)
         end)
      else
         nvim_buf_clear_namespace(0, ns, 0, -1)
      end
      events.emit("NeoCodeiumCompletionCleared", nil, true)
   else
      if scheduled then
         vim.schedule(function()
            self:clear_inline()
            self:clear_block()
         end)
      else
         self:clear_inline()
         self:clear_block()
      end
   end
end

---@private
function Renderer:update_forward_line()
   if not utils.is_empty(state.block.text) then
      -- find if block.text has multiple lines
      local index = state.block.text:find("\n")
      state.inline = { { prefix = "" } }
      local lnum, col = unpack(state.pos)
      if index then
         -- starting index `state.pos[2] + 1` is start of the line with indentation
         -- prevents shifting of the inline text
         state.inline[1].text = state.block.text:sub(col + 1, index - 1)
         state.block.text = state.block.text:sub(index + 1)
         -- state.block.id already exists, no need to set it
         show_block(state.block.id, state.block.text, lnum)
      else
         state.inline[1].text = state.block.text:sub(col + 1)
         self:clear_block()
         -- required to update label position
         if options.show_label and self.label.enabled then
            show_label(self.label.id, " 0 ", state.pos[1])
         end
      end
      state.inline[1].id = show_inline(nil, state.inline[1].text, lnum, col)
   end
   self:start_clear_timer()
end

---@private
function Renderer:update_backward_line()
   if #state.inline == 1 then
      if state.block.text then
         state.block.text = state.inline[1].text .. "\n" .. state.block.text
      else
         state.block.text = state.inline[1].text
      end
      self:clear_inline()
      -- state.block.id could be nil, so we need to set it
      state.block.id = show_block(state.block.id, state.block.text, state.pos[1])
   end
   self:start_clear_timer()
end

---@param prev_pos pos
---@param new_fulltext string
function Renderer:update_horz_move(prev_pos, new_fulltext)
   local lnum, col = unpack(state.pos)
   local prev_col = prev_pos[2]
   local horz_move = col - prev_col
   local first_inline = state.inline[1]

   if horz_move >= 0 then -- added some text
      if horz_move > #first_inline.text then
         self:clear_inline()
         self:start_clear_timer()
      else
         local prefix = first_inline.text:sub(1, horz_move)
         state.inline[1].text = first_inline.text:sub(horz_move + 1)
         show_inline(first_inline.id, first_inline.text, lnum, col)
         if new_fulltext:sub(prev_col) ~= prefix then
            self:start_clear_timer()
         end
      end
   else -- deleted some text
      if self.fulltext:match("^%s*$") then
         self:start_clear_timer()
      else
         local prefix = self.fulltext:sub(col + 1, col - horz_move)
         state.inline[1].text = prefix .. first_inline.text
         show_inline(first_inline.id, first_inline.text, lnum, col)
         self.clear_timer:stop()
         self:start_clear_timer()
      end
   end
end

function Renderer:update()
   local prev_pos = state.pos
   state.pos = utils.get_cursor()
   local vert_move = state.pos[1] - prev_pos[1]

   if self.changedtick == vim.b.changedtick or math.abs(vert_move) > 1 then
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
         if not state.inline[1] then
            self:clear_inline()
         else
            self:update_horz_move(prev_pos, fulltext)
         end
      end
      self.fulltext = fulltext
   end

   self.changedtick = vim.b.changedtick
end

return Renderer

-- vim: fdm=marker
