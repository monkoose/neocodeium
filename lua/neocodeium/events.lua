local events = {}

local api = vim.api
local augroup = api.nvim_create_augroup("neocodeium_events", {})

---Trigger an event
---@param event string The event pattern
---@param data? any The event data
---@param scheduled? boolean Whether or not to schedule the event
function events.emit(event, data, scheduled)
   local event_opts = { pattern = event, data = data, modeline = false }
   if scheduled then
      vim.schedule(function()
         api.nvim_exec_autocmds("User", event_opts)
      end)
   else
      api.nvim_exec_autocmds("User", event_opts)
   end
end

---Subscribes to an event
---@param event string The event pattern
---@param callback fun(data: any) The callback function
function events.subscribe(event, callback)
   api.nvim_create_autocmd("User", {
      pattern = event,
      group = augroup,
      callback = function(ev)
         callback(ev.data)
      end,
   })
end

return events
