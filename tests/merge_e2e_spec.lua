---@diagnostic disable: duplicate-set-field
--- End-to-end merge test: no stubs, a real git repo and the real `wt` binary.
--- Skipped when `wt` is not on PATH.

local worktrunk = require("worktrunk")
local config = require("worktrunk.config")

local has_wt = vim.fn.executable("wt") == 1

local function git(cwd, ...)
	local result = vim.system({ "git", ... }, { cwd = cwd, text = true }):wait()
	assert.are.equal(0, result.code, "git " .. table.concat({ ... }, " ") .. ": " .. (result.stderr or ""))
	return vim.trim(result.stdout or "")
end

---A fresh repo with one commit on `main` plus a `feature` worktree.
---@return string root, string base, string feature
local function fixture()
	local root = vim.fn.tempname()
	vim.fn.mkdir(root, "p")
	local base = root .. "/repo"

	git(root, "init", "-q", "-b", "main", "repo")
	git(base, "config", "user.email", "test@example.com")
	git(base, "config", "user.name", "test")
	git(base, "config", "commit.gpgsign", "false")
	vim.fn.writefile({ "hi" }, base .. "/f")
	git(base, "add", "f")
	git(base, "commit", "-qm", "init")

	local created = vim.system({ "wt", "switch", "-c", "feature", "-b", "main", "--no-cd" }, { cwd = base }):wait()
	assert.are.equal(0, created.code, created.stderr)

	return root, base, root .. "/repo.feature"
end

---`wt merge` removes the worktree in the background; give it a moment.
local function wait_until(predicate, timeout)
	return vim.wait(timeout or 5000, predicate, 50)
end

describe("merge (real wt)", function()
	local cwd, root, notifications

	before_each(function()
		if not has_wt then
			return
		end
		cwd = vim.uv.cwd()
		notifications = {}
		config.options, config.config = nil, nil
		require("worktrunk.cache").invalidate()
		worktrunk.setup({ auto_cd = true })

		---@diagnostic disable-next-line: duplicate-set-field
		vim.notify = function(msg, level)
			table.insert(notifications, { msg = msg, level = level })
		end
	end)

	after_each(function()
		if cwd then
			vim.cmd.cd(cwd)
		end
		if root then
			vim.fn.delete(root, "rf")
			root = nil
		end
	end)

	local function errors()
		return vim.tbl_map(function(n)
			return n.msg
		end, vim.tbl_filter(function(n)
			return n.level == vim.log.levels.ERROR
		end, notifications))
	end

	it("merges the current worktree into main and lands on the base", function()
		if not has_wt then
			pending("wt not installed")
			return
		end

		local base, feature
		root, base, feature = fixture()

		vim.cmd.cd(feature)
		vim.fn.writefile({ "change" }, feature .. "/f2")

		worktrunk.merge({ target = "main" })

		assert.are.same({}, errors())

		-- the change landed on main
		assert.are.equal("change", git(base, "show", "main:f2"))

		-- nvim followed the target
		assert.are.equal(vim.fs.normalize(base), vim.fs.normalize(vim.uv.cwd()))

		-- and the merged worktree was removed (background job)
		assert.is_true(wait_until(function()
			return vim.fn.isdirectory(feature) == 0
		end), "feature worktree was not removed")
	end)

	it("keeps the worktree with no_remove but still switches to the target", function()
		if not has_wt then
			pending("wt not installed")
			return
		end

		local base, feature
		root, base, feature = fixture()

		vim.cmd.cd(feature)
		vim.fn.writefile({ "change" }, feature .. "/f2")

		worktrunk.merge({ target = "main", no_remove = true })

		assert.are.same({}, errors())
		assert.are.equal("change", git(base, "show", "main:f2"))
		assert.are.equal(vim.fs.normalize(base), vim.fs.normalize(vim.uv.cwd()))
		assert.are.equal(1, vim.fn.isdirectory(feature))
	end)
end)
