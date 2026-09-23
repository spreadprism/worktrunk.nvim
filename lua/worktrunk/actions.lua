--- The commands the plugin exposes: switch, create, delete, merge.
local cli = require("worktrunk.cli")
local config = require("worktrunk.config")
local log = require("worktrunk.log")
local worktree = require("worktrunk.worktree")

require("worktrunk.types")

local M = {}

---The most useful message out of a failed `wt` run.
---@param result vim.SystemCompleted
---@return string
local function output(result)
	local text = result.stderr
	if text == nil or text == "" then
		text = result.stdout or ""
	end
	return vim.trim(text)
end

---First line of stdout, decoded as JSON.
---@param result vim.SystemCompleted
---@return table|nil
local function decode(result)
	local ok, decoded = pcall(vim.json.decode, vim.split(vim.trim(result.stdout or ""), "\n")[1])
	if ok and type(decoded) == "table" then
		return decoded
	end
	return nil
end

---@param path string
local function cd(path)
	if config.get().auto_cd then
		vim.cmd.tcd(vim.fn.fnameescape(path))
	end
end

---`wt` does the cd through shell integration we don't have, so every switch
---runs with --no-cd and chdirs nvim from the returned path.
---@param opts worktrunk.SwitchOpts
---@return table|nil result decoded `{action, branch, path}`
local function run_switch(opts)
	local result = cli.switch(vim.tbl_extend("force", opts, { no_cd = true, yes = true, format = "json" })) --[[@as vim.SystemCompleted]]
	if result.code ~= 0 then
		log.err(output(result))
		return nil
	end

	local decoded = decode(result)
	if not decoded or not decoded.path then
		log.err("could not parse switch result for " .. tostring(opts.branch))
		return nil
	end

	cd(decoded.path)
	return decoded
end

--- switch to the given worktree, if nil open a snack picker with choices
---@param worktree_name? string
function M.switch(worktree_name)
	if not worktree_name then
		return require("worktrunk.picker").pick(nil, function(wt)
			M.switch(worktree.name(wt))
		end)
	end

	local decoded = run_switch({ branch = worktree_name })
	if decoded then
		log.info("switched to " .. (decoded.branch or decoded.path))
	end
end

---Create a branch and its worktree, then switch to it.
---@param branch string
---@param base? string
function M.create(branch, base)
	if run_switch({ branch = branch, base = base, create = true }) then
		log.info("created " .. branch)
	end
end

--- delete given worktree, if currently on deleted worktree,
--- switch to base worktree, deletes current worktree if none given
--- refuses to delete base worktree
---@param worktree_name? string
function M.delete(worktree_name)
	local target ---@type Worktrunk.Worktree|nil
	if worktree_name then
		target = worktree.find(worktree_name)
		if not target then
			log.err("no worktree matching " .. worktree_name)
			return
		end
	else
		target = worktree.current()
		if not target then
			log.err("not inside a worktree")
			return
		end
	end

	if target.worktree and target.worktree.main then
		log.err("refusing to delete the base worktree " .. worktree.name(target))
		return
	end

	if target.worktree and target.worktree.current then
		local base = worktree.base()
		if not base then
			log.err("could not find the base worktree to switch to")
			return
		end
		M.switch(worktree.name(base))
	end

	local result = cli.remove({
		branches = { worktree.name(target) },
		foreground = true,
		yes = true,
		format = "json",
	}) --[[@as vim.SystemCompleted]]
	if result.code ~= 0 then
		log.err(output(result))
		return
	end

	log.info("deleted " .. worktree.name(target))
end

--- merge current worktree to base (don't merge if already on base)
function M.merge()
	local current = worktree.current()
	if not current then
		log.err("not inside a worktree")
		return
	end

	if current.worktree and current.worktree.main then
		log.err("already on the base worktree, nothing to merge")
		return
	end

	local base = worktree.base()

	--- `wt merge` resolves the branch from its working directory, and removes
	--- that worktree when it's done — so pin it explicitly and leave afterwards.
	local result = cli.merge({
		cwd = current.worktree and current.worktree.path,
		yes = true,
		format = "json",
	}) --[[@as vim.SystemCompleted]]
	if result.code ~= 0 then
		log.err(output(result))
		return
	end

	if base then
		M.switch(worktree.name(base))
	end
	log.info("merged " .. worktree.name(current) .. " into " .. (base and worktree.name(base) or "the default branch"))
end

return M
