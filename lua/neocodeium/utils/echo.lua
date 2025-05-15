local LEVEL = require("neocodeium.enums").LEVEL

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
   info = echo(LEVEL.info),
   warn = echo(LEVEL.warn),
   error = echo(LEVEL.error),
}
