--- Thin, 1:1 bindings for the `wt` (worktrunk) CLI.
---
--- Every field of the option tables below maps to exactly one flag of the
--- corresponding `wt <command> --help`, and nothing is invented on top.
local config = require("worktrunk.config")

local M = {}

---The `wt` binary, from user config.
---@return string
function M.bin()
	return config.get().bin
end

---@param value string|string[]|nil
---@return string[]
local function as_list(value)
	if value == nil then
		return {}
	end
	if type(value) == "string" then
		return { value }
	end
	return value
end

--------------------------------------------------------------------------------
-- Global options (shared by every subcommand)
--------------------------------------------------------------------------------

---@class worktrunk.GlobalOpts
---@field cwd string|nil        -C <path>              Working directory for this command
---@field config string|nil     --config <path>        User config file path
---@field config_set string[]|string|nil --config-set <toml>  Inline TOML overrides (repeatable)
---@field verbose integer|nil   -v...                  0|1|2 verbosity
---@field yes boolean|nil       -y, --yes              Skip approval prompts

---@param args string[]
---@param opts worktrunk.GlobalOpts
local function global_args(args, opts)
	if opts.cwd then
		vim.list_extend(args, { "-C", opts.cwd })
	end
	if opts.config then
		vim.list_extend(args, { "--config", opts.config })
	end
	for _, toml in ipairs(as_list(opts.config_set)) do
		vim.list_extend(args, { "--config-set", toml })
	end
	for _ = 1, (opts.verbose or 0) do
		table.insert(args, "-v")
	end
	if opts.yes then
		table.insert(args, "--yes")
	end
	return args
end

--------------------------------------------------------------------------------
-- wt switch
--------------------------------------------------------------------------------

--- `wt switch` — Switch to a worktree; create if needed.
---
--- Usage: wt switch [OPTIONS] [BRANCH] [-- <EXECUTE_ARGS>...]
---
---@class worktrunk.SwitchOpts : worktrunk.GlobalOpts
---@field branch string|nil        [BRANCH]            Branch, worktree path, shortcut (`^`, `-`, `@`, `pr:{N}`, `mr:{N}`) or PR/MR URL. Omit to open the interactive picker.
---@field execute_args string[]|nil [EXECUTE_ARGS]...  Extra args for --execute, passed after `--`
---@field create boolean|nil       -c, --create        Create a new branch
---@field base string|nil          -b, --base <BASE>   Base branch (same shortcuts as BRANCH)
---@field execute string|nil       -x, --execute <CMD> Command to run after switch
---@field clobber boolean|nil      --clobber           Remove stale paths at target
---@field no_cd boolean|nil        --no-cd             Skip directory change after switching
---@field cd boolean|nil           --cd                Override --no-cd from config
---@field branches boolean|nil     --branches          Picker: include branches without worktrees
---@field remotes boolean|nil      --remotes           Picker: include remote branches
---@field prs boolean|nil          --prs               Picker: include open PRs/MRs
---@field no_hooks boolean|nil     --no-hooks          Skip hooks
---@field format "text"|"json"|nil --format <FORMAT>   Output format [default: text]

---Build the argv for `wt switch`.
---@param opts worktrunk.SwitchOpts|nil
---@return string[]
function M.switch_args(opts)
	opts = opts or {}
	local args = { M.bin(), "switch" }

	if opts.create then
		table.insert(args, "--create")
	end
	if opts.base then
		vim.list_extend(args, { "--base", opts.base })
	end
	if opts.execute then
		vim.list_extend(args, { "--execute", opts.execute })
	end
	if opts.clobber then
		table.insert(args, "--clobber")
	end
	if opts.no_cd then
		table.insert(args, "--no-cd")
	end
	if opts.cd then
		table.insert(args, "--cd")
	end
	if opts.branches then
		table.insert(args, "--branches")
	end
	if opts.remotes then
		table.insert(args, "--remotes")
	end
	if opts.prs then
		table.insert(args, "--prs")
	end
	if opts.no_hooks then
		table.insert(args, "--no-hooks")
	end
	if opts.format then
		vim.list_extend(args, { "--format", opts.format })
	end
	global_args(args, opts)

	if opts.branch then
		table.insert(args, opts.branch)
	end
	if opts.execute_args and #opts.execute_args > 0 then
		table.insert(args, "--")
		vim.list_extend(args, opts.execute_args)
	end

	return args
