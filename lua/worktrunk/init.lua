--- Public API. This module only wires the plugin's parts together; every
--- behaviour lives in its own module:
---
---   worktrunk.cli       argv builders for the `wt` binary
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
M.setup = config.setup

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

--- merge current worktree to base (don't merge if already on base)
M.merge = actions.merge

--- open the worktree picker
---@param opts? Worktrunk.PickerConfig
---@param on_choice? fun(worktree: Worktrunk.Worktree)
function M.pick(opts, on_choice)
	return require("worktrunk.picker").pick(opts, on_choice)
end

return M
