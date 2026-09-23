--- `auto_buffer`: keep the buffer list in sync with the worktree we switched to.
---
--- On switch:
---   1. every buffer belonging to the old worktree is unlisted/deleted;
---   2. if the file open in the current buffer also exists in the new worktree,
---      its counterpart is opened;
---   3. otherwise we land on the empty buffer nvim shows at startup.
---
--- When a counterpart is opened, the cursor follows: onto the line holding the
--- exact same text when it's still there, onto the same line number otherwise.
local log = require("worktrunk.log")

local M = {}

---@param path string|nil
---@return string|nil
local function normalize(path)
	if path == nil or path == "" then
		return nil
	end
	return (vim.fs.normalize(vim.fn.fnamemodify(path, ":p")):gsub("/+$", ""))
end

---Buffers like oil's are named `oil:///abs/path`: a scheme glued to a real
---path. Split it so the path half can be treated like any other file.
---@param name string|nil
---@return string scheme `""` for plain files
---@return string|nil path
function M.split_scheme(name)
	if name == nil or name == "" then
		return "", nil
	end
	local scheme, rest = name:match("^(%a[%w+.-]*://)(.*)$")
	if scheme and rest ~= "" and rest:sub(1, 1) == "/" then
		return scheme, rest
	end
	return "", name
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
		local _, path = M.split_scheme(vim.api.nvim_buf_get_name(buf))
		if vim.bo[buf].buflisted and M.relative(path, root) then
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
	local scheme
	scheme, path = M.split_scheme(path)

	local rel = M.relative(path, old_root)
	if not rel then
		return nil
	end
	-- the worktree root itself only means something for a scheme buffer
	-- (an oil listing of the root); a plain file never sits there
	if rel == "" and scheme == "" then
		return nil
	end

	local candidate = normalize(new_root)
	if not candidate then
		return nil
	end
	if rel ~= "" then
		candidate = candidate .. "/" .. rel
	end

	local stat = vim.uv.fs_stat(candidate)
	if not stat then
		return nil
	end
	-- directories are only openable through a scheme handler like oil
	if stat.type == "file" or (scheme ~= "" and stat.type == "directory") then
		return scheme .. candidate
	end
	return nil
end

---@class worktrunk.Cursor
---@field line integer 1-based line the cursor sat on
---@field col integer 0-based column
---@field text string|nil the text of that line, to look for in the counterpart

---Snapshot of where the cursor sits in `win`.
---@param win integer
---@return worktrunk.Cursor|nil
function M.cursor(win)
	if not vim.api.nvim_win_is_valid(win) then
		return nil
	end
	local line, col = unpack(vim.api.nvim_win_get_cursor(win))
	local text = vim.api.nvim_buf_get_lines(vim.api.nvim_win_get_buf(win), line - 1, line, false)[1]
	return { line = line, col = col, text = text }
end

---Where `cursor` should land in `lines`: the nearest line with the exact same
---text, else the same line number, clamped to the buffer.
---@param cursor worktrunk.Cursor
---@param lines string[]
---@return integer line 1-based
---@return boolean exact whether the original line text was found
function M.locate(cursor, lines)
	local count = math.max(#lines, 1)

	-- blank lines match everywhere, so they say nothing about where we were
	if cursor.text and vim.trim(cursor.text) ~= "" then
		local best ---@type integer|nil
		for i, line in ipairs(lines) do
			if line == cursor.text then
				if not best or math.abs(i - cursor.line) < math.abs(best - cursor.line) then
					best = i
				end
			end
		end
		if best then
			return best, true
		end
	end

	return math.min(cursor.line, count), false
end

---Apply `cursor` to `win`, returning whether the exact line was found.
---@param win integer
---@param cursor worktrunk.Cursor
---@return boolean exact
local function place(win, cursor)
	local buf = vim.api.nvim_win_get_buf(win)
	local lines = vim.api.nvim_buf_get_lines(buf, 0, -1, false)
	local line, exact = M.locate(cursor, lines)
	local col = math.max(math.min(cursor.col, #(lines[line] or "")), 0)
	pcall(vim.api.nvim_win_set_cursor, win, { line, col })
	return exact
end

---Put the cursor back after the counterpart was opened.
---@param win integer
---@param cursor worktrunk.Cursor|nil
function M.restore(win, cursor)
	if not cursor or not vim.api.nvim_win_is_valid(win) then
		return
	end

	if place(win, cursor) then
		return
	end

	-- the buffer may still be filling in (oil renders its listing on the next
	-- tick), so try once more — but only if nothing moved the cursor since.
	local settled = vim.api.nvim_win_get_cursor(win)
	vim.schedule(function()
		if not vim.api.nvim_win_is_valid(win) then
			return
		end
		local now = vim.api.nvim_win_get_cursor(win)
		if now[1] == settled[1] and now[2] == settled[2] then
			place(win, cursor)
		end
	end)
end

---Move the buffer list from `old_root` to `new_root`.
---@param old_root string|nil
---@param new_root string|nil
function M.migrate(old_root, new_root)
	old_root, new_root = normalize(old_root), normalize(new_root)
	if not old_root or not new_root or old_root == new_root then
		return
	end

	-- a switch started from a prompt can still be in insert mode; the new
	-- buffer should never inherit it
	if vim.fn.mode():sub(1, 1) == "i" then
		vim.cmd.stopinsert()
	end

	local stale = M.buffers_in(old_root)
	local target = M.counterpart(vim.api.nvim_buf_get_name(0), old_root, new_root)
	local win = vim.api.nvim_get_current_win()
	local cursor = target and M.cursor(win) or nil

	-- Land somewhere outside the old worktree first, so deleting its buffers
	-- never drops us into an arbitrary leftover buffer.
	if target then
		vim.cmd.edit(vim.fn.fnameescape(target))
		M.restore(win, cursor)
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
