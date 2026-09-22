local M = {}

---@class worktrunk.Config
M.defaults = {}

---@type worktrunk.Config
M.options = nil

---@param opts worktrunk.Config|nil
function M.setup(opts)
	M.options = vim.tbl_deep_extend("force", {}, M.defaults, opts or {})
	return M.options
end

---@return worktrunk.Config
function M.get()
	return M.options or M.defaults
end

return M
