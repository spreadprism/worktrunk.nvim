local log = require("worktrunk.log")

local M = {}

---@class Worktrunk.Config
---@field bin string
---@field auto_cd boolean
M.defaults = {
	bin = "wt",
	auto_cd = true,
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
