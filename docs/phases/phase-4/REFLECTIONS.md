# Reflections: Phase 4

## Looking Back

### What Went Well
- **Authorization sweep was thorough**: All 5 auth check sites were updated to `Board.accessible_by(Current.user)` and the `require_owner!` guard was added cleanly. No controller was missed.
- **Turbo Streams used consistently throughout**: The Phase 3 lesson about `turbo_frame: "_top"` escape hatches was heeded — add-member and remove-member both use proper Turbo Stream responses, no page reloads.
- **Test quality improved significantly over Phase 3**: Integration tests assert `response.body` content, not just model state. Tests are independent with inline setup, no cross-test shared state. SimpleCov reached 89.14% — well above the 80% floor.
- **N+1 preempted on boards index**: The `@owned_board_ids` precomputation strategy was applied from the start, avoiding per-board ownership queries.
- **Must-Fix cycle was short and effective**: Only 4 items surfaced in review (1 critical, 3 minor), all fixed cleanly. The MUST-FIX.md is fully resolved.

### What Didn't Work
- **Data integrity gap in `BoardsController#create`**: Board creation and owner membership creation weren't wrapped in a transaction — a DB error on the second call would leave the board permanently inaccessible. Caught in review and fixed, but should have been in the original plan's success criteria.
- **`@board.members.include?(user)` loaded full association into memory**: The plan specified `BoardMembership.exists?()` but the implementation used the association check. This is a case where the plan was right and the builder deviated without reason.
- **Missing collaborator PATCH/DELETE tests**: The SPEC explicitly required tests for collaborator PATCH/DELETE cards and swimlane CRUD. These were omitted from initial implementation and caught in the adversarial test review. The authorization code was correct, but the coverage gap left a trust hole.
- **AGENTS.md project structure section went stale**: The "Phase 4 additions" section was added correctly but the top-level `app/controllers/` and `app/models/` list wasn't updated. Documentation housekeeping needs to be a checklist item, not an afterthought.
- **Unused `signIn` import in E2E spec**: Minor lint issue — imported but never called, since separate browser contexts were used instead. Signals that E2E helpers and spec design weren't fully aligned.

### Spec vs Reality
- **Delivered as spec'd**: BoardMembership model with role enum; Board.accessible_by scope; all 5 auth sites updated; MembershipsController with Turbo Stream add/remove; Members panel (owner-only); collaborator board access; owner-only view gates; non-member 404 on board and nested resources; README and AGENTS.md updates; SimpleCov ≥ 80%.
- **Deviated from spec**: Membership list ordering (`.order(:role, :created_at)`) was noted as cosmetic but missed in the initial implementation — the list had non-deterministic order. Fixed as part of the must-fix review.
- **Deferred**: Nothing from scope was deferred. All acceptance criteria were met.

### Review Findings Impact
- **Transaction gap in `BoardsController#create`**: Fixed by wrapping board save + membership create in `ActiveRecord::Base.transaction` with `rescue ActiveRecord::RecordInvalid`. Silent failure mode eliminated.
- **N+1 / memory load in `MembershipsController#create`**: Fixed by replacing `@board.members.include?(user)` with `BoardMembership.exists?(board: @board, user: user)`.
- **Missing collaborator test coverage**: Fixed by adding 4 integration tests — collaborator can update a card, delete a card, create a swimlane, delete a swimlane. Test count went from 14 to 18 in `MembershipsFlowTest`.
- **AGENTS.md project structure stale**: Fixed by adding `MembershipsController` and `BoardMembership` to the top-level structure comments.

---

## Looking Forward

### Recommendations for Next Phase
- **ActionCable complexity warrants early research into session management**: Real-time updates via ActionCable require authenticated WebSocket connections. Rails 8's built-in auth uses session cookies — verify ActionCable channel auth works with the existing `Current.user` pattern before building any UI.
- **Channel scoping is the hard problem**: Channels must only broadcast updates to users who are board members. The `Board.accessible_by` scope from Phase 4 gives us the predicate — use it to gate channel subscriptions. Design this before writing any broadcast code.
- **Start with a narrow real-time feature**: Don't try to real-time everything at once. Pick one high-value update (card created, card moved) and get it working end-to-end through the ActionCable stack before expanding to swimlanes, membership changes, etc.
- **Turbo Streams over WebSocket vs Turbo Streams over HTTP**: The existing Turbo Stream infrastructure uses HTTP. ActionCable uses the same `turbo_stream_from` tag on the client but broadcasts from the server. Understand the difference — don't conflate them in the plan.

### What Should Next Phase Build?
**Phase 5: Real-Time Updates via ActionCable**

The most logical next phase per BRIEF.md is real-time collaboration. Scope:
- Broadcast card created/updated/deleted to all board members
- Broadcast swimlane created/updated/deleted to all board members
- Channel authentication — only board members can subscribe
- Collaborators see each other's changes without page reload

Priority order within the phase:
1. ActionCable channel setup with membership-scoped auth
2. Card events (highest value — most frequent interaction)
3. Swimlane events
4. Membership events (member added/removed) — lower priority

Out of scope for Phase 5: presence indicators, "user is typing", activity feed.

### Technical Debt Noted
- **`require_owner!` fires two queries per owner-only action**: `set_board` loads board via membership join, then `require_owner!` runs a separate `BoardMembership.exists?` check. Acceptable now but could be cached with `@current_membership` if N becomes noticeable: `app/controllers/boards_controller.rb`
- **BoardMembership ordered query in `show.html.erb` could be a scope**: `.order(:role, :created_at)` on the membership association is inline in the view. Should be a named scope (`BoardMembership.ordered`) for testability: `app/views/boards/show.html.erb:31`
- **`BoardMembership.exists?` in views is a DB call per render**: The owner check in `show.html.erb` and `index.html.erb` queries the DB directly. The `@owned_board_ids` approach from the plan is applied to `index` but not `show`. Acceptable for a single board view, but worth noting: `app/views/boards/show.html.erb`

### Process Improvements
- **Add "check plan deviations" as an explicit build step**: The `@board.members.include?(user)` deviation from the plan went unnoticed until review. Build step should include a self-review against the plan checklist before committing.
- **Collaborator CRUD tests should be on the must-have test checklist**: The SPEC explicitly called these out. The plan task list should have included them as checklist items, not left them to be caught in adversarial review.
- **Documentation structure tasks need to be explicit**: "Update AGENTS.md project structure section" should be its own sub-task in Task 9, not implied. The top-level structure list and the phase-specific section require separate verification.
- **E2E spec helpers should be designed before the spec**: The unused `signIn` import shows the spec was written without fully resolving whether sign-in-via-existing-user or sign-up flows would be used. Clarify helper interface before writing the spec body.
