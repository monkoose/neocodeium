---@class Options
---@field enabled boolean
---@field bin? string
---@field manual boolean
---@field server { api_url?: string, portal_url?: string }
---@field show_label boolean
---@field debounce boolean
---@field max_lines integer # `-1` for all lines
---@field silent boolean
---@field disable_in_special_buftypes boolean
---@field log_level string
---@field single_line { enabled: boolean, label: string }
---@field filetypes table<string, boolean>
---@field root_dir string[]
---@field filter? fun(bufnr: integer)
local defaults = {
   enabled = true,
   bin = nil,
   manual = false,
   server = {},
   show_label = true,
   debounce = false,
   max_lines = 10000,
   silent = false,
   disable_in_special_buftypes = true,
   log_level = "warn",
   single_line = {
      enabled = false,
      label = "...",
   },
   filetypes = {
      help = false,
      gitcommit = false,
      gitrebase = false,
      ["."] = false,
   },
   root_dir = { ".bzr", ".git", ".hg", ".svn", "_FOSSIL_", "package.json" },
}

local M = { options = vim.deepcopy(defaults) }

function M.setup(opts)
   ---@type Options
   M.options = vim.tbl_deep_extend("force", defaults, opts or {})
end

return M
