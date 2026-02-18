# Must-Fix Items: Phase 4

## Summary
1 critical issue, 3 minor issues found in review.

---

## Tasks

### Task 1: Wrap board creation in a transaction
**Status:** ✅ Fixed
**What was done:** Replaced `if @board.save` / `else` with `ActiveRecord::Base.transaction { @board.save!; @board.board_memberships.create! }` and a `rescue ActiveRecord::RecordInvalid` clause that renders `:new`. Both operations now commit or roll back atomically.

---

### Task 2: Replace `@board.members.include?(user)` with a targeted EXISTS query
**Status:** ✅ Fixed
**What was done:** Replaced `@board.members.include?(user)` on line 19 of `MembershipsController#create` with `BoardMembership.exists?(board: @board, user: user)` — a single targeted SQL EXISTS query.

---

### Task 3: Add missing collaborator PATCH/DELETE integration tests
**Status:** ✅ Fixed
**What was done:** Added four tests to `MembershipsFlowTest`: `"collaborator can update a card"`, `"collaborator can delete a card"`, `"collaborator can create a swimlane"`, and `"collaborator can delete a swimlane"`. All pass (18 runs, 0 failures).

---

### Task 4: Fix AGENTS.md project structure section
**Status:** ✅ Fixed
**What was done:** Updated the `app/controllers/` comment in AGENTS.md to include `MembershipsController` and the `app/models/` comment to include `BoardMembership`.
