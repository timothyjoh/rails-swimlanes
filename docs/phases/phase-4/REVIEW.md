# Phase Review: Phase 4

## Overall Verdict
**NEEDS-FIX** — see MUST-FIX.md

---

## Code Quality Review

### Summary
The Phase 4 implementation is largely solid. Authorization is correctly swept across all five controller sites, the membership model is clean, Turbo Stream responses are used throughout (no `_top` escape hatches), and view gates correctly hide owner-only controls. Documentation is updated. SimpleCov is at 89.14% — well above the 80% floor.

Two issues require fixes: a data-integrity gap in `BoardsController#create` (no transaction around board + membership creation) and a real-query N+1 in `MembershipsController#create` (`members.include?` loads the full member collection). A third gap — missing ordered membership list — is cosmetic. Test coverage gaps for collaborator PATCH/DELETE operations are called out in the adversarial section.

### Findings

1. **Data Integrity — No transaction in `BoardsController#create`** — `app/controllers/boards_controller.rb:20-22`
   - `@board.save` succeeds, then `@board.board_memberships.create!` is called outside any transaction. If the second call raises (DB error, unique constraint, etc.), the board row is committed with zero members — the creator can never access their own board via the membership-scoped query. Low probability, but causes silent permanent inaccessibility.

2. **N+1 / Memory Load — `@board.members.include?(user)` in `MembershipsController#create`** — `app/controllers/memberships_controller.rb:19`
   - This loads the entire members association into memory to check for inclusion. The plan specified `BoardMembership.exists?(board: @board, user: user)` — a single targeted EXISTS query. With large boards this will become slow.

3. **Cosmetic — Membership list not ordered** — `app/views/boards/show.html.erb:31`
   - `@board.board_memberships.includes(:user)` has no `.order(...)`. The plan specified `.order(:role, :created_at)` so the owner row always appears first. Currently, order is non-deterministic across runs.

4. **Unused Import — `signIn` in E2E spec** — `e2e/board_sharing.spec.js:2`
   - `signIn` is imported from `helpers/auth.js` but never called. All test users are created via `signUp`. Minor, but generates a lint warning.

5. **AGENTS.md — Project Structure section not updated** — `AGENTS.md:52-54`
   - `app/controllers/` list still names only the Phase 1–3 controllers; `MembershipsController` is absent. `app/models/` list omits `BoardMembership`. The "Phase 4 additions" section further down documents this, but the top-level structure section is stale.

### Spec Compliance Checklist

- [x] `board_memberships` table with `board_id`, `user_id`, `role` enum, unique index — migration and schema confirmed
- [x] Board creation seeds an owner membership row
- [x] `Board.accessible_by(user)` scope — `app/models/board.rb:10-12`
- [x] All 5 auth check sites updated to membership-scoped query
- [x] `require_owner!` before edit/update/destroy on boards
- [x] MembershipsController add-member by email — Turbo Stream success and error paths
- [x] Removing a member via Turbo Stream; owner row has no Remove button
- [x] Collaborator boards index shows shared boards
- [x] Owner-only controls (Edit/Delete board) hidden from collaborators
- [x] Non-member 404 on board and nested resources
- [x] No `turbo_frame: "_top"` escape hatches — all member add/remove use Turbo Streams
- [x] Turbo Stream error responses assert response body, not only model state
- [x] SimpleCov ≥ 80% (89.14%)
- [x] README Phase 3 and Phase 4 entries have ✓
- [x] AGENTS.md authorization section and Phase 4 data model section updated
- [ ] AGENTS.md project structure section missing `MembershipsController` and `BoardMembership`
- [ ] Integration tests for collaborator PATCH cards, DELETE cards, swimlane edit/delete — per SPEC testing strategy section, these are explicitly required

---

## Adversarial Test Review

### Summary
Test quality is **adequate** — significantly better than Phase 3 (which checked only model state). All Turbo Stream integration tests assert on `response.body`. No mocks; real DB throughout. Tests are independent (inline setup, no cross-test shared state). The main gap is collaborator CRUD coverage for cards (PATCH, DELETE) and swimlanes (PATCH, DELETE) — the SPEC testing strategy explicitly calls these out.

### Findings

1. **Missing Test Cases — Collaborator PATCH/DELETE on cards** — `test/integration/memberships_flow_test.rb`
   - SPEC testing strategy (line 57): "a member-role user can GET board show, POST cards, **PATCH cards, DELETE cards**; returns 200/redirect, not 404." Only `POST cards` is tested (`"collaborator can create a card"`). No test for `PATCH` (update card) or `DELETE` (destroy card) by a collaborator.

2. **Missing Test Cases — Collaborator swimlane operations** — `test/integration/memberships_flow_test.rb`
   - SPEC says collaborators can create/edit/delete swimlanes. No test covers collaborator `POST /swimlanes`, `PATCH /swimlanes/:id`, or `DELETE /swimlanes/:id`. The authorization code is correct (`SwimlanesController` uses `Board.accessible_by`), but no test verifies it for the member role.

3. **Missing Test — Collaborator cannot GET edit board** — `test/integration/memberships_flow_test.rb`
   - `collaborator cannot rename board` tests `PATCH board_path` (→ 404 ✓). There is no test that `GET edit_board_path(@board)` by a collaborator also returns 404. The `require_owner!` before_action covers `:edit` too, but it's untested.

4. **Weak `assert_match` on `dom_id`** — `test/integration/memberships_flow_test.rb:51`
   - `assert_match dom_id(membership), response.body` verifies the DOM id string appears in the Turbo Stream remove response. This is adequate, but the test doesn't assert that the turbo-stream action is `remove` (vs. some other action that might also include that id). Acceptable for this phase.

5. **Board model unit tests use fixtures for accessible_by** — `test/models/board_test.rb:35-59`
   - Tests create records inline (no fixtures dependency) — consistent with the established pattern. Good.

6. **Happy path for board membership creation in model test missing the "board board just created" uniqueness check** — `test/models/board_membership_test.rb`
   - The `"enforces unique user per board"` test creates the first membership explicitly, then tests the duplicate. But the setup creates a board without a membership, meaning `setup` doesn't pre-seed the board owner — this is intentional for model tests. No issue.

7. **`MembershipsFlowTest` "owner cannot remove themselves"** — `test/integration/memberships_flow_test.rb:54-59`
   - Sends a standard HTML request (no Turbo headers) and asserts `assert_response :redirect`. The controller does `redirect_to @board, alert: "..."`. The redirect is followed or not — test confirms membership still exists. Solid, but doesn't assert the redirect location is the board. Minor.

### Test Coverage
- SimpleCov: **89.14%** (above the 80% floor)
- Missing coverage: collaborator PATCH/DELETE card paths, collaborator swimlane CRUD paths
