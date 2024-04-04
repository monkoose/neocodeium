-- Imports ------------------------------------------------- {{{1

local log = require("neocodeium.log")
local doc = require("neocodeium.doc")
local utils = require("neocodeium.utils")
local options = require("neocodeium.options").options
local types = require("neocodeium.types")
local server = require("neocodeium.server")
local renderer = require("neocodeium.renderer")

local vf = vim.fn
local uv = vim.uv
local json = vim.json

local nvim_feedkeys = vim.api.nvim_feedkeys
local nvim_get_current_buf = vim.api.nvim_get_current_buf
local nvim_replace_termcodes = vim.api.nvim_replace_termcodes

-- Completer ----------------------------------------------- {{{1

---@enum compl.status
local status = {
  none = 0,
  pending = 1,
  completed = 2,
}

---@class Completer
---@field pos pos
---@field data compl.data
---@field status compl.status
---@field timer uv.uv_timer_t
---@field request_id integer
---@field allowed_encoding boolean
---@field other_docs document[]
local Completer = {
  data = {},
  status = status.none,
  timer = assert(uv.new_timer()),
  request_id = 0,
  allowed_encoding = false,
  other_docs = {},
}

-- Auxiliary functions ------------------------------------- {{{1

---Returns values of `'shiftwidth'` and `'expandtab'` in the current buffer.
---@return editor_options
local function get_editor_opts()
  return {
    tab_size = vim.bo.shiftwidth,
    insert_spaces = vim.bo.expandtab,
  }
end

-- Completer methods --------------------------------------- {{{1

---Returns `true` if completion data is present and valid.
---@private
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
  if options.enabled and self.allowed_encoding and not vim.b.neocodeium_disabled then
    return options.filetypes[vim.bo.filetype] ~= false
  end
  return false
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

  renderer:display(self.data.items, self.data.index)
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
    if not renderer:display(self.data.items or {}, 1) then
      self:request()
    end
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
  for _, item in ipairs(renderer.inline) do
    text = text .. item.prefix .. item.text
  end

  if text ~= "" then
    text = vf.matchstr(text, regex)
    if #renderer.inline > 1 then
      local text_len = #text
      local combined_text = renderer.inline[1].text
      if text_len > #combined_text then
        local combined_prefix = ""
        for _, item in ipairs({ unpack(renderer.inline, 2) }) do
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
        local prefix_chars = vf.strchars(combined_prefix)
        if prefix_chars > 0 then
          local dels = nvim_replace_termcodes(string.rep("<Del>", prefix_chars), true, false, true)
          nvim_feedkeys(dels, "n", false)
        end
      end
    end
  else
    text = renderer.block.text or ""
    if text == "" then
      return
    end

    text = vim.split(text, "\n")[1]
    text = vf.matchstr(text, regex)
    local lnum1 = renderer.pos[1] + 1
    utils.set_lines(lnum1, lnum1, { "" })
    utils.set_cursor({ lnum1, 0 })
  end
  nvim_feedkeys(text, "nt", false)
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
  self.request_id = self.request_id + 1
  local curr_bufnr = nvim_get_current_buf()
  local pos = renderer.pos
  local metadata = server:request_metadata()
  metadata.request_id = self.request_id
  local data = {
    metadata = metadata,
    editor_options = get_editor_opts(),
    document = doc.get(curr_bufnr, vim.bo.filetype, -1, pos),
    other_documents = self.other_docs,
  }

  server:request("GetCompletions", data, function(r)
    self.status = status.completed
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
    if options.debounce and self.timer:is_active() then
      self.timer:stop()
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
    renderer:reset()
  end
end

---Initiates a completion.
---@param omit_manual? boolean
function Completer:initiate(omit_manual)
  renderer:update()
  self:clear()

  if options.manual and not omit_manual then
    renderer:clear_all()
    return
  end

  if options.debounce then
    if self.timer:is_active() then
      self.timer:stop()
    end
    self.timer:start(
      120,
      0,
      vim.schedule_wrap(function()
        self:request()
      end)
    )
  else
    self:request()
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
    metadata = server:request_metadata(),
    completion_id = curr_item.completion.completionId,
  })

  local pos ---@type pos
  local lnum = renderer.pos[1] + 1
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
  -- defer to prevent pasting block before accept_line()
  vim.defer_fn(function()
    renderer:reset()
    if block then
      utils.set_lines(lnum, lnum, block)
      utils.set_cursor(pos)
    end
  end, 0)
end
-- }}}1

return Completer

-- vim: fdm=marker
