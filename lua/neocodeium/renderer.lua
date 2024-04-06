-- Imports ------------------------------------------------- {{{1

local utils = require("neocodeium.utils")
local types = require("neocodeium.types")
local options = require("neocodeium.options").options

local fn = vim.fn
local uv = vim.uv

local nvim_get_current_line = vim.api.nvim_get_current_line
local nvim_buf_set_extmark = vim.api.nvim_buf_set_extmark
local nvim_get_hl_id_by_name = vim.api.nvim_get_hl_id_by_name
local nvim_create_namespace = vim.api.nvim_create_namespace
local nvim_buf_del_extmark = vim.api.nvim_buf_del_extmark
local nvim_buf_clear_namespace = vim.api.nvim_buf_clear_namespace

local hlgroup = nvim_get_hl_id_by_name("NeoCodeiumSuggestion")
local ns = nvim_create_namespace("neocodeium_compl")

-- Renderer ------------------------------------------------- {{{1

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

---@class Renderer
---@field pos pos
---@field tick integer
---@field timer uv.uv_timer_t
---@field fulltext string
---@field label label
---@field inline inline[]
---@field block block
local Renderer = {
  pos = { 0, 0 },
  timer = assert(uv.new_timer()),
  fulltext = "",
  label = { enabled = false },
  inline = {},
  block = {},
}

-- Auxiliary functions ------------------------------------- {{{1

---Adds virtual text into the `lnum` line number and `col` column.
---If `id` is nil then a new id will be generated.
---@param id extmark_id?
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
---@param id extmark_id?
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

-- Renderer methods ---------------------------------------- {{{1

-- TODO: show pending status
---@param id extmark_id
---@param text string
function Renderer:show_label(id, text)
  if not (options.show_label and self.label.enabled) then
    return
  end

  self.label.id = nvim_buf_set_extmark(0, ns, self.pos[1], 0, {
    id = id,
    virt_text = { { text, "NeoCodeiumLabel" } },
    virt_text_win_col = -1 - #text,
  })
end

---@private
---@param contents inline_content[]
function Renderer:display_inline(contents)
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
---@param text string?
function Renderer:display_block(text, lnum)
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
---@param items compl.item[]
---@param index integer
function Renderer:display_label(items, index)
  if utils.is_empty(items) then
    self:show_label(self.label.id, " 0 ")
  else
    self:show_label(self.label.id, index .. "/" .. #items)
  end
end

---Displays completion item
---@param items compl.item[]
---@param index integer
---@return boolean
function Renderer:display(items, index)
  -- TODO: doesn't work on first line in empty buffer
  if not utils.is_insert() then
    self:reset()
    return true
  end

  local lnum, col = self.pos[1], self.pos[2]
  local item = items[index] or {}
  local parts = item.completionParts or {}

  if utils.is_empty(parts) then
    return true
  end

  -- When only block part is present and text was changed compared to when
  -- request was sent, return false, so it will dispatch new request
  if not self.fulltext:match("^%s*$") and item.completion.text:match("^\n") then
    return false
  end

  local block_text ---@type string?
  local inline_contents = {} ---@type inline_content[]
  local cummulative_cols = 0

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
            return false
          end

          local delta = calc_inline_delta(prefix_len, match_prefix_idx, col)
          if delta < 0 then
            text = prefix:sub(delta) .. text
          elseif delta > 0 then
            text = text:sub(delta + 1)
          end

          table.insert(
            inline_contents,
            { lnum = lnum, col = column + delta, text = text, prefix = "" }
          )
        else
          table.insert(inline_contents, { lnum = lnum, col = column, text = text, prefix = prefix })
        end
      elseif part.type == types.part.block then
        block_text = text
      end
    end
  end

  self.timer:stop()
  self:display_inline(inline_contents)
  self:display_block(block_text, lnum)
  if block_text or #inline_contents > 0 then
    self:display_label(items, index)
  end
  return true
end

---@private
function Renderer:start_clear_timer()
  if not self.timer:is_active() then
    self.timer:start(
      350,
      0,
      vim.schedule_wrap(function()
        self:clear_all()
      end)
    )
  end
end

---@private
function Renderer:update_forward_line()
  if self.block.text and self.block.text ~= "" then
    -- find if block.text has multiple lines
    local index = self.block.text:find("\n")
    self.inline = { { prefix = "" } }
    if index then
      -- starting index `self.pos[2] + 1` is start of the line with indentation
      -- prevents shifting of the inline text
      self.inline[1].text = self.block.text:sub(self.pos[2] + 1, index - 1)
      self.block.text = self.block.text:sub(index + 1)
      -- self.block.id already exists, no need to set it
      show_block(self.block.id, self.block.text, self.pos[1])
    else
      self.inline[1].text = self.block.text:sub(self.pos[2] + 1)
      self:clear_block()
    end
    self.inline[1].id = show_inline(nil, self.inline[1].text, self.pos[1], self.pos[2])
  end
  self:start_clear_timer()
end

---@private
function Renderer:update_backward_line()
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
function Renderer:update_horz_move(prev_pos, new_fulltext)
  local lnum, col = unpack(self.pos)
  local prev_col = prev_pos[2]
  local horz_move = col - prev_col

  if horz_move >= 0 then -- added some text
    if horz_move > #self.inline[1].text then
      self:clear_inline()
      self:start_clear_timer()
    else
      local prefix = self.inline[1].text:sub(1, horz_move)
      self.inline[1].text = self.inline[1].text:sub(horz_move + 1)
      show_inline(self.inline[1].id, self.inline[1].text, lnum, col)
      if new_fulltext:sub(prev_col) ~= prefix then
        self:start_clear_timer()
      end
    end
  else -- deleted some text
    local prefix = self.fulltext:sub(col + 1, col - horz_move)
    self.inline[1].text = prefix .. self.inline[1].text
    show_inline(self.inline[1].id, self.inline[1].text, lnum, col)
    self.timer:stop()
    self:start_clear_timer()
  end
end

-- TODO: it shouldn't work in options.filetypes disabled buffers
function Renderer:update()
  local prev_pos = self.pos
  self.pos = utils.get_cursor()
  local vert_move = self.pos[1] - prev_pos[1]

  if self.tick == vim.b.changedtick or math.abs(vert_move) > 1 then
    self.timer:stop()
    self:clear_all()
    self.fulltext = nvim_get_current_line()
  else
    local fulltext = nvim_get_current_line()
    if vert_move == 1 then
      self.timer:stop()
      self:update_forward_line()
    elseif vert_move == -1 then
      self.timer:stop()
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
function Renderer:clear_block()
  if self.block.id == nil then
    return
  end

  delete_virttext(self.block.id)
  self.block.text = nil
  self.block.id = nil
end

---Clears the inline virtual text and resets `self.inline` to empty table
function Renderer:clear_inline()
  for _, item in ipairs(self.inline) do
    delete_virttext(item.id)
  end
  self.inline = {}
end

---Clears the label virtual text and removes label.id cache
function Renderer:clear_label()
  if self.label.id == nil then
    return
  end

  delete_virttext(self.label.id)
  self.label.id = nil
end

---Clears all virtual text
function Renderer:clear_all()
  self:clear_label()
  self:clear_inline()
  self:clear_block()
end

---Clears plugin's namespace and resets cache
function Renderer:reset()
  self.timer:stop()
  nvim_buf_clear_namespace(0, ns, 0, -1)
  self.label.id = nil
  self.inline = {}
  self.block.id = nil
  self.block.text = nil
  self.fulltext = ""
end
-- }}}1

return Renderer

-- vim: fdm=marker
