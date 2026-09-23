local buffer = require("worktrunk.buffer")

local function tmpdir(name)
	local dir = vim.fs.normalize(vim.fn.tempname() .. "-" .. name)
	vim.fn.mkdir(dir .. "/lua", "p")
	return dir
end

describe("buffer.relative", function()
	it("returns the path relative to the root", function()
		assert.are.equal("lua/init.lua", buffer.relative("/repo/lua/init.lua", "/repo"))
		assert.are.equal("", buffer.relative("/repo", "/repo/"))
	end)

	it("returns nil outside the root", function()
		assert.is_nil(buffer.relative("/other/init.lua", "/repo"))
		assert.is_nil(buffer.relative("/repo-2/init.lua", "/repo"))
		assert.is_nil(buffer.relative("", "/repo"))
		assert.is_nil(buffer.relative("/repo/init.lua", nil))
	end)
end)

describe("buffer.split_scheme", function()
	it("splits a scheme buffer name", function()
		local scheme, path = buffer.split_scheme("oil:///repo/lua")
		assert.are.equal("oil://", scheme)
		assert.are.equal("/repo/lua", path)
	end)

	it("leaves plain names alone", function()
		local scheme, path = buffer.split_scheme("/repo/lua/init.lua")
		assert.are.equal("", scheme)
		assert.are.equal("/repo/lua/init.lua", path)

		scheme, path = buffer.split_scheme("")
		assert.are.equal("", scheme)
		assert.is_nil(path)
	end)
end)

describe("buffer.counterpart", function()
	local old, new

	before_each(function()
		old, new = tmpdir("old"), tmpdir("new")
		vim.fn.writefile({ "-- old" }, old .. "/lua/init.lua")
		vim.fn.writefile({ "-- new" }, new .. "/lua/init.lua")
		vim.fn.writefile({ "-- only" }, old .. "/lua/only.lua")
	end)

	after_each(function()
		vim.fn.delete(old, "rf")
		vim.fn.delete(new, "rf")
	end)

	it("maps a file that exists in both worktrees", function()
		assert.are.equal(new .. "/lua/init.lua", buffer.counterpart(old .. "/lua/init.lua", old, new))
	end)

	it("returns nil when the file is missing in the new worktree", function()
		assert.is_nil(buffer.counterpart(old .. "/lua/only.lua", old, new))
	end)

	it("returns nil for a buffer outside the old worktree", function()
		assert.is_nil(buffer.counterpart("/elsewhere/init.lua", old, new))
		assert.is_nil(buffer.counterpart("", old, new))
	end)

	it("maps an oil directory buffer, root included", function()
		assert.are.equal("oil://" .. new .. "/lua", buffer.counterpart("oil://" .. old .. "/lua", old, new))
		assert.are.equal("oil://" .. new, buffer.counterpart("oil://" .. old, old, new))
	end)

	it("returns nil when the directory is missing in the new worktree", function()
		vim.fn.mkdir(old .. "/only", "p")
		assert.is_nil(buffer.counterpart("oil://" .. old .. "/only", old, new))
	end)

	it("never maps a plain directory path", function()
		assert.is_nil(buffer.counterpart(old .. "/lua", old, new))
	end)

	-- the `~/platform` -> `~/platform.test` sibling layout: the new root is a
	-- string prefix of nothing, and the old root is a prefix of the new one
	it("maps sibling worktree roots", function()
		local root = vim.fs.normalize(vim.fn.tempname() .. "-siblings")
		vim.fn.mkdir(root .. "/platform/lua", "p")
		vim.fn.mkdir(root .. "/platform.test/lua", "p")
		local base, test = root .. "/platform", root .. "/platform.test"

		assert.are.equal("oil://" .. test, buffer.counterpart("oil://" .. base, base, test))
		assert.are.equal("oil://" .. base, buffer.counterpart("oil://" .. test, test, base))
		assert.are.equal("oil://" .. test .. "/lua", buffer.counterpart("oil://" .. base .. "/lua", base, test))
		-- ...and `platform.test` must not be treated as living inside `platform`
		assert.is_nil(buffer.counterpart("oil://" .. test, base, test))

		vim.fn.delete(root, "rf")
	end)
end)