end

---Run `wt switch`.
---@param opts worktrunk.SwitchOpts|nil
---@param on_exit fun(result: vim.SystemCompleted)|nil
function M.switch(opts, on_exit)
	return M.run(M.switch_args(opts), opts, on_exit)
end

--------------------------------------------------------------------------------
-- wt list
--------------------------------------------------------------------------------

--- `wt list` — List worktrees and their status.
---
--- Usage: wt list [OPTIONS]
---        wt list <COMMAND>
---
---@class worktrunk.ListOpts : worktrunk.GlobalOpts
---@field format "table"|"json"|nil  --format <FORMAT>  Output format [default: table]
---@field branches boolean|nil       --branches         Include branches without worktrees
---@field remotes boolean|nil        --remotes          Include remote branches
---@field full boolean|nil           --full             Show CI status and LLM summaries
---@field progressive boolean|nil    --progressive / --no-progressive  Fast info first, then slow info

---Build the argv for `wt list`.
---@param opts worktrunk.ListOpts|nil
---@return string[]
function M.list_args(opts)
	opts = opts or {}
	local args = { M.bin(), "list" }

	if opts.format then
		vim.list_extend(args, { "--format", opts.format })
	end
	if opts.branches then
		table.insert(args, "--branches")
	end
	if opts.remotes then
		table.insert(args, "--remotes")
	end
	if opts.full then
		table.insert(args, "--full")
	end
	if opts.progressive ~= nil then
		table.insert(args, opts.progressive and "--progressive" or "--no-progressive")
	end
	global_args(args, opts)

	return args
end

---Run `wt list`.
---@param opts worktrunk.ListOpts|nil
---@param on_exit fun(result: vim.SystemCompleted)|nil
function M.list(opts, on_exit)
	return M.run(M.list_args(opts), opts, on_exit)
end

--- `wt list statusline` — Single-line status for the current worktree.
---
---@class worktrunk.StatuslineOpts : worktrunk.GlobalOpts
---@field format "table"|"json"|"claude-code"|nil  --format <FORMAT>  [default: table]

---Build the argv for `wt list statusline`.
---@param opts worktrunk.StatuslineOpts|nil
---@return string[]
function M.statusline_args(opts)
	opts = opts or {}
	local args = { M.bin(), "list", "statusline" }
	if opts.format then
		vim.list_extend(args, { "--format", opts.format })
	end
	return global_args(args, opts)
end

---Run `wt list statusline`.
---@param opts worktrunk.StatuslineOpts|nil
---@param on_exit fun(result: vim.SystemCompleted)|nil
function M.statusline(opts, on_exit)
	return M.run(M.statusline_args(opts), opts, on_exit)
end

--------------------------------------------------------------------------------
-- wt remove
--------------------------------------------------------------------------------

--- `wt remove` — Remove worktree; delete branch if merged.
--- Defaults to the current worktree.
---
--- Usage: wt remove [OPTIONS] [BRANCHES]...
---
---@class worktrunk.RemoveOpts : worktrunk.GlobalOpts
---@field branches string[]|string|nil  [BRANCHES]...   Branch names or worktree paths [default: current]
---@field no_delete_branch boolean|nil  --no-delete-branch  Keep branch after removal
---@field force_delete boolean|nil      -D, --force-delete  Delete unmerged branches
---@field foreground boolean|nil        --foreground        Block until removal completes
---@field reap boolean|nil              --reap              Kill processes started in the worktree [experimental]
---@field force boolean|nil             -f, --force         Force worktree removal (dirty worktree)
---@field no_hooks boolean|nil          --no-hooks          Skip hooks
---@field format "text"|"json"|nil      --format <FORMAT>   Output format [default: text]

---Build the argv for `wt remove`.
---@param opts worktrunk.RemoveOpts|nil
---@return string[]
function M.remove_args(opts)
	opts = opts or {}
	local args = { M.bin(), "remove" }

	if opts.no_delete_branch then
		table.insert(args, "--no-delete-branch")
	end
	if opts.force_delete then
		table.insert(args, "--force-delete")
	end
	if opts.foreground then
		table.insert(args, "--foreground")
	end
	if opts.reap then
		table.insert(args, "--reap")
	end
	if opts.force then
		table.insert(args, "--force")
	end
	if opts.no_hooks then
		table.insert(args, "--no-hooks")
	end
	if opts.format then
		vim.list_extend(args, { "--format", opts.format })
	end
	global_args(args, opts)

	vim.list_extend(args, as_list(opts.branches))

	return args
