local echo = require("neocodeium.utils.echo")

local nvim_buf_get_var = vim.api.nvim_buf_get_var
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
---@field is_enabled function
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

   -- TODO: remove after some time
   if type(M.options.enabled) == "function" then
      ---@diagnostic disable-next-line: assign-type-mismatch
      M.options.filter = M.options.enabled
      M.options.enabled = true
      echo.warn(
         "using a function for `enabled` is deprecated, please use the `filter` option instead"
      )
   end

   ---@param bufnr? bufnr
   ---@return boolean, integer
   M.options.is_enabled = function(bufnr)
      bufnr = bufnr or 0
      if not M.options.enabled then
         return false, 1 -- globally disabled
      -- Buffer variable should enable neocodeium even if it is disabled
      -- by 'options.filetypes' or 'options.filter()'
      elseif vim.b[bufnr].neocodeium_enabled then
         return true, 0 -- enabled
      elseif vim.b[bufnr].neocodeium_enabled == false then
         return false, 2 -- locally disabled
      -- The same as vim.b[bunfr].neocodeium_enabled == nil and ...
      elseif M.options.filetypes[nvim_get_option_value("filetype", { buf = bufnr })] == false then
         return false, 3 -- disabled by 'options.filetypes'
      elseif M.options.filter and M.options.filter(bufnr) == false then
         return false, 4 -- disabled by 'options.filter()'
      else
         return true, 0 -- enabled
      end
   end
end

return M
