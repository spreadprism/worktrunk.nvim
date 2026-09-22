local worktrunk = require("worktrunk")

describe("worktrunk", function()
	before_each(function()
		worktrunk.options = nil
	end)

	it("returns defaults if setup not called", function()
		assert.True(vim.deep_equal(worktrunk.get(), worktrunk.defaults))
	end)

	it("merges user options on setup", function()
		worktrunk.setup({ foo = "bar" })
		assert.are.equal("bar", worktrunk.get().foo)
	end)
end)