describe("buffer.locate", function()
	local lines = { "local a = 1", "", "local b = 2", "return a" }

	it("prefers the exact same line", function()
		local line, exact = buffer.locate({ line = 1, col = 0, text = "return a" }, lines)
		assert.are.equal(4, line)
		assert.True(exact)
	end)

	it("picks the occurrence nearest the old line number", function()
		local dup = { "x", "y", "x", "y", "x" }
		assert.are.equal(3, buffer.locate({ line = 3, col = 0, text = "x" }, dup))
		assert.are.equal(1, buffer.locate({ line = 1, col = 0, text = "x" }, dup))
		assert.are.equal(5, buffer.locate({ line = 5, col = 0, text = "x" }, dup))
	end)

	it("falls back to the same line number", function()
		local line, exact = buffer.locate({ line = 3, col = 0, text = "gone" }, lines)
		assert.are.equal(3, line)
		assert.False(exact)
	end)

	it("clamps past the end of the buffer", function()
		assert.are.equal(4, buffer.locate({ line = 99, col = 0, text = nil }, lines))
		assert.are.equal(1, buffer.locate({ line = 99, col = 0, text = "x" }, {}))
	end)

	it("ignores blank lines, which match anywhere", function()
		local line, exact = buffer.locate({ line = 4, col = 0, text = "" }, lines)
		assert.are.equal(4, line)
		assert.False(exact)
	end)
end)

describe("buffer.migrate", function()
	local old, new

	local function open(path)
		vim.cmd.edit(vim.fn.fnameescape(path))
		return vim.api.nvim_get_current_buf()
	end

	before_each(function()
		old, new = tmpdir("old"), tmpdir("new")
		for _, root in ipairs({ old, new }) do
			vim.fn.writefile({ "-- " .. root }, root .. "/lua/init.lua")
		end
		vim.fn.writefile({ "-- only" }, old .. "/lua/only.lua")
		vim.cmd("silent! %bwipeout!")
	end)

	after_each(function()
		vim.cmd("silent! %bwipeout!")
		vim.fn.delete(old, "rf")
		vim.fn.delete(new, "rf")
	end)

	it("switches to the counterpart and drops the old buffers", function()
		local stale = open(old .. "/lua/only.lua")
		open(old .. "/lua/init.lua")

		buffer.migrate(old, new)

		assert.are.equal(new .. "/lua/init.lua", vim.fs.normalize(vim.api.nvim_buf_get_name(0)))
		assert.False(vim.api.nvim_buf_is_valid(stale) and vim.bo[stale].buflisted)
		assert.are.same({}, buffer.buffers_in(old))
	end)

	it("lands on an empty buffer when the file is gone", function()
		open(old .. "/lua/only.lua")

		buffer.migrate(old, new)

		assert.are.equal("", vim.api.nvim_buf_get_name(0))
		assert.are.same({}, buffer.buffers_in(old))
	end)

	it("keeps buffers from outside the old worktree", function()
		local outside = open(new .. "/lua/init.lua")
		open(old .. "/lua/only.lua")

		buffer.migrate(old, new)

		assert.True(vim.api.nvim_buf_is_valid(outside))
		assert.True(vim.bo[outside].buflisted)
	end)

	it("follows an oil buffer to the new worktree", function()
		local stale = open(old .. "/lua/only.lua")
		open("oil://" .. old .. "/lua")

		buffer.migrate(old, new)

		local scheme, path = buffer.split_scheme(vim.api.nvim_buf_get_name(0))
		assert.are.equal("oil://", scheme)
		assert.are.equal(new .. "/lua", vim.fs.normalize(path):gsub("/+$", ""))
		assert.False(vim.api.nvim_buf_is_valid(stale) and vim.bo[stale].buflisted)
		assert.are.same({}, buffer.buffers_in(old))
	end)

	it("keeps the cursor on the same line of text", function()
		vim.fn.writefile({ "-- header", "local a = 1", "return a" }, old .. "/lua/shift.lua")
		vim.fn.writefile({ "-- header", "-- extra", "-- extra", "local a = 1", "return a" }, new .. "/lua/shift.lua")

		open(old .. "/lua/shift.lua")
		vim.api.nvim_win_set_cursor(0, { 2, 6 })

		buffer.migrate(old, new)

		assert.are.same({ 4, 6 }, vim.api.nvim_win_get_cursor(0))
	end)

	it("falls back to the same line number and clamps the column", function()
		vim.fn.writefile({ "-- header", "local gone = 1", "return 1" }, old .. "/lua/shift.lua")
		vim.fn.writefile({ "-- header", "ab", "return 1" }, new .. "/lua/shift.lua")

		open(old .. "/lua/shift.lua")
		vim.api.nvim_win_set_cursor(0, { 2, 10 })

		buffer.migrate(old, new)

		-- "ab" is 2 chars, and normal mode caps the column at the last one
		assert.are.same({ 2, 1 }, vim.api.nvim_win_get_cursor(0))
	end)

	it("does nothing when the roots are the same", function()
		local buf = open(old .. "/lua/init.lua")
		buffer.migrate(old, old)
		assert.are.equal(buf, vim.api.nvim_get_current_buf())
	end)

	it("never deletes modified buffers", function()
		local dirty = open(old .. "/lua/only.lua")
		vim.api.nvim_buf_set_lines(dirty, 0, -1, false, { "unsaved" })

		buffer.migrate(old, new)

		assert.True(vim.api.nvim_buf_is_valid(dirty))
		assert.True(vim.bo[dirty].modified)
	end)
end)
