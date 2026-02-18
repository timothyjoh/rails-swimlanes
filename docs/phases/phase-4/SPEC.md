# Phase 4: Board Sharing

## Objective
Phase 4 lets a board owner share their board with other registered users, giving collaborators full read/write access to swimlanes and cards on that board. This is the first phase where a single piece of data (a board) is visible to more than one user, which means every authorization check in the app must be updated to reflect the new access model — not just the new sharing UI. The result is a visible, testable feature: a user can visit a shared board, create cards, and leave, with all changes visible to the board owner.

## Scope

### In Scope
- **BoardMembership model** — join table connecting boards to users with a `role` column (`owner` | `member`); existing boards are migrated so the creating user becomes the `owner`
- **Sharing UI on board settings / members panel** — a form on the board page where the owner can type an existing user's email and add them as a member
- **Removing a member** — owner can remove any member from the board (but cannot remove themselves / the owner role)
- **Collaborator board access** — shared boards appear on the collaborator's boards index page; collaborators can open the board, create/edit/delete swimlanes and cards
- **Authorization update** — all controllers that currently scope by `Current.user.boards` must be updated to scope by boards the user is a member of (owned or shared); a collaborator may not delete or rename the board itself (owner-only actions)
- **No invite emails / invite links** — sharing is by exact email address of an existing user only; if the email is not found, show a validation error

### Out of Scope
- Inviting users who don't yet have an account (no sign-up invites)
- Role granularity beyond `owner` / `member` (no read-only, no admin)
- A collaborator transferring ownership
- Notification emails when someone is added to a board
- Real-time membership updates (Phase 5)
- Activity log showing who made which change

## Requirements
- A `board_memberships` join table exists with `board_id`, `user_id`, and `role` (enum: `owner`, `member`); a unique index on `[board_id, user_id]` prevents duplicates
- When a board is created, a `BoardMembership` row is created with `role: :owner` for the creating user
- The boards index page shows all boards where the current user has any membership (owned + shared)
- The board show page includes a "Members" section visible only to the board owner; it lists current members and provides a form to add a new member by email
- Submitting the add-member form with a valid existing-user email creates a `member`-role membership and updates the member list via Turbo Stream
- Submitting with an unknown email renders a validation error via Turbo Stream (no page reload)
- Removing a member from the board destroys the membership and updates the member list via Turbo Stream; the owner row has no remove link
- A collaborator (member role) can read the board, create/edit/delete swimlanes and cards — same capabilities as the owner for those resources
- A collaborator cannot delete the board, cannot rename the board (those actions remain owner-only)
- Accessing a board or any of its nested resources (swimlanes, cards) as a non-member returns 404 (not 403, to avoid leaking board existence)
- All existing authorization checks are updated to use the membership-scoped query; no resource is still gated only on `user_id == Current.user.id`

## Acceptance Criteria
- [ ] A board owner can open the board and see a "Members" panel listing the current members (initially just themselves)
- [ ] A board owner can type an existing user's email and submit to add that user as a member; the member list updates without a page reload
- [ ] Submitting a non-existent email shows an inline validation error without a page reload
- [ ] The newly added member sees the shared board on their boards index page after the next page load
- [ ] A collaborator can open a shared board and create a card in a swimlane
- [ ] A collaborator cannot see "Delete Board" or "Rename Board" controls
- [ ] A board owner can remove a collaborator; the member list updates without a page reload; the removed user no longer sees the board on their index
- [ ] A user who is not a member of a board receives 404 when accessing the board URL directly
- [ ] A user who is not a member receives 404 when accessing any nested resource (swimlane or card) on that board
- [ ] All existing tests continue to pass
- [ ] SimpleCov coverage remains at or above 80%
- [ ] All tests pass

## Testing Strategy
- **Minitest** for unit and integration tests:
  - **Unit — BoardMembership model**: validates presence of board, user, and role; prevents duplicate membership (uniqueness); `owner?` / `member?` predicate helpers if added
  - **Unit — Board model**: `#accessible_by(user)` (or equivalent) scope returns boards where user has any membership
  - **Integration — Add member**: POST to add-member endpoint with valid email creates membership, returns Turbo Stream updating member list; POST with unknown email returns Turbo Stream with error message
  - **Integration — Remove member**: DELETE destroys membership, returns Turbo Stream; attempting to remove the owner row is rejected
  - **Integration — Collaborator board access**: a member-role user can GET board show, POST cards, PATCH cards, DELETE cards; returns 200/redirect, not 404
  - **Integration — Owner-only actions**: collaborator DELETE/PATCH on the board itself returns 404
  - **Integration — Non-member access**: GET on board, swimlane, card for a non-member returns 404
  - **Auth boundary regression**: verify that existing boards created in Phase 1-3 pattern are still accessible to owners after the migration to membership-scoped queries
- **Playwright E2E**:
  - E2E: Owner adds a collaborator by email; signs out; signs in as collaborator; navigates to boards index; opens the shared board; creates a card; verifies card appears
  - E2E: Owner removes collaborator; collaborator's boards index no longer shows the board
  - E2E: Non-member directly navigates to board URL; page shows 404 (or redirect to root)
- **Coverage**: SimpleCov must stay at or above 80%; new membership and controller paths are covered

## Documentation Updates
- **AGENTS.md**: Add `BoardMembership` to the data model section (`board_id`, `user_id`, `role enum`); update the authorization section to describe membership-scoped access; document any new routes (`boards/:id/memberships`)
- **README.md**: Update the feature list to mark Phase 4 complete; add a sentence describing board sharing and the email-based add-member flow

## Dependencies
- Phases 1–3 must be complete and all tests passing
- No new external libraries required — email lookup is a simple `User.find_by(email:)` call; Turbo Streams already in place
- No environment variables or external services needed

## Adjustments from Previous Phase

Phase 3 had no REFLECTIONS.md (it ended at MUST-FIX), but the review and must-fix documents surface clear lessons:

1. **Fix before feature — carryover from Phase 3 review**: The Phase 3 review noted the README Phase 3 entry is missing its `✓` checkmark. Fix this cosmetic issue as the very first task before any Phase 4 work.
2. **Turbo Stream consistency — no `_top` shortcuts**: The Phase 3 critical bug was description and due-date forms using `turbo_frame: "_top"`, causing page reloads. Phase 4's add-member and remove-member actions must use Turbo Streams from the start — no `_top` escape hatches.
3. **Assert rendered HTML, not just model state**: Phase 3's weak integration tests checked `model.reload` but not the response body. Phase 4 integration tests for add/remove member must assert the Turbo Stream response body contains the updated member list HTML.
4. **Authorization scope is wide — audit every controller**: The shift from `Current.user.boards.find()` to membership-scoped access touches every controller. The plan must include an explicit checklist of all controllers to update, and an integration test for each that verifies non-member access returns 404.
5. **Manual smoke test before committing**: Following Phase 2's lesson, run a manual smoke test of the add-member flow (add → verify member list → sign in as collaborator → verify board visible) before any commit.
