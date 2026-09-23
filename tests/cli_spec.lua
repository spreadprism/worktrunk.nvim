local cli = require("worktrunk.cli")

describe("cli.switch_args", function()
	it("defaults to a bare picker invocation", function()
		assert.same({ "wt", "switch" }, cli.switch_args())
	end)

	it("maps every switch flag", function()
		assert.same({
			"wt",
			"switch",
			"--create",
			"--base",
			"^",
			"--execute",
			"claude",
			"--clobber",
			"--no-cd",
			"--branches",
			"--remotes",
			"--prs",
			"--no-hooks",
			"--format",
			"json",
			"-C",
			"/repo",
			"--config",
			"/cfg.toml",
			"--config-set",
			"list.full=true",
			"-v",
			"-v",
			"--yes",
			"feature",
			"--",
			"Fix GH #322",
		}, cli.switch_args({
			branch = "feature",
			execute_args = { "Fix GH #322" },
			create = true,
			base = "^",
			execute = "claude",
			clobber = true,
			no_cd = true,
			branches = true,
			remotes = true,
			prs = true,
			no_hooks = true,
			format = "json",
			cwd = "/repo",
			config = "/cfg.toml",
			config_set = { "list.full=true" },
			verbose = 2,
			yes = true,
		}))
	end)

	it("puts the branch after the flags", function()
		assert.same({ "wt", "switch", "--create", "new-feature" }, cli.switch_args({ branch = "new-feature", create = true }))
	end)
end)

describe("cli.list_args", function()
	it("defaults to a bare list", function()
		assert.same({ "wt", "list" }, cli.list_args())
	end)

	it("maps every list flag", function()
		assert.same({
			"wt",
			"list",
			"--format",
			"json",
			"--branches",
			"--remotes",
			"--full",
			"--progressive",
		}, cli.list_args({
			format = "json",
			branches = true,
			remotes = true,
			full = true,
			progressive = true,
		}))
	end)

	it("emits --no-progressive for progressive=false", function()
		assert.same({ "wt", "list", "--no-progressive" }, cli.list_args({ progressive = false }))
	end)

	it("builds the statusline subcommand", function()
		assert.same(
			{ "wt", "list", "statusline", "--format", "claude-code" },
			cli.statusline_args({ format = "claude-code" })
		)
	end)
end)

describe("cli.remove_args", function()
	it("defaults to the current worktree", function()
		assert.same({ "wt", "remove" }, cli.remove_args())
	end)

	it("maps every remove flag", function()
		assert.same({
			"wt",
			"remove",
			"--no-delete-branch",
			"--force-delete",
			"--foreground",
			"--reap",
			"--force",
			"--no-hooks",
			"--format",
			"json",
			"old-feature",
			"another-branch",
		}, cli.remove_args({
			branches = { "old-feature", "another-branch" },
			no_delete_branch = true,
			force_delete = true,
			foreground = true,
			reap = true,
			force = true,
			no_hooks = true,
			format = "json",
		}))
	end)

	it("accepts a single branch as a string", function()
		assert.same({ "wt", "remove", "feature" }, cli.remove_args({ branches = "feature" }))
	end)
end)

describe("cli.merge_args", function()
	it("defaults to the default branch", function()
		assert.same({ "wt", "merge" }, cli.merge_args())
	end)

	it("maps every merge flag", function()
		assert.same({
			"wt",
			"merge",
			"--no-squash",
			"--no-commit",
			"--no-rebase",
			"--no-remove",
			"--no-ff",
			"--stage",
			"tracked",
			"--no-hooks",
			"--format",
			"json",
			"-C",
			"/repo",
			"develop",
		}, cli.merge_args({
			target = "develop",
			no_squash = true,
			no_commit = true,
			no_rebase = true,
			no_remove = true,
			no_ff = true,
			stage = "tracked",
			no_hooks = true,
			format = "json",
			cwd = "/repo",
		}))
	end)
end)
