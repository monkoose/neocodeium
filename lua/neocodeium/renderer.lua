-- Imports ------------------------------------------------- {{{1

local options = require("neocodeium.options").options
local events = require("neocodeium.events")
local state = require("neocodeium.state")
local utils = require("neocodeium.utils")

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
---@field virt_text table

---@class Renderer
---@field clear_timer uv.uv_timer_t
---@field label label
---@field changedtick integer
---@field single_line_virt_text table
---@field inline_virt_text table
local Renderer = {
   clear_timer = assert(uv.new_timer()),
   label = {
      enabled = false,
      virt_text = { { "", "NeoCodeiumLabel" } },
   },
   changedtick = -1,
   single_line_virt_text = { { options.single_line.label, "NeoCodeiumSingleLineLabel" } },
   inline_virt_text = { { "", hlgroup } },
}

-- Auxiliary functions ------------------------------------- {{{1

---Deletes virtual text by it's extmark `id`
---@param id extmark_id
---@return boolean true if deleted
local function delete_virttext(id)
   return nvim_buf_del_extmark(0, ns, id)
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

-- Renderer methods ---------------------------------------- {{{1

---@param text string
---@return extmark_id
function Renderer:set_virt_label(text)
   self.label.virt_text[1][1] = text
   return nvim_buf_set_extmark(0, ns, state.pos[1], 0, {
      id = self.label.id,
      virt_text = self.label.virt_text,
      virt_text_win_col = -1 - #text,
   })
end

---Adds virtual text into the `lnum` line number and `col` column.
---If `id` is nil then a new id will be generated.
---@param id? extmark_id
---@param str string text to display
---@param col col
---@param lnum? lnum
---@return extmark_id
function Renderer:set_virt_inline(id, str, col, lnum)
   self.inline_virt_text[1][1] = str
   return nvim_buf_set_extmark(0, ns, lnum or state.pos[1], col, {
      id = id,
      virt_text_pos = "inline",
      virt_text = self.inline_virt_text,
      undo_restore = false,
      strict = false,
   })
end

---Adds virtual text below the line with `lnum` number.
---If `id` is nil then a new id will be generated.
---@param text string # text to display, will be split into lines at "\n"
---@param lnum? lnum
---@return extmark_id
function Renderer:set_virt_block(text, lnum)
   lnum = lnum or state.pos[1]
   if
      options.single_line.enabled
      and state.inline[1]
      and not utils.is_empty(state.inline[1].text)
   then
      state.block.visible = false
      return nvim_buf_set_extmark(0, ns, lnum, 0, {
         id = state.block.id,
         virt_text = self.single_line_virt_text,
         undo_restore = false,
         strict = false,
      })
   else
      state.block.visible = true
      local block_lines = {}
      for line in vim.gsplit(text, "\n") do
         table.insert(block_lines, { { leading_tabs_to_spaces(line), hlgroup } })
      end

      return nvim_buf_set_extmark(0, ns, lnum, 0, {
         id = state.block.id,
         virt_lines = block_lines,
         undo_restore = false,
         strict = false,
      })
   end
end

---@private
function Renderer:start_clear_timer()
   if not self.clear_timer:is_active() then
      self.clear_timer:start(350, 0, function()
         self:clear(false, true)
      end)
   end
end

---@private
---@param contents inline_content[]
function Renderer:display_inline(contents)
   -- removes extra inline items
   local leftover_ids = #state.inline - #contents
   if leftover_ids > 0 then
      for _ = 1, leftover_ids do
         local item = table.remove(state.inline)
         delete_virttext(item.id)
      end
   end
   -- change inline virtual text
   for i, c in ipairs(contents) do
      if not state.inline[i] then
         state.inline[i] = {}
      end
      state.inline[i].text = c.text
      state.inline[i].prefix = c.prefix
      state.inline[i].id = self:set_virt_inline(state.inline[i].id, c.text, c.col, c.lnum)
   end
end

---@private
---@param text? string
function Renderer:display_block(text)
   if text then
      if not state.block.id or options.single_line.enabled or state.block.text ~= text then
         state.block.text = text
         state.block.id = self:set_virt_block(text)
      end
   else
      self:remove_block()
   end
end

function Renderer:update_label()
   vim.schedule(function()
      if state.active and utils.is_empty(state.inline) and not state.block.text then
         self:display_label()
      end
   end)
end

---@private
function Renderer:display_label()
   if not (options.show_label and self.label.enabled) then
      return
   end

   if state.pending then
      self.label.id = self:set_virt_label(" * ")
   elseif utils.is_empty(state.data.items) then
      self.label.id = self:set_virt_label(" 0 ")
   else
      if #state.inline == 1 and state.inline[1].text == "" and not state.block.text then
         self.label.id = self:set_virt_label(" 0 ")
      else
         self.label.id = self:set_virt_label(state.data.index .. "/" .. #state.data.items)
      end
   end
end

---Displays completion item, if request to the server should be resend returns true
---@param inline inline_content[]
---@param block? string
function Renderer:display(inline, block)
   self.clear_timer:stop()
   self:display_inline(inline)
   self:display_block(block)
   if block or #inline > 0 then
      self:display_label()
   end
   events.emit("NeoCodeiumCompletionDisplayed", nil, true)
end

---Removes block virtual text and block cache
function Renderer:remove_block()
   if state.block.id then
      delete_virttext(state.block.id)
      state.block.text = nil
      state.block.id = nil
      state.block.visible = nil
   end
end

---Removes inline virtual text and resets `state.inline`
function Renderer:remove_inline()
   for i = #state.inline, 1, -1 do
      delete_virttext(state.inline[i].id)
      state.inline[i] = nil
   end
end

---Removes label virtual text and label.id cache
function Renderer:remove_label()
   if self.label.id then
      delete_virttext(self.label.id)
      self.label.id = nil
   end
end

---Clears plugin's namespace and resets cache
---@param with_reset? boolean
---@param scheduled? boolean
function Renderer:clear(with_reset, scheduled)
   if with_reset then
      self.clear_timer:stop()
      self.label.id = nil
      state.inline = {}
      state.block.id = nil
      state.block.text = nil
      state.block.visible = nil
      state.curline_text = ""
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
            self:remove_inline()
            self:remove_block()
         end)
      else
         self:remove_inline()
         self:remove_block()
         if options.manual then
            self:remove_label()
         end
      end
   end
end

---@private
function Renderer:update_forward_line()
   if not utils.is_empty(state.block.text) then
      -- find if block.text has multiple lines
      local index = state.block.text:find("\n")
      self:remove_inline()
      state.inline = { { prefix = "" } }
      local lnum, col = unpack(state.pos)
      if index then
         -- starting index `state.pos[2] + 1` is start of the line with indentation
         -- prevents shifting of the inline text
         state.inline[1].text = state.block.text:sub(col + 1, index - 1)
         state.block.text = state.block.text:sub(index + 1)
         -- state.block.id already exists, no need to set it
         self:set_virt_block(state.block.text, lnum)
      else
         state.inline[1].text = state.block.text:sub(col + 1)
         self:remove_block()
         -- required to update label position
         if options.show_label and self.label.enabled then
            self:set_virt_label(" 0 ")
         end
      end
      state.inline[1].id = self:set_virt_inline(nil, state.inline[1].text, col, lnum)
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
      self:remove_inline()
      -- state.block.id could be nil, so we need to set it
      state.block.id = self:set_virt_block(state.block.text)
   end
   self:start_clear_timer()
end

---@param prev_pos pos
---@param curline_text string
function Renderer:update_horz_move(prev_pos, curline_text)
   local col = state.pos[2]
   local prev_col = prev_pos[2]
   local horz_move = col - prev_col
   local first_inline = state.inline[1]

   if horz_move >= 0 then -- added some text
      if horz_move > #first_inline.text then
         self:remove_inline()
         self:start_clear_timer()
      else
         local prefix = first_inline.text:sub(1, horz_move)
         state.inline[1].text = first_inline.text:sub(horz_move + 1)
         self:set_virt_inline(first_inline.id, first_inline.text, col)
         if curline_text:sub(prev_col + 1) ~= prefix then
            self:start_clear_timer()
         else
            state.matching = true
            -- refresh virttext block of full inline completion
            if state.inline[1].text == "" and state.block.text then
               self:set_virt_block(state.block.text)
            end
         end
      end
   else -- deleted some text
      if state.curline_text:match("^%s*$") then
         self:start_clear_timer()
      else
         local prefix = state.curline_text:sub(col + 1, col - horz_move)
         state.inline[1].text = prefix .. first_inline.text
         self:set_virt_inline(first_inline.id, first_inline.text, col)
         self.clear_timer:stop()
         self:start_clear_timer()
      end
   end
end

function Renderer:update()
   state.matching = false
   local prev_pos = state.pos
   state.pos = utils.get_cursor()
   local vert_move = state.pos[1] - prev_pos[1]

   if self.changedtick == vim.b.changedtick or math.abs(vert_move) > 1 then
      self.clear_timer:stop()
      self:clear()
      state.curline_text = nvim_get_current_line()
   else
      local curline_text = nvim_get_current_line()
      if vert_move == 1 then
         self.clear_timer:stop()
         self:update_forward_line()
      elseif vert_move == -1 then
         self.clear_timer:stop()
         self:update_backward_line()
      else -- cursor movement happened on the same line
         if not state.inline[1] then
            self:remove_inline()
         else
            self:update_horz_move(prev_pos, curline_text)
         end
      end
      state.curline_text = curline_text
   end

   self.changedtick = vim.b.changedtick
end

return Renderer

-- vim: fdm=marker
