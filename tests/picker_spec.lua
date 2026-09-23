local picker = require("worktrunk.picker")

describe("picker.parse_pattern", function()
	local function parse(pattern)
		local kind, number, rest = picker.parse_pattern(pattern)
		return { kind = kind, number = number, rest = rest }
	end

	it("passes a plain pattern through", function()
		assert.same({ rest = "feat" }, parse("feat"))
	end)

	it("parses the worktree sigils", function()
		assert.same({ kind = "current", rest = "" }, parse("@"))
		assert.same({ kind = "main", rest = "api" }, parse("^ api"))
		assert.same({ kind = "previous", rest = "" }, parse("-"))
	end)

	it("parses pr:/mr: with and without a number", function()
		assert.same({ kind = "pr", number = 101, rest = "" }, parse("pr:101"))
		assert.same({ kind = "pr", number = 42, rest = "auth" }, parse("mr:42 auth"))
		assert.same({ kind = "pr", rest = "" }, parse("pr:"))
		assert.same({ kind = "pr", rest = "auth" }, parse("pr auth"))
	end)
end)

describe("picker.matches_kind", function()
	local item = { current = true, main = false, previous = false, pr = 101 }

	it("keeps everything without a sigil", function()
		assert.True(picker.matches_kind({}, nil, nil))
	end)

	it("filters by row kind", function()
		assert.True(picker.matches_kind(item, "current", nil))
		assert.False(picker.matches_kind(item, "main", nil))
		assert.False(picker.matches_kind(item, "previous", nil))
	end)

	it("filters by pr number when given", function()
		assert.True(picker.matches_kind(item, "pr", nil))
		assert.True(picker.matches_kind(item, "pr", 101))
		assert.False(picker.matches_kind(item, "pr", 7))
		assert.False(picker.matches_kind({ pr = nil }, "pr", nil))
	end)
end)
