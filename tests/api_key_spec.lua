local api_key = require("neocodeium.api_key")

local function last_message()
  return vim.api.nvim_exec2("1mes", { output = true }).output
end

describe("get() and set()", function()
  it("should work", function()
    api_key.set("test")
    assert.are.Equal(api_key.get(), "test")
  end)
end)

describe("check()", function()
  it("should not write warning message when api key is set", function()
    print("test")
    api_key.set("test")
    api_key.check()
    assert.is.Falsy(last_message():match("No API key found"))
  end)

  it("should write warning message when api key is missing", function()
    print("test")
    api_key.set(nil) ---@diagnostic disable-line: param-type-mismatch
    api_key.check()
    assert.is.Truthy(last_message():match("No API key found"))
  end)
end)
