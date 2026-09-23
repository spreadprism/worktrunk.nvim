--- User callbacks from `config.hooks`, dispatched defensively: a hook that
--- throws is reported but never breaks the command that fired it.
local config = require("worktrunk.config")
local log = require("worktrunk.log")

local M = {}

---@class Worktrunk.SwitchEvent
---@field branch string|nil branch that is now checked out
---@field path string worktree nvim moved into
---@field from string|nil worktree nvim came from
---@field action string|nil what `wt switch` did: "switched", "created", "already_at", ...
---@field created boolean whether the worktree was created by this switch

---Run a hook by name with `event`.
---@param name string
---@param event table
function M.emit(name, event)
	local hooks = config.get().hooks or {}
	local hook = hooks[name]
	if type(hook) ~= "function" then
		return
	end

	local ok, err = pcall(hook, event)
	if not ok then
		log.err(("hooks.%s failed: %s"):format(name, tostring(err)))
	end
end

---@param event Worktrunk.SwitchEvent
function M.on_switch(event)
	M.emit("on_switch", event)
end

return M
