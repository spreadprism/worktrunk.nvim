--- Read-only queries over `wt list`.
local cli = require("worktrunk.cli")
local log = require("worktrunk.log")

require("worktrunk.types")

local M = {}

---The label a worktree is addressed by: its branch, or its path when detached.
---@param wt Worktrunk.Worktree
---@return string
function M.name(wt)
	return wt.branch or (wt.worktree and wt.worktree.path) or "(detached)"
end

---Every row of `wt list`, including branches without a worktree when asked.
---@param opts? worktrunk.ListOpts
---@return Worktrunk.Worktree[]
function M.all(opts)
	local envelope, err = cli.list_json(opts)
	if not envelope then
		log.err(err or "could not list worktrees")
		return {}
	end
	return envelope.items
end

---Only the rows backed by a worktree on disk.
---@return Worktrunk.Worktree[]
function M.list()
	return vim.tbl_filter(function(item)
		return item.worktree ~= nil
	end, M.all())
end

---The repository's base (primary) worktree.
---@return Worktrunk.Worktree|nil
function M.base()
	for _, wt in ipairs(M.list()) do
		if wt.worktree and wt.worktree.main then
			return wt
		end
	end
	return nil
end

---The worktree nvim is currently in.
---@return Worktrunk.Worktree|nil
function M.current()
	for _, wt in ipairs(M.list()) do
		if wt.worktree and wt.worktree.current then
			return wt
		end
	end
	return nil
end

---Find a worktree by branch name or by path.
---@param worktree string
---@return Worktrunk.Worktree|nil
function M.find(worktree)
	local target = vim.fs.normalize(worktree)
	for _, wt in ipairs(M.list()) do
		if wt.branch == worktree or (wt.worktree and vim.fs.normalize(wt.worktree.path) == target) then
			return wt
		end
	end
	return nil
end

return M
