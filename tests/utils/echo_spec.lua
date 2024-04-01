local echo = require("neocodeium.utils.echo")

local function last_message()
  return vim.api.nvim_exec2("1mes", { output = true }).output
end

describe("error()", function()
  it("should display correct error message", function()
    assert.has_no.Error(function()
      echo.error("test")
    end)
    echo.error("some error")
    assert.is.Truthy(vim.v.errmsg:match("some error"))
    assert.is.Truthy(last_message():match("NeoCodeium: some error"))
  end)
end)

describe("warn()", function()
  it("should display correct message", function()
    echo.warn("some warning")
    assert.are.Equal(last_message(), "NeoCodeium: some warning")
  end)
end)

describe("info()", function()
  it("should display correct message", function()
    echo.warn("some info")
    assert.are.Equal(last_message(), "NeoCodeium: some info")
  end)
end)
