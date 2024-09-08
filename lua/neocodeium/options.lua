local nvim_buf_get_var = vim.api.nvim_buf_get_var
local nvim_get_option_value = vim.api.nvim_get_option_value

---@class Options
---@field enabled function|boolean
---@field bin? string
---@field manual boolean
---@field server { api_url?: string, portal_url?: string }
---@field show_label boolean
---@field debounce boolean
---@field max_lines integer `-1` for all lines
---@field silent boolean
---@field filetypes table<string, boolean>
---@field root_dir string[]
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

   if type(M.options.enabled) == "boolean" then
      vim.g.neocodeium_enabled = M.options.enabled
   end

   ---@param bufnr? bufnr
   ---@return boolean
   M.options.enabled_func = function(bufnr)
      bufnr = bufnr or 0
      if
         vim.g.neocodeium_enabled == false
         or M.options.filetypes[nvim_get_option_value("filetype", { buf = bufnr })] == false
      then
         return false
      end

      local ok, res = pcall(nvim_buf_get_var, bufnr, "neocodeium_enabled")
      if ok and res == false then
         return false
      end

      if type(M.options.enabled) == "function" then
         return M.options.enabled(bufnr)
      end

      return true
   end
end

return M
