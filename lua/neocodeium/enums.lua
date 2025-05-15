local M = {}

---@enum level
M.LEVEL = {
   trace = 0,
   debug = 1,
   info = 2,
   warn = 3,
   error = 4,
}

---@enum compl.part_type
M.PART = {
   inline = "COMPLETION_PART_TYPE_INLINE",
   inline_mask = "COMPLETION_PART_TYPE_INLINE_MASK",
   block = "COMPLETION_PART_TYPE_BLOCK",
}

---@enum state.request_status
M.REQUEST_STATUS = {
   none = 0,
   pending = 1,
   completed = 2,
}

return M
