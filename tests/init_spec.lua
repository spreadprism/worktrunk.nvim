---@diagnostic disable: duplicate-set-field

local worktrunk = require("worktrunk")
local config = require("worktrunk.config")
local cli = require("worktrunk.cli")

---@return Worktrunk.Worktree
local function wt(branch, opts)
	opts = opts or {}
	local info = nil
	if not opts.bare then
		info = {
			path = "/repo." .. branch,
			main = opts.main or false,
			current = opts.current or false,
			previous = false,
			detached = false,
			branch_mismatch = false,
			duplicate_branch = false,
			changes = {
				staged = false,
				modified = false,
				untracked = false,
				renamed = false,
				deleted = false,
				conflicted = false,
				diff = { added = 0, deleted = 0 },
			},
		}
	end
	return {
		branch = branch,
		head = { sha = "0", short_sha = "0", subject = "s", committed_at = "2026-01-01T00:00:00Z" },
		worktree = info,
		display = { symbols = "", statusline = "" },
	}
end

local function stub_list(items)
	cli.list_json = function()
		return { schema = 2, repo = { default_branch = "main" }, collected = {}, items = items }, nil
	end
end

describe("worktrunk", function()
	local calls, notifications
	local real = {}

	before_each(function()
		calls, notifications = {}, {}
		config.options, config.config = nil, nil

		for _, name in ipairs({ "list_json", "switch", "remove", "merge" }) do
			real[name] = cli[name]
		end
		for _, name in ipairs({ "switch", "remove", "merge" }) do
			cli[name] = function(opts)
				table.insert(calls, { cmd = name, opts = opts })
				return { code = 0, stdout = '{"action":"switched","branch":"main","path":"/repo.main"}', stderr = "" }
			end
		end

		real.notify = vim.notify
		vim.notify = function(msg, level)
			table.insert(notifications, { msg = msg, level = level })
		end

		stub_list({ wt("main", { main = true }), wt("feature", { current = true }) })
		worktrunk.setup({ auto_cd = false })
	end)

	after_each(function()
		for name, fn in pairs(real) do
			if name == "notify" then
				vim.notify = fn
			else
				cli[name] = fn
			end
		end
	end)

	local function last_error()
		for i = #notifications, 1, -1 do
			if notifications[i].level == vim.log.levels.ERROR then
				return notifications[i].msg
			end
		end
	end

	describe("list", function()
		it("returns only rows backed by a worktree", function()
			stub_list({ wt("main", { main = true }), wt("stale", { bare = true }) })
			local items = worktrunk.list()
			assert.are.equal(1, #items)
			assert.are.equal("main", items[1].branch)
		end)

		it("finds the base and current worktrees", function()
			assert.are.equal("main", worktrunk.base().branch)
			assert.are.equal("feature", worktrunk.current().branch)
		end)

		it("finds a worktree by branch or path", function()
			assert.are.equal("feature", worktrunk.find("feature").branch)
			assert.are.equal("feature", worktrunk.find("/repo.feature").branch)
			assert.is_nil(worktrunk.find("nope"))
		end)
	end)

	describe("switch", function()
		it("fires hooks.on_switch once the switch landed", function()
			local seen
			config.options, config.config = nil, nil
			worktrunk.setup({
				auto_cd = false,
				auto_buffer = false,
				hooks = {
					on_switch = function(event)
						seen = event
					end,
				},
			})

			worktrunk.switch("main")

			assert.are.equal("main", seen.branch)
			assert.are.equal("/repo.main", seen.path)
			assert.are.equal("switched", seen.action)
			assert.False(seen.created)
		end)

		it("switches with --no-cd and json output", function()
			worktrunk.switch("main")
			assert.are.equal("switch", calls[1].cmd)
			assert.are.equal("main", calls[1].opts.branch)
			assert.True(calls[1].opts.no_cd)
			assert.are.equal("json", calls[1].opts.format)
		end)
	end)

	describe("delete", function()
		it("refuses to delete the base worktree", function()
			worktrunk.delete("main")
			assert.are.equal(0, #calls)
			assert.matches("refusing to delete the base worktree", last_error())
		end)

		it("defaults to the current worktree and switches to base first", function()
			worktrunk.delete()
			assert.are.equal("switch", calls[1].cmd)
			assert.are.equal("main", calls[1].opts.branch)
			assert.are.equal("remove", calls[2].cmd)
			assert.same({ "feature" }, calls[2].opts.branches)
		end)

		it("removes another worktree without switching", function()
			stub_list({ wt("main", { main = true, current = true }), wt("feature") })
			worktrunk.delete("feature")
			assert.are.equal(1, #calls)
			assert.are.equal("remove", calls[1].cmd)
			assert.same({ "feature" }, calls[1].opts.branches)
		end)

		it("errors on an unknown worktree", function()
			worktrunk.delete("nope")
			assert.are.equal(0, #calls)
			assert.matches("no worktree matching nope", last_error())
		end)
	end)

	describe("merge", function()
		it("merges from the current worktree then switches to base", function()
			worktrunk.merge()
			assert.are.equal("merge", calls[1].cmd)
			assert.are.equal("/repo.feature", calls[1].opts.cwd)
			assert.are.equal("switch", calls[2].cmd)
			assert.are.equal("main", calls[2].opts.branch)
		end)

		it("does nothing when already on base", function()
			stub_list({ wt("main", { main = true, current = true }) })
			worktrunk.merge()
			assert.are.equal(0, #calls)
			assert.matches("already on the base worktree", last_error())
		end)
	end)
end)
