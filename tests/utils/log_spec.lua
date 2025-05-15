local log = require("neocodeium.log")
local fn = vim.fn

describe("get_log_file()", function()
   it("should return correct path", function()
      local path = log.get_log_file()
      vim.cmd.sleep("10m")
      assert.is.True(vim.endswith(path, "neocodeium.log"))
      vim.uv.fs_open(path, "a", tonumber("644", 8), function(_, fd)
         if fd then
            vim.uv.fs_write(fd, "test", -1, function()
               vim.uv.fs_close(fd)
            end)
         end
         assert.is.Truthy(fn.filereadable(path) == 1)
      end)
   end)
end)

---@return string
local function read_log_file()
   local path = log.get_log_file()
   vim.cmd.sleep("10m")
   local lines = fn.readfile(path, "", -1)
   if #lines > 0 then
      return lines[1]
   end
   return ""
end

describe("log functions which satisfies min_log_level", function()
   it("should write log file", function()
      log.warn("warn test")
      assert.is.Truthy(read_log_file():match("warn test"))
      log.error("error test")
      assert.is.Truthy(read_log_file():match("error test"))
   end)
end)

describe("log functions which doesn't satisfy min_log_level", function()
   it("should not write log file", function()
      log.info("info test")
      assert.is.Falsy(read_log_file():match("info test"))
      log.debug("debug test")
      assert.is.Falsy(read_log_file():match("debug test"))
      log.trace("trace test")
      assert.is.Falsy(read_log_file():match("trace test"))
   end)
end)
