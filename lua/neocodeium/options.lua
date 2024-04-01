local defaults = {
  enabled = true,
  bin = nil,
  manual = false,
  server = {},
  log_file = nil,
  show_label = true,
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
  M.options = vim.tbl_deep_extend("force", defaults, opts or {})
end

return M
