--- snacks.nvim picker over `wt list`, modelled on the `wt switch` picker:
--- sigil filters (`@`, `^`, `-`, `pr:{N}`), rows for branches without a
--- worktree, multi-select removal, and create/refresh actions.
---
--- Falls back to `vim.ui.select` when snacks.nvim isn't installed.
local cli = require("worktrunk.cli")
local log = require("worktrunk.log")
local worktree = require("worktrunk.worktree")

require("worktrunk.types")

---@class Worktrunk.Picker
local M = {}

--------------------------------------------------------------------------------
-- types
--------------------------------------------------------------------------------

---@class Worktrunk.PickerItem: snacks.picker.finder.Item
---@field branch string
---@field path? string
---@field current boolean
---@field main boolean
---@field created boolean worktree already checked out on disk
---@field previous boolean previously visited worktree (`-`)
---@field remote? string remote name for remote-only branches
---@field pr? integer PR/MR number attached to the branch
---@field worktrunk Worktrunk.Worktree raw `wt list` item

---@class Worktrunk.PickerState
---@field cache table<string, Worktrunk.Worktree[]> raw `wt list` items per mode
---@field kind? Worktrunk.PickerKind last parsed sigil, to detect changes

---@class Worktrunk.PickerConfig: snacks.picker.Config
---@field branches? boolean include local branches without a worktree (default true)
---@field remotes? boolean include remote-only branches (default true)
---@field wt_state? Worktrunk.PickerState

---@alias Worktrunk.PickerKind "current"|"main"|"previous"|"pr"

--------------------------------------------------------------------------------
-- highlights
--------------------------------------------------------------------------------

-- Written as UTF-8 byte escapes so tooling can't strip the private-use
-- codepoints: U+F0765 `nf-md-circle` (filled) and U+F0766 `nf-md-circle_outline`.
local icons = {
	created = "\243\176\157\165",
	uncreated = "\243\176\157\166",
}

local hl = {
	-- same orange as the `@` gutter
	created = "SnacksPickerGitBranchCurrent",
	uncreated = "WorktrunkUncreated",
	added = "WorktrunkAdded",
	deleted = "WorktrunkDeleted",
}

---First foreground colour found among `names`, ignoring groups that only set a
---background (`DiffAdd` & friends).
---@param names string[]
---@return integer|string|nil
local function fg_of(names)
	for _, name in ipairs(names) do
		local ok, got = pcall(vim.api.nvim_get_hl, 0, { name = name, link = false })
		if ok and got and got.fg then
			return got.fg
		end
	end
end

---Blue circle for a branch without a worktree, and fg-only diff colours: the
---diffstat must never paint a background, so the colours are copied out of the
---usual git groups and re-declared with `bg = "NONE"`.
local function set_highlights()
	vim.api.nvim_set_hl(0, hl.uncreated, { fg = "#7aa2f7", default = true })
	vim.api.nvim_set_hl(0, hl.added, {
		fg = fg_of({ "Added", "diffAdded", "GitSignsAdd", "DiffAdd" }) or "#9ece6a",
		bg = "NONE",
	})
	vim.api.nvim_set_hl(0, hl.deleted, {
		fg = fg_of({ "Removed", "diffRemoved", "GitSignsDelete", "DiffDelete" }) or "#f7768e",
		bg = "NONE",
	})
end

--------------------------------------------------------------------------------
-- items
--------------------------------------------------------------------------------

---@param item Worktrunk.Worktree
---@return string
local function gutter(item)
	local info = item.worktree
	if info and info.current then
		return "@"
	elseif info and info.main then
		return "^"
	end
	return " "
end

---@param item Worktrunk.Worktree
---@return Worktrunk.PickerItem
local function to_item(item)
	local branch = item.branch or "?"
	local path = item.worktree and item.worktree.path
	local subject = item.head and item.head.subject or ""

	return {
		text = table.concat({ branch, subject }, " "),
		branch = branch,
		path = path,
		file = path,
		dir = path ~= nil,
		current = (item.worktree and item.worktree.current) or false,
		main = (item.worktree and item.worktree.main) or false,
		created = path ~= nil,
		previous = (item.worktree and item.worktree.previous) or false,
		remote = item.remote,
		pr = item.pr and item.pr.number or nil,
		worktrunk = item,
	}
end

---Rank: current worktree, then the main one, then other worktrees, then local
---branches without a worktree, then remote-only branches.
---@param item Worktrunk.PickerItem
---@return integer
local function rank(item)
	if item.current then
		return 0
	elseif item.created then
		return item.main and 1 or 2
	elseif not item.remote then
		return 3
	end
	return 4
end

---Line counts to show: uncommitted changes for a worktree, otherwise the diff
---against the default branch.
---@param raw Worktrunk.Worktree
---@return integer added, integer deleted
local function diffstat(raw)
	local d = (raw.worktree and raw.worktree.changes and raw.worktree.changes.diff)
		or (raw.default_branch and raw.default_branch.diff)
	return d and d.added or 0, d and d.deleted or 0
end

--------------------------------------------------------------------------------
-- sigil filters
--------------------------------------------------------------------------------

