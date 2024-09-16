local events = {}

local nvim_exec_autocmds = vim.api.nvim_exec_autocmds
local nvim_create_autocmd = vim.api.nvim_create_autocmd
local nvim_create_augroup = vim.api.nvim_create_augroup

local augroup = nvim_create_augroup("neocodeium_events", {})

---Trigger an event
---@param event string The event pattern
---@param data? any The event data
---@param scheduled? boolean Whether or not to schedule the event
function events.emit(event, data, scheduled)
   local event_opts = { pattern = event, data = data, modeline = false }
   if scheduled then
      vim.schedule(function()
         nvim_exec_autocmds("User", event_opts)
      end)
   else
      nvim_exec_autocmds("User", event_opts)
   end
end

---Subscribes to an event
---@param event string The event pattern
---@param callback fun(data: any) The callback function
function events.subscribe(event, callback)
   nvim_create_autocmd("User", {
      pattern = event,
      group = augroup,
      callback = function(ev)
         callback(ev.data)
      end,
   })
end

return events
