local utils = require("neocodeium.utils")

local nvim_get_option_value = vim.api.nvim_get_option_value

---@class Options
---@field enabled boolean
---@field bin? string
---@field manual boolean
---@field server { api_url?: string, portal_url?: string }
---@field show_label boolean
---@field debounce boolean
---@field max_lines integer `-1` for all lines
---@field silent boolean
---@field filetypes table<string, boolean>
---@field root_dir string[]
---@field filter? fun(bufnr: integer)
---@field status function
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

   ---@param bufnr? bufnr
   ---@return integer
   M.options.status = function(bufnr)
      bufnr = bufnr or 0
      if not M.options.enabled then
         return 1 -- globally disabled
      -- Buffer variable should enable neocodeium even if it is disabled
      -- by 'options.filetypes' or 'options.filter()' or in special buftypes
      elseif vim.b[bufnr].neocodeium_enabled then
         return 0 -- enabled
      elseif vim.b[bufnr].neocodeium_enabled == false then
         return 2 -- locally disabled
      elseif M.options.disable_in_special_buftypes and not utils.is_normal_buf(bufnr) then
         return 6 -- disabled in special buftypes
      -- The same as vim.b[bunfr].neocodeium_enabled == nil and ...
      elseif M.options.filetypes[nvim_get_option_value("filetype", { buf = bufnr })] == false then
         return 3 -- disabled by 'options.filetypes'
      elseif M.options.filter and M.options.filter(bufnr) == false then
         return 4 -- disabled by 'options.filter()'
      else
         return 0 -- enabled
      end
   end
end

return M
