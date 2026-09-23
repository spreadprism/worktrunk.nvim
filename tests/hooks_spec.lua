local config = require("worktrunk.config")
local hooks = require("worktrunk.hooks")

describe("hooks", function()
	local notifications
	local real_notify

	before_each(function()
		notifications = {}
		config.options, config.config = nil, nil
		real_notify = vim.notify
		vim.notify = function(msg, level)
			table.insert(notifications, { msg = msg, level = level })
		end
	end)

	after_each(function()
		vim.notify = real_notify
		config.options, config.config = nil, nil
	end)

	it("does nothing when no hook is configured", function()
		assert.has_no.errors(function()
			hooks.on_switch({ path = "/repo" })
		end)
	end)

	it("calls the hook with the event", function()
		local seen
		config.setup({ hooks = { on_switch = function(event)
			seen = event
		end } })

		hooks.on_switch({ branch = "feature", path = "/repo.feature", from = "/repo" })

		assert.same({ branch = "feature", path = "/repo.feature", from = "/repo" }, seen)
	end)

	it("reports a throwing hook instead of propagating", function()
		config.setup({ hooks = { on_switch = function()
			error("boom")
		end } })

		assert.has_no.errors(function()
			hooks.on_switch({ path = "/repo" })
		end)
		assert.are.equal(vim.log.levels.ERROR, notifications[1].level)
		assert.matches("hooks.on_switch failed", notifications[1].msg)
	end)

	it("ignores a non-function hook", function()
		config.setup({ hooks = { on_switch = "nope" } })
		assert.has_no.errors(function()
			hooks.on_switch({ path = "/repo" })
		end)
		assert.are.equal(0, #notifications)
	end)
end)
