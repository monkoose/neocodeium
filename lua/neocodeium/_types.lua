local M = {}

---@enum level
M.level = {
   trace = 0,
   debug = 1,
   info = 2,
   warn = 3,
   error = 4,
}

---@enum compl.type
M.part = {
   inline = "COMPLETION_PART_TYPE_INLINE",
   inline_mask = "COMPLETION_PART_TYPE_INLINE_MASK",
   block = "COMPLETION_PART_TYPE_BLOCK",
}

return M
