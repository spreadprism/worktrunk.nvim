--- A one-line floating input backed by a *real* buffer.
---
--- `vim.ui.input()` is either a cmdline prompt or whatever the user's UI plugin
--- provides, and neither gives us a buffer we control. Completion engines
--- (blink.cmp, nvim-cmp, ...) attach per buffer and are configured per
--- filetype, so this window uses a normal scratch buffer with a dedicated
--- filetype — `worktrunk-input`, plus `b:worktrunk_input` describing what is
--- being asked. A blink source for branch names can then be wired with:
---
--- ```lua
--- require("blink.cmp").setup({
---   sources = { per_filetype = { ["worktrunk-input"] = { "worktrunk" } } },
--- })
--- ```
local M = {}

M.filetype = "worktrunk-input"

---@class Worktrunk.InputOpts
---@field prompt? string text shown in the window title
---@field default? string initial content, cursor placed after it
---@field kind? string what is being asked, exposed as `b:worktrunk_input`
---@field width? integer window width in columns (default 60)

---@param win integer
---@param buf integer
local function close(win, buf)
	if vim.api.nvim_win_is_valid(win) then
		vim.api.nvim_win_close(win, true)
	end
	if vim.api.nvim_buf_is_valid(buf) then
		vim.api.nvim_buf_delete(buf, { force = true })
	end
end

---Open the input window and call `on_confirm` with the trimmed text, or with
---`nil` when the user cancelled or left it empty.
---@param opts? Worktrunk.InputOpts
---@param on_confirm fun(value: string|nil)
---@return integer win, integer buf
function M.open(opts, on_confirm)
	opts = opts or {}
	local default = opts.default or ""

	local buf = vim.api.nvim_create_buf(false, true)
	vim.bo[buf].buftype = "nofile"
	vim.bo[buf].bufhidden = "wipe"
	vim.bo[buf].filetype = M.filetype
	vim.b[buf].worktrunk_input = opts.kind or "branch"
	-- blink.cmp opt-in flag, for users who enable it per buffer
	vim.b[buf].completion = true
	vim.api.nvim_buf_set_lines(buf, 0, -1, false, { default })

	local width = math.min(opts.width or 60, vim.o.columns - 4)
	local win = vim.api.nvim_open_win(buf, true, {
		relative = "editor",
		row = math.floor((vim.o.lines - 3) / 2),
		col = math.floor((vim.o.columns - width) / 2),
		width = width,
		height = 1,
		style = "minimal",
		border = "rounded",
		title = " " .. (opts.prompt or "Input") .. " ",
		title_pos = "center",
	})
	vim.wo[win].winhighlight = "NormalFloat:NormalFloat,FloatBorder:FloatBorder"
	vim.wo[win].wrap = false

	local done = false
	---@param value string|nil
	local function finish(value)
		if done then
			return
		end
		done = true
		close(win, buf)
		vim.schedule(function()
			on_confirm(value)
		end)
	end

	local function confirm()
		local line = vim.api.nvim_buf_get_lines(buf, 0, 1, false)[1] or ""
		local value = vim.trim(line)
		finish(value ~= "" and value or nil)
	end

	local function cancel()
		finish(nil)
	end

	vim.keymap.set({ "i", "n" }, "<CR>", confirm, { buffer = buf, nowait = true })
	vim.keymap.set("n", "<Esc>", cancel, { buffer = buf, nowait = true })
	vim.keymap.set("n", "q", cancel, { buffer = buf, nowait = true })
	vim.keymap.set("i", "<C-c>", cancel, { buffer = buf, nowait = true })

	-- leaving the window is a cancel; the buffer is wiped either way
	vim.api.nvim_create_autocmd({ "WinLeave", "BufLeave" }, {
		buffer = buf,
		once = true,
		callback = cancel,
	})

	vim.cmd.startinsert()
	vim.api.nvim_win_set_cursor(win, { 1, #default })

	return win, buf
end

return M
