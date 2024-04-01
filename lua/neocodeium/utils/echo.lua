local types = require("neocodeium.types")

---@param lvl level one of vim.log.levels
---@return fun(msg: string)
local function echo(lvl)
  ---@param msg string
  return function(msg)
    vim.cmd.redraw()
    vim.notify("NeoCodeium: " .. msg, lvl)
  end
end

return {
  ---@type fun(msg: string)
  info = echo(types.level.info),
  ---@type fun(msg: string)
  warn = echo(types.level.warn),
  ---@type fun(msg: string)
  error = echo(types.level.error),
}