end

---Run `wt remove`.
---@param opts worktrunk.RemoveOpts|nil
---@param on_exit fun(result: vim.SystemCompleted)|nil
function M.remove(opts, on_exit)
	return M.run(M.remove_args(opts), opts, on_exit)
end

--------------------------------------------------------------------------------
-- wt merge
--------------------------------------------------------------------------------

--- `wt merge` — Merge current branch into the target branch.
--- Squash & rebase, fast-forward the target branch, remove the worktree.
---
--- Usage: wt merge [OPTIONS] [TARGET]
---
---@class worktrunk.MergeOpts : worktrunk.GlobalOpts
---@field target string|nil                       [TARGET]      Target branch [default: default branch]
---@field no_squash boolean|nil                   --no-squash   Skip commit squashing
---@field no_commit boolean|nil                   --no-commit   Skip commit and squash
---@field no_rebase boolean|nil                   --no-rebase   Skip rebase; require a fast-forward
---@field no_remove boolean|nil                   --no-remove   Keep worktree after merge
---@field no_ff boolean|nil                       --no-ff       Create a merge commit
---@field stage "all"|"tracked"|"none"|nil        --stage       What to stage before committing [default: all]
---@field no_hooks boolean|nil                    --no-hooks    Skip hooks
---@field format "text"|"json"|nil                --format      Output format [default: text]

---Build the argv for `wt merge`.
---@param opts worktrunk.MergeOpts|nil
---@return string[]
function M.merge_args(opts)
	opts = opts or {}
	local args = { M.bin(), "merge" }

	if opts.no_squash then
		table.insert(args, "--no-squash")
	end
	if opts.no_commit then
		table.insert(args, "--no-commit")
	end
	if opts.no_rebase then
		table.insert(args, "--no-rebase")
	end
	if opts.no_remove then
		table.insert(args, "--no-remove")
	end
	if opts.no_ff then
		table.insert(args, "--no-ff")
	end
	if opts.stage then
		vim.list_extend(args, { "--stage", opts.stage })
	end
	if opts.no_hooks then
		table.insert(args, "--no-hooks")
	end
	if opts.format then
		vim.list_extend(args, { "--format", opts.format })
	end
	global_args(args, opts)

	if opts.target then
		table.insert(args, opts.target)
	end

	return args
end

---Run `wt merge`.
---@param opts worktrunk.MergeOpts|nil
---@param on_exit fun(result: vim.SystemCompleted)|nil
function M.merge(opts, on_exit)
	return M.run(M.merge_args(opts), opts, on_exit)
end

--------------------------------------------------------------------------------
-- Execution
--------------------------------------------------------------------------------

---Run an argv built by one of the *_args builders.
---Without `on_exit` the call is synchronous and returns the completed result.
---@param args string[]
---@param opts worktrunk.GlobalOpts|nil
---@param on_exit fun(result: vim.SystemCompleted)|nil
function M.run(args, opts, on_exit)
	opts = opts or {}
	local sys_opts = { text = true, cwd = opts.cwd }
	local proc = vim.system(args, sys_opts, on_exit and vim.schedule_wrap(on_exit) or nil)
	if on_exit then
		return proc
	end
	return proc:wait()
end

--------------------------------------------------------------------------------
-- Typed helpers
--------------------------------------------------------------------------------

---Run `wt list --format=json` and decode the schema 2 envelope.
---@param opts worktrunk.ListOpts|nil
---@return Worktrunk.List|nil envelope, string|nil err
function M.list_json(opts)
	opts = vim.tbl_extend("force", opts or {}, { format = "json" })
	opts.config_set = vim.list_extend(as_list(opts.config_set), { "list.json-schema=2" })

	local result = M.run(M.list_args(opts), opts)
	if result.code ~= 0 then
		return nil, (result.stderr ~= "" and result.stderr or ("wt list exited with %d"):format(result.code))
	end

	local ok, decoded = pcall(vim.json.decode, result.stdout, { luanil = { object = true, array = true } })
	if not ok then
		return nil, "failed to decode wt list output: " .. tostring(decoded)
	end
	return decoded, nil
end

return M
