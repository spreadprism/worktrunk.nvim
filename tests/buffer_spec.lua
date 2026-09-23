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
