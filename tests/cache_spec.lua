---@diagnostic disable: duplicate-set-field

local cache = require("worktrunk.cache")
local cli = require("worktrunk.cli")
local config = require("worktrunk.config")

local function envelope(items)
	return { schema = 2, repo = { default_branch = "main" }, collected = {}, items = items or {} }
end

describe("cache", function()
	local real_list_json
	local fetches, background, reply, fail

	---@param ttl number
	local function set_ttl(ttl)
		config.options = { cache_ttl = ttl }
		config.config = nil
	end

	before_each(function()
		cache.invalidate()
		fetches, background, fail = {}, {}, nil
		reply = envelope()
		set_ttl(5000)

		real_list_json = cli.list_json
		cli.list_json = function(opts, on_done)
			if on_done then
				-- background fetch: parked until the test flushes it
				table.insert(background, { opts = opts or {}, done = on_done })
				return
			end
			table.insert(fetches, opts or {})
			if fail then
				return nil, fail
			end
			return reply, nil
		end
	end)

	after_each(function()
		cli.list_json = real_list_json
		config.options, config.config = nil, nil
		cache.invalidate()
	end)

	describe("store", function()
		it("fetches once and serves repeats from the cache", function()
			local first = cache.get()
			local second = cache.get()
			assert.are.equal(1, #fetches)
			assert.are.equal(reply, first)
			assert.are.equal(first, second)
		end)

		it("keys entries by the flags that change the row set", function()
			cache.get()
			cache.get({ branches = true })
			cache.get({ branches = true, remotes = true })
			cache.get({ branches = true }) -- repeat: cached
			assert.are.equal(3, #fetches)
		end)

		it("keys entries by working directory", function()
			cache.get({ cwd = "/tmp/a" })
			cache.get({ cwd = "/tmp/b" })
			cache.get({ cwd = "/tmp/a" }) -- repeat: cached
			assert.are.equal(2, #fetches)
		end)

		it("defaults the key to nvim's cwd instead of one shared bucket", function()
			assert.are.equal(cache.key(), cache.key({ cwd = vim.fn.getcwd() }))
			assert.are_not.equal(cache.key(), cache.key({ cwd = "/somewhere/else" }))
		end)

		it("refresh re-fetches and replaces the cached entry", function()
			cache.get()
			local swapped = envelope({ "new" })
			reply = swapped
			assert.are.equal(swapped, cache.refresh())
			assert.are.equal(swapped, cache.get())
			assert.are.equal(2, #fetches)
		end)

		it("invalidate drops everything", function()
			cache.get()
			cache.get({ branches = true })
			cache.invalidate()
			cache.get()
			assert.are.equal(3, #fetches)
		end)

		it("never caches failures", function()
			fail = "boom"
			local got, err = cache.get()
			assert.is_nil(got)
			assert.are.equal("boom", err)

			fail = nil
			assert.are.equal(reply, cache.get())
			assert.are.equal(2, #fetches)
		end)

		it("tracks the age of an entry", function()
			assert.is_nil(cache.age())
			cache.get()
			assert.is_true(cache.age() >= 0)
			cache.invalidate()
			assert.is_nil(cache.age())
		end)
	end)

	describe("stale-while-revalidate", function()
		it("serves a stale entry instantly and refreshes in the background", function()
			set_ttl(0) -- every hit counts as stale
			cache.get() -- cold: the one blocking fetch

			local stale = cache.get()
			assert.are.equal(reply, stale) -- answered immediately, no new blocking fetch
			assert.are.equal(1, #fetches)
			assert.are.equal(1, #background)

			local fresh = envelope({ "fresh" })
			background[1].done(fresh, nil)
			assert.are.equal(fresh, cache.get())
		end)

		it("never blocks past the cold start", function()
			set_ttl(0)
			cache.get()
			for _ = 1, 5 do
				cache.get()
			end
			assert.are.equal(1, #fetches)
		end)

		it("dedupes concurrent background refreshes but runs every callback", function()
			set_ttl(0)
			cache.get()

			local seen = {}
			cache.get(nil, function(fresh)
				table.insert(seen, fresh)
			end)
			cache.get(nil, function(fresh)
				table.insert(seen, fresh)
			end)
			assert.are.equal(1, #background)

			local fresh = envelope({ "fresh" })
			background[1].done(fresh, nil)
			assert.are.same({ fresh, fresh }, seen)
		end)

		it("does not refresh a fresh entry", function()
			set_ttl(5000)
			cache.get()
			cache.get(nil, function()
				error("should not refresh a fresh entry")
			end)
			assert.are.equal(0, #background)
		end)

		it("keeps the stale entry when the background refresh fails", function()
			set_ttl(0)
			cache.get()
			cache.get()
			background[1].done(nil, "boom")

			assert.are.equal(reply, cache.get()) -- stale survives
			assert.are.equal(2, #background) -- and the next stale read retries
		end)

		it("discards background results that land after an invalidate", function()
			set_ttl(0)
			cache.get()
			cache.get() -- starts the background refresh

			cache.invalidate()
			background[1].done(envelope({ "from before the invalidate" }), nil)

			assert.is_nil(cache.age()) -- nothing was resurrected
			cache.get() -- cold again: blocking fetch of current data
			assert.are.equal(2, #fetches)
		end)
	end)

	describe("prefetch", function()
		it("warms an entry in the background without ever blocking", function()
			cache.prefetch()
			assert.are.equal(0, #fetches)
			assert.are.equal(1, #background)

			background[1].done(reply, nil)
			assert.are.equal(reply, cache.get())
			assert.are.equal(0, #fetches) -- the later get was served warm
		end)

		it("is deduped against an in-flight refresh", function()
			cache.prefetch()
			cache.prefetch()
			assert.are.equal(1, #background)
		end)
	end)
end)
