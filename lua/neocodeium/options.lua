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
---@field filter fun(bufnr: integer)?
---@field enabled_func function
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

   if type(M.options.enabled) == "function" then
      M.options.filter = M.options.enabled
      M.options.enabled = true
      vim.notify(
         "Using a function for `enabled` is deprecated, please use the `filter` option instead",
         vim.log.levels.WARN
      )
   end
   vim.g.neocodeium_enabled = M.options.enabled

   ---@param bufnr? bufnr
   ---@return boolean, integer
   M.options.enabled_func = function(bufnr)
      bufnr = bufnr or 0
      if vim.b[bufnr].neocodeium_enabled == false then
         return false, 2 -- locally disabled for current buffer
      elseif vim.g.neocodeium_enabled == false then
         return false, 1 -- globally disabled
      elseif M.options.filetypes[nvim_get_option_value("filetype", { buf = bufnr })] == false then
         return false, 3 -- disabled by 'options.filetypes'
      end

      if M.options.filter then
         local result = M.options.filter(bufnr)
         if result then
            return result, 0 -- enabled
         else
            return result, 4 -- disabled by 'options.enabled()' function
         end
      end

      return true, 0 -- enabled
   end
end

return M