---`wt switch` shortcuts, typed as a prefix in the picker input:
---
---  `@`      current worktree
---  `^`      default branch
---  `-`      previous worktree
---  `pr:{N}` / `mr:{N}` PR/MR rows (all of them when `{N}` is omitted)
---
---The rest of the pattern keeps fuzzy-matching as usual.
---@param pattern string
---@return Worktrunk.PickerKind|nil kind, integer|nil number, string rest
function M.parse_pattern(pattern)
	local number, rest = pattern:match("^[pm]r:(%d*)%s*(.*)$")
	if number then
		return "pr", tonumber(number), rest
	end

	rest = pattern:match("^[pm]r%s+(.*)$") or (pattern:match("^[pm]r$") and "")
	if rest then
		return "pr", nil, rest
	end

	local sigil
	sigil, rest = pattern:match("^([@%^%-])%s*(.*)$")
	if sigil == "@" then
		return "current", nil, rest
	elseif sigil == "^" then
		return "main", nil, rest
	elseif sigil == "-" then
		return "previous", nil, rest
	end

	return nil, nil, pattern
end

---@param item Worktrunk.PickerItem
---@param kind? Worktrunk.PickerKind
---@param number? integer
---@return boolean
function M.matches_kind(item, kind, number)
	if kind == "current" then
		return item.current
	elseif kind == "main" then
		return item.main
	elseif kind == "previous" then
		return item.previous
	elseif kind == "pr" then
		return item.pr ~= nil and (number == nil or item.pr == number)
	end
	return true
end

---Filter hook: strips the sigil off the pattern before the matcher sees it and
---stashes it in `filter.meta`. Returning `true` forces the finder to re-run so
---the row set follows the sigil (cheap: `wt list` output is cached).
---@param picker snacks.Picker
---@param filter snacks.picker.Filter
---@return boolean refresh
local function transform(picker, filter)
	local opts = picker.opts --[[@as Worktrunk.PickerConfig]]
	local state = assert(opts.wt_state)
	local kind, number, rest = M.parse_pattern(filter.pattern)

	filter.pattern = rest
	filter.meta.wt_kind = kind
	filter.meta.wt_number = number

	local changed = state.kind ~= kind
	state.kind = kind
	return changed
end

--------------------------------------------------------------------------------
-- finder & format
--------------------------------------------------------------------------------

