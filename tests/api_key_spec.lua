-- required for proper options setup
require("neocodeium").setup()

local api = vim.api
local windsurf_api_key = require("neocodeium.api_key")

local function last_message()
   return api.nvim_exec2("1mes", { output = true }).output
end

describe("get() and set()", function()
   it("should work", function()
      windsurf_api_key.set("test")
      assert.Equal(windsurf_api_key.get(), "test")
   end)
end)

describe("check()", function()
   it("should not write warning message when api key is set", function()
      print("test")
      windsurf_api_key.set("test")
      windsurf_api_key.check()
      vim.schedule(function()
         assert.Falsy(last_message():find("No API key found", nil, true))
      end)
   end)

   it("should write warning message when api key is missing", function()
      print("test")
      windsurf_api_key.set(nil) ---@diagnostic disable-line: param-type-mismatch
      windsurf_api_key.check()
      vim.schedule(function()
         assert.Truthy(last_message():find("No API key found", nil, true))
      end)
   end)
end)
