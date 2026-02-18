# Phase 2: Swimlanes and Cards with Drag-and-Drop

## Objective
Deliver a fully interactive board view where users can manage swimlane columns and cards within those columns. A user navigates to a board, sees its lanes side-by-side, adds/renames/deletes lanes and cards, and can drag cards to reorder within a lane or move them between lanes. This is the core Trello-like canvas — the feature that makes the app usable as a task management tool.

## Scope

### In Scope
- Promote the existing sparse `boards#show` to a full board canvas view rendering swimlanes and cards
- Swimlane (column) model: `name`, `position`, `belongs_to :board`; Board `has_many :swimlanes, dependent: :destroy`
- Card model: `name`, `position`, `belongs_to :swimlane`; Swimlane `has_many :cards, dependent: :destroy`
- Swimlane CRUD: create, rename, delete lanes within a board (Turbo Frames/Streams for inline interaction)
- Card CRUD: create, rename, delete cards within a lane (Turbo Frames/Streams for inline interaction)
- Drag-and-drop card reordering within a lane and moving between lanes via SortableJS
- Position update endpoint (`PATCH /boards/:board_id/swimlanes/:swimlane_id/cards/:id`) to persist sort order
- Authorization: all swimlane/card actions scoped to the current user's boards only
- Fix the Phase 1 technical debt: add explicit `before_action :require_authentication` to `ApplicationController`
- Add name strip/validation to prevent whitespace-only swimlane and card names
- Minitest unit + integration tests for all new models and controllers
- Playwright E2E tests for the board canvas interactions

### Out of Scope
- Card detail modal (descriptions, due dates, labels, checklists) — Phase 3
- Swimlane drag-to-reorder (column reordering) — can be deferred to Phase 3
- Board sharing / multi-user access — Phase 4
- Real-time ActionCable updates — Phase 5
- Board background customization — Phase 6

## Requirements
- Swimlane has `name` (string, not null), `position` (integer, not null, default 0), and `board_id` (foreign key, not null)
- Card has `name` (string, not null), `position` (integer, not null, default 0), and `swimlane_id` (foreign key, not null)
- Both models validate `name` presence and strip whitespace before validation
- Swimlanes are displayed in `position` order (ascending); cards within each lane are displayed in `position` order
- Creating a swimlane appends it at the end (max position + 1)
- Creating a card appends it at the bottom of its lane (max position + 1)
- Deleting a swimlane cascades to destroy all its cards
- All swimlane and card routes are nested under `/boards/:board_id`; card routes also nested under `swimlanes/:swimlane_id`
- Drag-and-drop updates card position server-side via a PATCH request; response is Turbo Stream or JSON
- The board `show` page must enforce user ownership (current user must own the board)
- No swimlane or card action may succeed for a board the current user doesn't own

## Acceptance Criteria
- [ ] Navigating to `/boards/:id` shows the board name and all its swimlanes in order
- [ ] A user can add a new swimlane by typing a name and submitting; it appears immediately without full page reload
- [ ] A user can rename a swimlane inline; the updated name persists
- [ ] A user can delete a swimlane; it and all its cards are removed immediately
- [ ] A user can add a card to a lane by typing a name and submitting; it appears at the bottom of the lane
- [ ] A user can rename a card inline; the updated name persists
- [ ] A user can delete a card; it is removed immediately
- [ ] A user can drag a card to a new position within the same lane; the order persists after page reload
- [ ] A user can drag a card from one lane to another; the card appears in the new lane and order persists after reload
- [ ] Attempting to access another user's board returns 404 (not a redirect that leaks board existence)
- [ ] Whitespace-only names for swimlanes or cards are rejected with a validation error
- [ ] All tests pass
- [ ] Code compiles without warnings
- [ ] SimpleCov coverage remains at or above 80%

## Testing Strategy
- **Framework**: Minitest (existing setup from Phase 1) with SimpleCov coverage
- **Unit tests** (`test/models/`): Swimlane and Card model validations, associations, position defaults, cascade destroy
- **Integration tests** (`test/integration/` or controller tests): Swimlane CRUD scoped to board owner, Card CRUD scoped to swimlane owner, position PATCH endpoint, cross-user access returns 404
- **E2E tests** (`test/e2e/` via Playwright): Full board canvas — create swimlane, create card, drag card within lane, drag card between lanes, verify persistence after reload
- **Key scenarios to cover**:
  - Creating a swimlane when unauthenticated redirects to login
  - Creating a card under another user's board returns 404
  - Dragging a card and reloading the page shows the new order
  - Deleting a swimlane removes all its cards from the page
- **Coverage**: maintain 80%+ floor; review should call out any new file below 80%

## Documentation Updates
- **AGENTS.md**: Add notes on SortableJS integration, nested route structure, and any new `bin/` scripts introduced
- **README.md**: Update feature list to include Swimlanes and Cards; add any new setup steps if SortableJS requires a build step
- **CLAUDE.md**: No pipeline changes needed; architecture notes for nested routes and position update pattern are sufficient in AGENTS.md

Documentation is part of "done" — code without updated docs is incomplete.

## Dependencies
- Phase 1 complete: Rails 8 app running, authentication working, Board model and CRUD functional
- SortableJS available (via importmap or npm/esbuild — match whatever asset pipeline was set up in Phase 1)
- Existing `boards#show` action and view as the starting scaffold

## Adjustments from Previous Phase

Based on Phase 1 REFLECTIONS.md:

1. **Fix `ApplicationController` explicit auth**: Add `before_action :require_authentication` explicitly at the top of `ApplicationController` — do not rely on implicit concern behavior.
2. **Spec and test the `show` action from day one**: The Phase 1 `show` stub was out-of-scope and untested. Phase 2 owns it fully — it must have an authorization test and full view coverage.
3. **Commit granularly**: Each logical task (model + migration, controller, views, tests) should be committed separately, not bundled into one phase-level commit.
4. **Verify plan checklist before marking tasks done**: Build agent must check each `[ ]` in the PLAN success criteria before declaring a task complete.
5. **Add strip validation for names**: Phase 1 reflection flagged whitespace-only board names; apply `strip` + `presence` to all name fields introduced in Phase 2 (swimlanes, cards) and fix Board while we're in the model layer.
6. **E2E seed strategy**: Playwright tests should use a consistent seed/setup helper rather than signing up fresh in every test, to keep tests fast and less brittle as interaction complexity grows.
