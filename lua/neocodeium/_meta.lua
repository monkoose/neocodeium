---@meta types

---Represents buffer number; 0 is current buffer.
---@alias bufnr integer
---0-based line number
---@alias lnum integer
---0-based column number.
---@alias col integer
---Tuple of 0-based line number and column number.
---@alias pos { [1]: lnum, [2]: col }
---Ex command
---@alias ex_cmd string
---Decoded json table
---Encoded json string
---@alias json_str string
---Represenation of the url string, must start with http:// or https://.
---@alias url string

---@alias extmark_id integer
---@alias filepath string

---@alias os_name "linux" | "macos" | "windows" | "unsupported"
---@alias arch "x64" | "arm" | "unsupported"

---@class system_info
---@field os os_name
---@field arch arch

---@class document
---@field text string
---@field editor_language string
---@field cursor_position { row: integer, col: integer }
---@field language integer
---@field absolute_uri string
---@field workspace_uri string|nil
---@field line_ending string

---@class request_metadata
---@field ide_name string
---@field ide_version string
---@field extension_name string
---@field extension_version string
---@field api_key string?
---@field request_id integer?

---@alias request_type
---| "Heartbeat"
---| "GetCompletions"
---| "CancelRequest"
---| "AcceptCompletion"
---| "RefreshContextForIdeAction"
---| "GetProcesses"
---| "AddTrackedWorkspace"

---@class request_data
---@field metadata request_metadata

---@class accept_request_data
---@field metadata request_metadata
---@field completion_id string

---@class completion_request_data
---@field metadata request_metadata
---@field editor_options? editor_options
---@field document? document
---@field other_documents? document[]

---@class response
---@field out string[]
---@field err string[]

---@class editor_options
---@field tab_size integer
---@field insert_spaces boolean

---@class virttext_cache
---@field timer uv.uv_timer_t
---@field col col
---@field lnum lnum
---@field text string
---@field char string
---@field inline_ids extmark_id[]
---@field block_text string
---@field block_id extmark_id?

---@class inline_content
---@field text string
---@field prefix string
---@field lnum lnum
---@field col col

---@class compl.data
---@field items compl.item[]?
---@field index integer?
---@field id integer?

---@alias completionId string
---@class compl.item
---@field completion { completionId: completionId, text: string }
---@field completionParts? compl.part[]
---@field range compl.range
---@field source compl.source
---@field suffix compl.suffix

---@class compl.part
---@field line compl.lnum?
---@field offset compl.offset
---Prefix of the part text. Missing at the start of the line and for block parts.
---@field prefix string?
---Text of the part.
---@field text string
---Type of the part.
---@field type compl.part_type

---@class compl.range
---@field startOffset compl.offset?
---@field startPosition compl.pos
---@field endOffset compl.offset
---@field endPosition compl.pos

---@class compl.suffix
---@field deltaCursorOffset string

---0-based line number as string. If not present should be understand as "0".
---@alias compl.lnum string
---0-based column number as string. If not present should be understand as "0".
---@alias compl.col string
---@alias compl.pos { row: compl.lnum?, col: compl.col? }
---Byte offset position in a buffer as string.
---@alias compl.offset string

---@alias compl.source
---| "COMPLETION_SOURCE_NETWORK"
---| "COMPLETION_SOURCE_TYPING_AS_SUGGESTED"
