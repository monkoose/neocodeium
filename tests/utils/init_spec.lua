---@diagnostic disable: undefined-field
local utils = require("neocodeium.utils")
local stub = require("luassert.stub")

describe("exec()", function()
   it("should return string if vim ex command is executed successfully", function()
      assert.has_no.Error(function()
         utils.exec("ls")
      end)
      assert.is.String(utils.exec("ls"))
   end)
   it("should throw an error if command is not executed successfully", function()
      assert.has.Error(function()
         utils.exec("NotExistsCommand")
      end)
   end)
end)

describe("", function()
   vim.cmd.edit("tests/assets/readable.txt")

   describe("get_cursor()", function()
      it("should return 0-based cursor position in the current window", function()
         vim.api.nvim_win_set_cursor(0, { 2, 1 })
         assert.are.Same(utils.get_cursor(), { 1, 1 })
      end)
   end)

   describe("set_cursor()", function()
      it("should set 0-based cursor position in the current window", function()
         vim.cmd.edit("tests/assets/readable.txt")
         utils.set_cursor({ 1, 3 })
         assert.are.Same(vim.api.nvim_win_get_cursor(0), { 2, 3 })
      end)
   end)

   describe("set_lines()", function()
      it("should set lines in the current buffer", function()
         local lines = { "foo", "bar" }
         utils.set_lines(1, 2, lines)
         assert.are.Same(vim.api.nvim_buf_get_lines(0, 1, 1 + #lines, true), lines)
      end)
   end)

   vim.cmd("bwipe!")
end)

describe("is_insert()", function()
   local cur_mode = stub(vim.api, "nvim_get_mode")

   it("should return true in insert mode", function()
      cur_mode.returns({ mode = "i" })
      assert.is.True(utils.is_insert())
   end)

   it("sould return false if current mode is not insert", function()
      cur_mode.returns({ mode = "v" })
      assert.is.False(utils.is_insert())
      cur_mode.returns({ mode = "c" })
      assert.is.False(utils.is_insert())
      cur_mode.returns({ mode = "R" })
      assert.is.False(utils.is_insert())
      cur_mode.returns({ mode = "n" })
      assert.is.False(utils.is_insert())
   end)

   cur_mode:revert()
end)

describe("get_system_info()", function()
   it("should return table containing system info", function()
      local info = utils.get_system_info()
      assert.is.Table(info)
      assert.is.String(info.os)
      assert.is.String(info.arch)
      assert.is.Boolean(info.is_arm)
      assert.is.Boolean(info.is_unix)
      assert.is.Boolean(info.is_win)
   end)

   it("should return correct data", function()
      local uname = stub(vim.uv, "os_uname")

      uname.returns({ sysname = "Linux", machine = "x86_64" })
      local info = utils.get_system_info()
      assert.is.Equal(info.os, "linux")
      assert.is.Equal(info.arch, "x64")
      assert.is.False(info.is_arm)
      assert.is.False(info.is_win)
      assert.is.True(info.is_unix)

      uname.returns({ sysname = "Windows_NT", machine = "x86_64" })
      package.loaded["neocodeium.utils"] = nil
      info = require("neocodeium.utils").get_system_info()
      assert.is.Equal(info.os, "windows")
      assert.is.Equal(info.arch, "x64")
      assert.is.True(info.is_win)
      assert.is.False(info.is_unix)

      uname.returns({ sysname = "Darwin", machine = "arm" })
      package.loaded["neocodeium.utils"] = nil
      info = require("neocodeium.utils").get_system_info()
      assert.is.Equal(info.os, "macos")
      assert.is.Equal(info.arch, "arm")
      assert.is.True(info.is_arm)
      assert.is.False(info.is_win)
      assert.is.True(info.is_unix)

      uname.returns({ sysname = "Darwin", machine = "aarch64" })
      package.loaded["neocodeium.utils"] = nil
      info = require("neocodeium.utils").get_system_info()
      assert.is.Equal(info.arch, "arm")
      assert.is.True(info.is_arm)

      uname:revert()
   end)
end)

describe("with_shell()", function()
   it("should not change shell options after the function is executed", function()
      local shell = vim.o.shell
      local shellpipe = vim.o.shellpipe
      local shellredir = vim.o.shellredir
      local shellquote = vim.o.shellquote
      local shellxquote = vim.o.shellxquote
      local shellcmdflag = vim.o.shellcmdflag

      utils.with_shell(function()
         vim.o.shell = "__unset__"
         vim.o.shellpipe = "__unset__"
         vim.o.shellredir = "__unset__"
         vim.o.shellquote = "__unset__"
         vim.o.shellxquote = "__unset__"
         vim.o.shellcmdflag = "__unset__"
      end)

      assert.are.Equal(vim.o.shell, shell)
      assert.are.Equal(vim.o.shellpipe, shellpipe)
      assert.are.Equal(vim.o.shellredir, shellredir)
      assert.are.Equal(vim.o.shellquote, shellquote)
      assert.are.Equal(vim.o.shellxquote, shellxquote)
      assert.are.Equal(vim.o.shellcmdflag, shellcmdflag)
   end)
end)

describe("is_empty()", function()
   it("should return true if table is nil or empty", function()
      assert.is.True(utils.is_empty({}))
      assert.is.True(utils.is_empty(nil))
   end)
   it("should return false if table is not empty", function()
      assert.is.False(utils.is_empty({ 1, 2, 3 }))
   end)
   it("should return true if string is nil or empty", function()
      assert.is.True(utils.is_empty(""))
   end)
   it("should return false if string is not empty", function()
      assert.is.False(utils.is_empty("test"))
      assert.is.False(utils.is_empty(" "))
   end)
end)

describe("trim_leading()", function()
   it("should trim leading whitespaces", function()
      assert.are.Same(utils.trim_leading("  \t\t\n  test \t"), "test \t")
   end)
end)
