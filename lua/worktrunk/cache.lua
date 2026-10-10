--- Shared cache for `wt list` output, so repeated queries (switch picker,
--- worktree lookups, ...) don't shell out every time.
---
--- Reads are stale-while-revalidate: `get` always answers instantly from the
--- store — even past the TTL — and a stale hit triggers one background
--- refresh. Only a cold miss ever blocks. Mutating actions `invalidate()` and
--- `prefetch()` so the next read is warm again.
---
--- Entries are keyed by the query shape — working directory plus the flags
--- that change the row set (`branches`, `remotes`, `full`) — because each
--- combination is genuinely different output (`current` depends on the cwd,
--- `--full` adds forge data, ...).
local cli = require("worktrunk.cli")
local config = require("worktrunk.config")

require("worktrunk.types")

local M = {}

---@class Worktrunk.CacheEntry
---@field envelope Worktrunk.List decoded `wt list` output
---@field at integer ms timestamp (vim.uv.now) of the fetch

---@type table<string, Worktrunk.CacheEntry>
local store = {}

---Keys with a background fetch in flight, to dedupe concurrent refreshes.
---@type table<string, boolean>
local pending = {}

---Callbacks to run when the background fetch for a key lands.
---@type table<string, fun(envelope: Worktrunk.List)[]>
local waiting = {}

---Bumped by `invalidate`: background results from an older generation are
---thrown away instead of resurrecting pre-invalidation data.
local generation = 0

---The cache key for a query. `cwd` defaults to nvim's cwd so "no cwd" isn't
---one shared bucket while the editor moves between worktrees.
---@param opts worktrunk.ListOpts|nil
---@return string
function M.key(opts)
	opts = opts or {}
	return table.concat({
		vim.fs.normalize(opts.cwd or vim.fn.getcwd()),
		opts.branches and "branches" or "",
		opts.remotes and "remotes" or "",
		opts.full and "full" or "",
	}, "|")
end

---Start a background fetch for `key` unless one is already in flight.
---On success the entry is stored and the key's waiters run; on failure the
---stale entry survives and the next stale `get` retries.
---@param key string
---@param opts worktrunk.ListOpts|nil
---@param on_refresh fun(envelope: Worktrunk.List)|nil
local function fetch_in_background(key, opts, on_refresh)
	if on_refresh then
		waiting[key] = waiting[key] or {}
		table.insert(waiting[key], on_refresh)
	end
	if pending[key] then
		return
	end
	pending[key] = true

	local gen = generation
	cli.list_json(opts, function(envelope, _)
		if gen ~= generation then
			return -- invalidated while in flight: the result is not trusted
		end
		pending[key] = nil
		local callbacks = waiting[key]
		waiting[key] = nil
		if not envelope then
			return
		end
		store[key] = { envelope = envelope, at = vim.uv.now() }
		for _, callback in ipairs(callbacks or {}) do
			callback(envelope)
		end
	end)
end

---Envelope for `opts`, always answered from the store when possible:
---  - cold miss: one blocking fetch (the only path that ever blocks);
---  - fresh hit: served as is;
---  - stale hit (older than `cache_ttl`): served as is, plus one deduped
---    background refresh; `on_refresh` runs when it lands.
---@param opts worktrunk.ListOpts|nil
---@param on_refresh fun(envelope: Worktrunk.List)|nil called (scheduled) after a background refresh triggered by this read
---@return Worktrunk.List|nil envelope, string|nil err
function M.get(opts, on_refresh)
	local key = M.key(opts)
	local entry = store[key]
	if not entry then
		return M.refresh(opts)
	end
	if (vim.uv.now() - entry.at) >= config.get().cache_ttl then
		fetch_in_background(key, opts, on_refresh)
	end
	return entry.envelope, nil
end

---Blocking fetch of `opts`, replacing any cached entry.
---Failures are returned but never cached.
---@param opts worktrunk.ListOpts|nil
---@return Worktrunk.List|nil envelope, string|nil err
function M.refresh(opts)
	local envelope, err = cli.list_json(opts)
	if envelope then
		store[M.key(opts)] = { envelope = envelope, at = vim.uv.now() }
	end
	return envelope, err
end

---Warm the entry for `opts` in the background, regardless of its age.
---Fire and forget: errors are swallowed, a stale entry just stays stale.
---@param opts worktrunk.ListOpts|nil
function M.prefetch(opts)
	fetch_in_background(M.key(opts), opts)
end

---Milliseconds since the cached entry for `opts` was fetched, nil on a miss.
---@param opts worktrunk.ListOpts|nil
---@return integer|nil
function M.age(opts)
	local entry = store[M.key(opts)]
	return entry and (vim.uv.now() - entry.at) or nil
end

---Drop every cached entry and discard in-flight background results.
---The next `get` fetches again.
function M.invalidate()
	store, pending, waiting = {}, {}, {}
	generation = generation + 1
end

return M
