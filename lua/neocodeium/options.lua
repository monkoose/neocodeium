---@class Options
---@field enabled boolean
---@field bin? string
---@field manual boolean
---@field server { api_url?: string, portal_url?: string }
---@field show_label boolean
---@field debounce boolean
---@field max_lines integer
---@field silent boolean
---@field filetypes table<string, boolean>
---@field root_dir string[]
local defaults = {
  enabled = true,
  bin = nil,
  manual = false,
  server = {},
  show_label = true,
  debounce = false,
  max_lines = 10000,
  silent = false,
  filetypes = {
    help = false,
    gitcommit = false,
    gitrebase = false,
    ["."] = false,
  },
  root_dir = { ".bzr", ".git", ".hg", ".svn", "_FOSSIL_", "package.json" },
}

local M = { options = {} }

function M.setup(opts)
  ---@type Options
  M.options = vim.tbl_deep_extend("force", defaults, opts or {})
end

return M
