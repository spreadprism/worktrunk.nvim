--- Public API. This module only wires the plugin's parts together; every
--- behaviour lives in its own module:
---
---   worktrunk.cli       argv builders for the `wt` binary
---   worktrunk.cache     stale-while-revalidate cache over `wt list`
---   worktrunk.worktree  read-only queries over `wt list`
---   worktrunk.actions   switch / create / delete / merge
---   worktrunk.picker    snacks.nvim picker
---   worktrunk.input     floating one-line input (completion friendly)
---   worktrunk.config    user options
---   worktrunk.log       notifications
---   worktrunk.types     LuaCATS definitions
local actions = require("worktrunk.actions")
local config = require("worktrunk.config")
local worktree = require("worktrunk.worktree")

require("worktrunk.types")

local M = {}

--- configure the plugin
---@param opts? Worktrunk.Config
function M.setup(opts)
	config.setup(opts)
	-- warm the picker's query in the background so even the first open is
	-- served from cache (outside a repo this fails silently and caches nothing)
	require("worktrunk.cache").prefetch({ branches = true, remotes = true })
end

--- returns a list of worktrees
M.list = worktree.list

--- the repository's base (primary) worktree
M.base = worktree.base

--- the worktree nvim is currently in
M.current = worktree.current

--- find a worktree by branch name or by path
M.find = worktree.find

--- the label a worktree is addressed by
M.name = worktree.name

--- switch to the given worktree, if nil open a snack picker with choices
M.switch = actions.switch

--- create a branch and its worktree, then switch to it,
--- if nil open the worktree creation input
M.create = actions.create

--- delete given worktree, if currently on deleted worktree,
--- switch to base worktree, deletes current worktree if none given
--- refuses to delete base worktree
M.delete = actions.delete

--- merge current worktree into a target (don't merge from the base worktree),
--- if no target is given open the picker to choose one;
--- `opts` maps every `wt merge` flag (see `Worktrunk.MergeOpts`)
---@type fun(opts?: Worktrunk.MergeOpts)
M.merge = actions.merge

--- open the worktree picker
---@param opts? Worktrunk.PickerConfig
---@param on_choice? fun(worktree: Worktrunk.Worktree)
function M.pick(opts, on_choice)
	return require("worktrunk.picker").pick(opts, on_choice)
end

return M
