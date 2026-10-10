--- The commands the plugin exposes: switch, create, delete, merge.
local buffer = require("worktrunk.buffer")
local cache = require("worktrunk.cache")
local cli = require("worktrunk.cli")
local config = require("worktrunk.config")
local hooks = require("worktrunk.hooks")
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
		vim.cmd.cd(vim.fn.fnameescape(path))
	end
end

---Where nvim sits right now: what `auto_buffer` diffs against, and what the
---`on_switch` hook reports as `from`.
---
---`cwd` overrides the directory the lookup runs from: after a merge nvim's own
---cwd can be a worktree `wt` has just deleted, and git refuses to run there.
---@param cwd string|nil
---@return string|nil
local function origin(cwd)
	local current = worktree.current({ cwd = cwd })
	return (current and current.worktree and current.worktree.path) or vim.fn.getcwd()
end

---The worktree layout just changed: drop the cache and re-warm the picker's
---query in the background so the next picker open is instant *and* fresh.
local function refetch()
	cache.invalidate()
	cache.prefetch({ branches = true, remotes = true })
end

---`wt` does the cd through shell integration we don't have, so every switch
---runs with --no-cd and chdirs nvim from the returned path.
---@param opts worktrunk.SwitchOpts
---@return table|nil result decoded `{action, branch, path}`
local function run_switch(opts)
	local from = origin(opts.cwd)

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

	-- after the cd, so the warmed entry is keyed on the new cwd
	cd(decoded.path)
	refetch()
	if from and config.get().auto_buffer then
		buffer.migrate(from, decoded.path)
	end

	-- after the cd and the buffer shuffle, so the hook sees the final state
	hooks.on_switch({
		branch = decoded.branch,
		path = decoded.path,
		from = from or nil,
		action = decoded.action,
		created = opts.create == true,
	})

	return decoded
end

--- switch to the given worktree, if nil open a snack picker with choices
---@param worktree_name? string
---@param opts? { cwd: string|nil } directory to run `wt` from (default: nvim's cwd)
function M.switch(worktree_name, opts)
	if not worktree_name then
		return require("worktrunk.picker").pick(nil, function(wt)
			M.switch(worktree.name(wt))
		end)
	end

	local decoded = run_switch({ branch = worktree_name, cwd = opts and opts.cwd })
	if decoded then
		log.info("switched to " .. (decoded.branch or decoded.path))
	end
end

--- Create a branch and its worktree, then switch to it. Missing arguments are
--- asked for in turn: the name through the worktrunk input (free text), the
--- base through the picker (an existing branch or worktree). Cancelling either
--- one aborts, and an existing branch is refused before anything is asked or
--- created.
---@param worktree_name? string
---@param base? string
function M.create(worktree_name, base)
	if not worktree_name then
		return require("worktrunk.input").open({
			prompt = "New worktree",
			kind = "branch",
		}, function(name)
			if name then
				M.create(name, base)
			end
		end)
	end

	local existing = worktree.branch(worktree_name)
	if existing then
		local where = existing.worktree and (" (" .. existing.worktree.path .. ")") or ""
		log.err("branch " .. worktree_name .. " already exists" .. where .. ", switch to it instead")
		return
	end

	if not base then
		return require("worktrunk.picker").pick({ title = "Base for " .. worktree_name }, function(wt)
			M.create(worktree_name, worktree.name(wt))
		end)
	end

	if run_switch({ branch = worktree_name, base = base, create = true }) then
		log.info("created " .. worktree_name)
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

	refetch()
	log.info("deleted " .. worktree.name(target))
end

--- Options for `M.merge`, one field per `wt merge` flag.
---
--- `cwd` and `format` are not exposed: the action pins the working directory
--- to the worktree it merges and needs JSON back to report the result.
---@class Worktrunk.MergeOpts
---@field target string|nil                 [TARGET]        Target branch. Omit to pick one from the worktree picker.
---@field no_squash boolean|nil             --no-squash     Skip commit squashing
---@field no_commit boolean|nil             --no-commit     Skip commit and squash
---@field no_rebase boolean|nil             --no-rebase     Skip rebase; require a fast-forward
---@field no_remove boolean|nil             --no-remove     Keep worktree after merge
---@field no_ff boolean|nil                 --no-ff         Create a merge commit
---@field stage "all"|"tracked"|"none"|nil  --stage <STAGE> What to stage before committing [default: all]
---@field no_hooks boolean|nil              --no-hooks      Skip hooks
---@field config string|nil                 --config <path> User config file path
---@field config_set string[]|string|nil    --config-set <toml> Inline TOML overrides (repeatable)
---@field verbose integer|nil               -v...           0|1|2 verbosity
---@field yes boolean|nil                   -y, --yes       Skip approval prompts [default: true]

--- Merge the current worktree into a target branch (never from the base
--- worktree). Without `target` the picker asks for one; cancelling aborts.
--- Afterwards nvim follows the target, whether or not `no_remove` keeps the
--- merged worktree alive.
---@param opts? Worktrunk.MergeOpts
function M.merge(opts)
	opts = opts or {}

	local current = worktree.current()
	if not current then
		log.err("not inside a worktree")
		return
	end

	if current.worktree and current.worktree.main then
		log.err("already on the base worktree, nothing to merge")
		return
	end

	if not opts.target then
		return require("worktrunk.picker").pick({ title = "Merge " .. worktree.name(current) .. " into" }, function(wt)
			M.merge(vim.tbl_extend("force", opts, { target = worktree.name(wt) }))
		end)
	end

	-- where to land afterwards: the target's worktree if it has one, else base
	local destination = worktree.find(opts.target) or worktree.base()
	local destination_path = destination and destination.worktree and destination.worktree.path
	local source_path = current.worktree and current.worktree.path

	--- `wt merge` resolves the branch from its working directory, and removes
	--- that worktree when it's done — so pin it explicitly and leave afterwards.
	local result = cli.merge(vim.tbl_extend("force", { yes = true }, opts, {
		cwd = current.worktree and current.worktree.path,
		format = "json",
	})) --[[@as vim.SystemCompleted]]
	if result.code ~= 0 then
		log.err(output(result))
		return
	end

	-- everything the cache knows predates the merge; the follow-up switch
	-- re-warms it (run_switch), so only drop it here
	cache.invalidate()

	-- `wt merge` removes the merged worktree in a background job that holds the
	-- repository locks; switching on top of it races with `.git/index.lock`.
	local merged = decode(result) or {}
	if merged.removed and source_path then
		vim.wait(5000, function()
			return vim.fn.isdirectory(source_path) == 0
		end, 50)
	end

	-- follow the target either way: the worktree we merged from is usually gone,
	-- and with --no-remove it survives but we still want to land on the target.
	-- run the switch from the destination: nvim's cwd may be the deleted worktree.
	if destination then
		M.switch(worktree.name(destination), { cwd = destination_path })
	end
	log.info("merged " .. worktree.name(current) .. " into " .. opts.target)
end

return M
