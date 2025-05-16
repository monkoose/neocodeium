local M = {}

---@enum compl.part_type
M.PART = {
   inline = "COMPLETION_PART_TYPE_INLINE",
   inline_mask = "COMPLETION_PART_TYPE_INLINE_MASK",
   block = "COMPLETION_PART_TYPE_BLOCK",
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
