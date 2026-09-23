--- Notification helpers: every message is prefixed with the plugin name.
local M = {}

M.prefix = "worktrunk: "

---@param msg string
---@param level integer
function M.notify(msg, level)
	vim.notify(M.prefix .. msg, level)
end

---@param msg string
function M.err(msg)
	M.notify(msg, vim.log.levels.ERROR)
end

---@param msg string
function M.warn(msg)
	M.notify(msg, vim.log.levels.WARN)
end

---@param msg string
function M.info(msg)
	M.notify(msg, vim.log.levels.INFO)
end

---@param msg string
function M.debug(msg)
	M.notify(msg, vim.log.levels.DEBUG)
end

return M
