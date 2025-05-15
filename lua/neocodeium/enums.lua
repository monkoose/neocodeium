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

---@enum request_status
M.REQUEST_STATUS = {
   none = 0,
   pending = 1,
   completed = 2,
}

---@enum state.status
M.STATUS = {
   enabled = 0,
   disabled = 1,
   buf_disabled = 2,
   filetype_disabled = 3,
   filter_disabled = 4,
   encoding_disabled = 5,
   special_buf_disabled = 6,
}

return M
