--- `auto_buffer`: keep the buffer list in sync with the worktree we switched to.
---
--- On switch:
---   1. every buffer belonging to the old worktree is unlisted/deleted;
---   2. if the file open in the current buffer also exists in the new worktree,
---      its counterpart is opened;
---   3. otherwise we land on the empty buffer nvim shows at startup.
local log = require("worktrunk.log")

local M = {}

---@param path string|nil
---@return string|nil
local function normalize(path)
	if path == nil or path == "" then
		return nil
	end
	return vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("/+$", "")
end

---`path` relative to `root`, or nil when it lives outside of it.
---@param path string|nil
---@param root string|nil
---@return string|nil
function M.relative(path, root)
	path, root = normalize(path), normalize(root)
	if not path or not root then
		return nil
	end
	if path == root then
		return ""
	end
	local prefix = root .. "/"
	if path:sub(1, #prefix) == prefix then
		return path:sub(#prefix + 1)
	end
	return nil
end

---Listed buffers whose file lives inside `root`.
---@param root string
---@return integer[]
function M.buffers_in(root)
	local bufs = {}
	for _, buf in ipairs(vim.api.nvim_list_bufs()) do
		if vim.bo[buf].buflisted and M.relative(vim.api.nvim_buf_get_name(buf), root) then
			table.insert(bufs, buf)
		end
	end
	return bufs
end

---The counterpart of `path` in `new_root`, when it exists on disk.
---@param path string|nil
---@param old_root string
---@param new_root string
---@return string|nil
function M.counterpart(path, old_root, new_root)
	local rel = M.relative(path, old_root)
	if not rel or rel == "" then
		return nil
	end

	local candidate = normalize(new_root) .. "/" .. rel
	local stat = vim.uv.fs_stat(candidate)
	if stat and stat.type == "file" then
		return candidate
	end
	return nil
end

---Move the buffer list from `old_root` to `new_root`.
---@param old_root string|nil
---@param new_root string|nil
function M.migrate(old_root, new_root)
	old_root, new_root = normalize(old_root), normalize(new_root)
	if not old_root or not new_root or old_root == new_root then
		return
	end

	local stale = M.buffers_in(old_root)
	local target = M.counterpart(vim.api.nvim_buf_get_name(0), old_root, new_root)

	-- Land somewhere outside the old worktree first, so deleting its buffers
	-- never drops us into an arbitrary leftover buffer.
	if target then
		vim.cmd.edit(vim.fn.fnameescape(target))
	else
		vim.cmd.enew()
	end
	local landing = vim.api.nvim_get_current_buf()

	local kept = 0
	for _, buf in ipairs(stale) do
		if buf ~= landing then
			if vim.bo[buf].modified then
				kept = kept + 1
			elseif vim.api.nvim_buf_is_valid(buf) then
				pcall(vim.api.nvim_buf_delete, buf, {})
			end
		end
	end

	if kept > 0 then
		log.warn(("kept %d unsaved buffer%s from the previous worktree"):format(kept, kept == 1 and "" or "s"))
	end
end

return M
