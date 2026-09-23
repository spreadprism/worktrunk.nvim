local log = require("worktrunk.log")

local M = {}

---@class Worktrunk.Hooks
---@field on_switch fun(event: Worktrunk.SwitchEvent) run after a switch
---completed, i.e. after the `tcd` and the `auto_buffer` shuffle

---@class Worktrunk.Config
---@field bin string `wt` binary to run
---@field auto_cd boolean `tcd` into the worktree after a switch
---@field auto_buffer boolean on switch, drop the old worktree's buffers and
---reopen the current file's counterpart (or the startup empty buffer)
---@field hooks Worktrunk.Hooks user callbacks
M.defaults = {
	bin = "wt",
	auto_cd = true,
	auto_buffer = true,
	hooks = {
		---@param _event Worktrunk.SwitchEvent
		on_switch = function(_event) end,
	},
}

---@type Worktrunk.Config
M.options = nil

---@type Worktrunk.Config
M.config = nil

---@param opts? Worktrunk.Config
function M.setup(opts)
	if M.options ~= nil then
		log.warn("setup() called more than once, overriding previous options")
	end
	M.options = opts or {}
	M.config = nil
end

---@return Worktrunk.Config
function M.get()
	if M.config == nil then
		M.config = vim.tbl_deep_extend("force", M.defaults, M.options or {})
	end

	return M.config
end

return M
