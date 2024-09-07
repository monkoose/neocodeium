local types = require("neocodeium.types")

---@param lvl level one of vim.log.levels
---@return fun(msg: string, silent?: boolean)
local function echo(lvl)
   return function(msg, silent)
      if not silent then
         vim.cmd.redraw()
         vim.notify("NeoCodeium: " .. msg, lvl)
      end
   end
end

return {
   info = echo(types.level.info),
   warn = echo(types.level.warn),
   error = echo(types.level.error),
}
