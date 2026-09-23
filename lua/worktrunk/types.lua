--- Type definitions for the `wt list --format=json` schema 2 envelope.
--- See `wt list --help` ("JSON output" / "Schema 2") and
--- https://worktrunk.dev/schema/list-v2.json
---
--- Absence rules from the CLI docs:
---  * a field is *absent* when there is nothing to report (not applicable,
---    not requested this run, or determined-empty);
---  * a field is `nil`/null when it was requested but never determined
---    (timeout, stale branch, failed forge fetch) — the JSON form of the
---    table's `·` placeholder.

--------------------------------------------------------------------------------
-- Envelope
--------------------------------------------------------------------------------

---@class Worktrunk.Forge
---@field url string Repository web URL
---@field provider "github"|"gitlab"|"gitea"|"azure-devops"|"unknown"
---@field host string Repository web host
---@field owner string Owner, organization, or namespace path
---@field name string Repository name
---@field project? string Azure DevOps project name
---@field remote? string Local remote name used for the metadata

---@class Worktrunk.Repo
---@field default_branch string
---@field forge? Worktrunk.Forge

---@class Worktrunk.Collected
---@field ci boolean Whether CI data was collected this run
---@field summary boolean Whether LLM summaries were collected this run

---@class Worktrunk.List
---@field schema 2
---@field repo Worktrunk.Repo
---@field collected Worktrunk.Collected
---@field items Worktrunk.Worktree[]

--------------------------------------------------------------------------------
-- Item
--------------------------------------------------------------------------------

---@class Worktrunk.Diff
---@field added integer
---@field deleted integer

---@class Worktrunk.Head
---@field sha string Full commit SHA
---@field short_sha string Short SHA, abbreviated per core.abbrev
---@field subject string First line of the commit message
---@field committed_at string RFC 3339 UTC timestamp

---Working-tree flags plus `conflicted` and the diff vs HEAD.
---@class Worktrunk.Changes
---@field staged boolean
---@field modified boolean
---@field untracked boolean
---@field renamed boolean
---@field deleted boolean
---@field conflicted boolean
---@field diff Worktrunk.Diff

---@class Worktrunk.LockState
---@field reason? string

---Absent on branch-only rows.
---@class Worktrunk.WorktreeInfo
---@field path string Worktree directory
---@field main boolean Is the primary (home) worktree
---@field current boolean Is the current worktree
---@field previous boolean Previous worktree from `wt switch`
---@field detached boolean HEAD is detached
---@field branch_mismatch boolean Worktree isn't at the path its branch implies
---@field duplicate_branch boolean Branch is checked out in more than one worktree
---@field locked? Worktrunk.LockState
---@field prunable? Worktrunk.LockState
---@field operation? "rebase"|"merge"
---@field changes Worktrunk.Changes

---Why a branch counts as integrated; checks run cheapest-first, first match wins.
---@alias Worktrunk.IntegrationReason
---| "same_commit"
---| "ancestor"
---| "no_added_changes"
---| "trees_match"
---| "merge_adds_nothing"
---| "patch_id_match"

---@class Worktrunk.Integration
---@field reason Worktrunk.IntegrationReason

---Relation to the default branch; absent on the default branch itself.
---@class Worktrunk.DefaultBranch
---@field ahead integer Commits ahead of the default branch
---@field behind integer Commits behind the default branch
---@field diff Worktrunk.Diff Line diffs since the merge-base
---@field orphan boolean No common ancestor with the default branch
---@field integration? Worktrunk.Integration nil when not determined (e.g. dirty tree)
---@field merge_conflicts boolean Merging into the default branch would conflict

---Tracking branch; absent when none is configured.
---@class Worktrunk.Upstream
---@field remote string
---@field branch string
---@field ahead integer
---@field behind integer

---@alias Worktrunk.ReviewState "changes_requested"|"pending"|"draft"|"approved"

---Open PR/MR; collected with `--full` or a listed `ci` column.
---@class Worktrunk.Pr
---@field number integer
---@field url string
---@field review? Worktrunk.ReviewState
---@field mergeable? boolean false when the forge reports conflicts, nil otherwise
---@field repo? Worktrunk.Forge Repository the PR/MR targets

---@class Worktrunk.Checks
---@field status? "passed"|"running"|"failed" nil when a conflicts report masks it
---@field source "pr"|"branch"
---@field stale boolean Local HEAD differs from remote (unpushed changes)

---@class Worktrunk.DevServer
---@field url string
---@field listening boolean

---Relation to the default branch, highest-priority state first.
---@alias Worktrunk.State
---| "is_main"
---| "orphan"
---| "empty"
---| "integrated"
---| "would_conflict"
---| "same_commit"
---| "diverged"
---| "ahead"
---| "behind"

---@class Worktrunk.Display
---@field state? Worktrunk.State
---@field symbols string Raw status symbols without colors (e.g. "!?↓")
---@field statusline string Pre-formatted status with ANSI colors and OSC 8 links
---@field columns? table<string, string> Custom-column cells keyed by header

---One row of `wt list`: a worktree, a local branch, or a remote branch.
---@class Worktrunk.Worktree
---@field branch? string nil for a detached-HEAD worktree
---@field remote? string Present only on remote-only branch rows
---@field head? Worktrunk.Head nil for unborn branches
---@field worktree? Worktrunk.WorktreeInfo Absent on branch-only rows
---@field default_branch? Worktrunk.DefaultBranch Absent on the default branch itself
---@field upstream? Worktrunk.Upstream
---@field pr? Worktrunk.Pr
---@field checks? Worktrunk.Checks
---@field dev_server? Worktrunk.DevServer
---@field summary? string LLM branch summary
---@field vars? table<string, string> Per-branch variables from `wt config state vars`
---@field display Worktrunk.Display

return {}