---Synchronous finder: `wt` is fast and the result is cached for the lifetime of
---the picker, so this avoids the async finder dance (snacks aborts the finder
---task on every re-find, dropping late `cb()` calls).
---
---Unlike `require("worktrunk").list()` this passes `--branches`/`--remotes` so
---branches without a worktree show up too (same set as `wt switch`).
---@param opts Worktrunk.PickerConfig
---@param ctx snacks.picker.finder.ctx
---@return Worktrunk.PickerItem[]
local function finder(opts, ctx)
	local state = assert(opts.wt_state)
	local kind, number = ctx.filter.meta.wt_kind, ctx.filter.meta.wt_number

	-- PR/MR numbers only come with `--full` (forge lookups), so pay for them
	-- lazily, when a `pr:`/`mr:` sigil is typed.
	local mode = kind == "pr" and "full" or "basic"
	local items = state.cache[mode]

	if not items then
		local envelope, err = cli.list_json({
			branches = opts.branches ~= false,
			remotes = opts.remotes ~= false,
			full = mode == "full",
		})
		if not envelope then
			log.err(err or "could not list worktrees")
			return {}
		end
		items = envelope.items
		state.cache[mode] = items
	end

	---@type Worktrunk.PickerItem[]
	local entries = {}
	for _, item in ipairs(items) do
		local entry = to_item(item)
		if M.matches_kind(entry, kind, number) then
			entry.idx = #entries + 1
			entries[#entries + 1] = entry
		end
	end

	-- stable sort: created worktrees first, keeping `wt list` order inside each
	-- group.
	table.sort(entries, function(a, b)
		local ra, rb = rank(a), rank(b)
		if ra ~= rb then
			return ra < rb
		end
		return a.idx < b.idx
	end)

	for i, entry in ipairs(entries) do
		if entry.current then
			ctx.picker.list:set_target(i)
			break
		end
	end

	return entries
end

---Columns: gutter sigil, created/not icon, branch, diffstat, commit sha.
---@param item Worktrunk.PickerItem
---@return snacks.picker.Highlight[]
local function format(item)
	local a = Snacks.picker.util.align
	local raw = item.worktrunk
	local added, deleted = diffstat(raw)
	local sha = raw.head and raw.head.short_sha or ""

	---@type snacks.picker.Highlight[]
	local ret = {}
	ret[#ret + 1] = { a(gutter(raw), 2), item.current and "SnacksPickerGitBranchCurrent" or "SnacksPickerComment" }
	ret[#ret + 1] = {
		a(item.created and icons.created or icons.uncreated, 2),
		item.created and hl.created or hl.uncreated,
	}
	ret[#ret + 1] = { " " }
	ret[#ret + 1] = { a(item.branch, 40, { truncate = true }), "SnacksPickerGitBranch" }
	ret[#ret + 1] = { " " }
	ret[#ret + 1] = { a(added > 0 and ("+%d"):format(added) or "", 7), hl.added }
	ret[#ret + 1] = { a(deleted > 0 and ("-%d"):format(deleted) or "", 7), hl.deleted }
	ret[#ret + 1] = { a(sha, 8), "SnacksPickerGitCommit" }
	return ret
end

--------------------------------------------------------------------------------
-- actions
--------------------------------------------------------------------------------

---Drop the cached `wt list` output so the next find re-runs the command.
---@param picker snacks.Picker
local function invalidate(picker)
	local state = (picker.opts --[[@as Worktrunk.PickerConfig]]).wt_state
	if state then
		state.cache = {}
	end
end

---@type table<string, snacks.picker.Action.spec>
local actions = {
	---Switch to the row under the cursor. Rows without the filled icon have no
	---worktree yet (local or remote branch); `wt switch` creates it on demand.
	worktrunk_switch = function(picker, item)
		picker:close()
		if not item then
			return
		end
		if not item.created then
			log.info("creating worktree " .. item.branch)
		end
		require("worktrunk.actions").switch(item.branch)
	end,

	---Delete every selected worktree (or the one under the cursor), with a
	---single confirmation for the whole batch.
	worktrunk_delete = function(picker)
		local items = vim.tbl_filter(function(item)
			return item.created and not item.main
		end, picker:selected({ fallback = true }))
		if #items == 0 then
			return
		end

		local branches = vim.tbl_map(function(item)
			return item.branch
		end, items)

		local prompt = #branches == 1 and ("Delete worktree %q?"):format(branches[1])
			or ("Delete %d worktrees? (%s)"):format(#branches, table.concat(branches, ", "))

		Snacks.picker.util.confirm(prompt, function()
			local actions = require("worktrunk.actions")
			for _, branch in ipairs(branches) do
				actions.delete(branch)
			end
			if not picker.closed then
				invalidate(picker)
				picker:refresh()
			end
		end)
	end,

	---Create a worktree for a *new* branch named after the typed text (like
	---`Alt-c` in the `wt switch` picker). Opens the creation input when the
	---pattern is empty.
	worktrunk_create = function(picker)
		local _, _, rest = M.parse_pattern(vim.trim(picker.input.filter.pattern))
		local branch = vim.trim(rest)
		picker:close()

		require("worktrunk.actions").create(branch ~= "" and branch or nil)
	end,

	---Re-run `wt list` (pick up worktrees created elsewhere).
	worktrunk_refresh = function(picker)
		invalidate(picker)
		picker:refresh()
	end,
}

--------------------------------------------------------------------------------
-- entry point
--------------------------------------------------------------------------------

---Fallback for when snacks.nvim isn't available.
---@param on_choice fun(worktree: Worktrunk.Worktree)
local function select(on_choice)
	vim.ui.select(worktree.list(), {
		prompt = "Worktrees",
		format_item = function(item)
			return gutter(item) .. " " .. worktree.name(item)
		end,
	}, function(choice)
		if choice then
			on_choice(choice)
		end
	end)
end

---Open the worktrunk picker.
---@param opts? Worktrunk.PickerConfig
---@param on_choice? fun(worktree: Worktrunk.Worktree) defaults to the switch action
function M.pick(opts, on_choice)
	local ok = pcall(require, "snacks")
	if not ok or not Snacks.picker then
		return select(on_choice or function(item)
			require("worktrunk.actions").switch(worktree.name(item))
		end)
	end

	set_highlights()

	---@type Worktrunk.PickerConfig
	local defaults = {
		source = "worktrunk",
		title = "Worktrees",
		branches = true,
		remotes = true,
		wt_state = { cache = {} },
		filter = { transform = transform },
		finder = finder,
		format = format,
		preview = "none",
		live = false,
		sort = { fields = { "score:desc", "idx" } },
		layout = {
			preset = "select",
			layout = {
				-- NOTE: width/height are fractions of the editor, but min_*/max_*
				-- are absolute columns/lines (`snacks.win` clamps with them).
				width = 0.8,
				min_width = 100,
				max_width = 160,
				height = 0.7,
				min_height = 20,
				max_height = 40,
			},
		},
		confirm = "worktrunk_switch",
		actions = actions,
		win = {
			input = {
				keys = {
					["<C-d>"] = { "worktrunk_delete", mode = { "n", "i" } },
					["<C-n>"] = { "worktrunk_create", mode = { "n", "i" } },
					["<C-r>"] = { "worktrunk_refresh", mode = { "n", "i" } },
				},
			},
			list = {
				keys = {
					["<C-d>"] = "worktrunk_delete",
					["<C-n>"] = "worktrunk_create",
					["<C-r>"] = "worktrunk_refresh",
				},
			},
		},
	}

	if on_choice then
		defaults.confirm = function(picker, item)
			picker:close()
			if item then
				on_choice(item.worktrunk)
			end
		end
	end

	return Snacks.picker.pick(vim.tbl_deep_extend("force", defaults, opts or {}))
end

return M
