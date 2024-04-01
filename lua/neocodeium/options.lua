---@class Options
---@field enabled boolean
---@field bin? string
---@field manual boolean
---@field server { api_url?: string, portal_url?: string }
---@field log_file? string
---@field show_label boolean
---@field debounce boolean
---@field max_lines integer
---@field filetypes table<string, boolean>
local defaults = {
  enabled = true,
  bin = nil,
  manual = false,
  server = {},
  log_file = nil,
  show_label = true,
  debounce = false,
  max_lines = 10000,
  filetypes = {
    help = false,
    gitcommit = false,
    gitrebase = false,
    ["."] = false,
  },
}

local M = { options = {} }

function M.setup(opts)
  ---@type Options
  M.options = vim.tbl_deep_extend("force", defaults, opts or {})
end

return M
