# Phase Review: Phase 2

## Overall Verdict
NEEDS-FIX — see MUST-FIX.md

---

## Code Quality Review

### Summary
The implementation is solid and complete. All major spec requirements are delivered: models, CRUD controllers, Turbo Streams/Frames, SortableJS integration, and nested routes. Tests pass at 85.59% coverage (above the 80% floor). Two issues warrant fixes: a N+1-adjacent Ruby sort in the swimlane partial that bypasses the eager-load ordering, and an unhandled edge case in the `reorder` action that can corrupt positions when the `position` parameter exceeds the lane's card count.

### Findings

1. **Ruby-level sort bypasses DB ordering** — `app/views/swimlanes/_swimlane.html.erb:21`
   `swimlane.cards.sort_by(&:position)` sorts an already-loaded ActiveRecord relation in Ruby. The `includes(:cards)` in `BoardsController#show` loads cards without an order clause, so the Ruby sort is necessary for correctness — but it silently discards the SQL ordering benefit. The PLAN specified `render swimlane.cards.order(:position)` (Task 4); the actual implementation diverges with a Ruby sort. This is functionally correct but inconsistent with the pattern established everywhere else (DB-level ordering), and it will silently fall back to insertion order if `sort_by` is ever removed.

2. **`reorder` action: `insert` at out-of-bounds position is not guarded** — `app/controllers/cards_controller.rb:70-75`
   `cards.insert(target_position, card)` — Ruby's `Array#insert` with a position greater than `cards.length` pads with `nil` entries. If the client sends `position: 99` for a 2-card lane, `cards` becomes `[card1, card2, nil, nil, ..., card]`. The subsequent `each_with_index` will call `nil.update_columns`, raising `NoMethodError`. The SortableJS controller sends `event.newIndex` which is bounded by DOM reality during normal use, but there is no server-side guard — any raw PATCH request can trigger this.

3. **`_swimlane.html.erb` does not wrap content in a Turbo Frame** — `app/views/swimlanes/_swimlane.html.erb:1`
   The PLAN and SPEC described wrapping each swimlane in `turbo_frame_tag dom_id(swimlane)`. The actual implementation uses a plain `<div id="<%= dom_id(swimlane) %>">`. The Turbo Stream `remove` in `destroy` and `append` in `create.turbo_stream.erb` target this DOM id correctly via id attribute, so delete and create work. However, the absence of a Turbo Frame means the `edit` action response (a partial) cannot be scoped to a frame for the swimlane container itself. The header Turbo Frame (`dom_id(swimlane, :header)`) handles rename correctly, so this is not a functional bug — but it diverges from the PLAN's design and could cause confusion in future phases.

4. **`create.turbo_stream.erb` appends swimlane before "Add Lane" form column** — `app/views/swimlanes/create.turbo_stream.erb:1`
   `turbo_stream.append "swimlanes"` appends to the `#swimlanes` container, which also contains the "Add Lane" form column (`<div class="flex-shrink-0 w-64">`). A new swimlane will be inserted *before* the form column because `append` adds to the end of `#swimlanes`, but the form div is the last child. Wait — `append` inserts as the last child of `#swimlanes`, which would place the new swimlane *after* the "Add Lane" form column div. This means newly created swimlanes render to the right of the "Add Lane" input, not before it.

5. **`boards#show` integration test missing** — `test/integration/`
   The SPEC explicitly states: "Spec and test the `show` action from day one … it must have an authorization test and full view coverage." No integration test file covers `boards#show` verifying that `@swimlanes` is assigned and that an unauthorized user gets 404. The swimlane flow tests call `post` but never `get board_path(@board)` to verify the board canvas renders correctly.

6. **`cancel` link in `_edit_form.html.erb` navigates away instead of restoring header** — `app/views/swimlanes/_edit_form.html.erb:9-11`
   `link_to "Cancel", board_path(board)` with `data: { turbo_frame: dom_id(swimlane, :header) }` will load the entire board show page inside the `header` Turbo Frame, not restore the header partial. The Cancel link should point to `edit_board_swimlane_path(board, swimlane)` — no wait, it needs to render the *header* partial, not the edit form. The correct target is `board_swimlane_path` but that doesn't have a GET route. A simpler approach is a link back to the edit endpoint which re-renders the header, but the implemented Cancel link will stuff the whole board HTML into the frame.

### Spec Compliance Checklist

- [x] Swimlane model: `name`, `position`, `belongs_to :board`
- [x] Card model: `name`, `position`, `belongs_to :swimlane`
- [x] Both models validate `name` presence and strip whitespace
- [x] Swimlanes displayed in position order (ascending)
- [x] Cards within each lane displayed in position order
- [x] Creating a swimlane appends at end (max position + 1)
- [x] Creating a card appends at bottom (max position + 1)
- [x] Deleting a swimlane cascades to destroy all its cards
- [x] All routes nested under `/boards/:board_id`; card routes also under `swimlanes/:swimlane_id`
- [x] Drag-and-drop updates card position server-side via PATCH
- [x] Board `show` enforces user ownership
- [x] No swimlane/card action succeeds for boards the current user doesn't own
- [x] Explicit `before_action :require_authentication` in `ApplicationController`
- [x] Board name strip/whitespace validation added
- [x] SortableJS integrated via importmap
- [x] AGENTS.md and README.md updated
- [ ] `boards#show` has authorization integration test (missing)
- [ ] `reorder` endpoint guards against out-of-bounds position input
- [ ] Newly created swimlane renders *before* "Add Lane" form (Turbo Stream append order issue)
- [ ] Cancel link on swimlane rename form works correctly

---

## Adversarial Test Review

### Summary
Test quality is **strong** overall. The integration tests are comprehensive — they cover cross-user authorization for all three CRUD operations on both swimlanes and cards (not just create), and the reorder tests cover within-lane, cross-lane, cross-user, and unauthenticated cases. Model tests cover position scoping per-board/per-swimlane. No mock abuse — all tests use real database objects.

### Findings

1. **`swimlanes_flow_test.rb`: destroy test asserts -1 for both Swimlane and Card counts** — `test/integration/swimlanes_flow_test.rb:41`
   ```ruby
   assert_difference ["Swimlane.count", "Card.count"], -1 do
   ```
   The swimlane has 1 card (`Card A`), so both counts drop by 1. If the cascade destroy were broken and cards were NOT deleted, the `Card.count` assertion would still pass because `Card.count` alone dropping by 1 when the card isn't destroyed would fail… but actually this assertion checks that *both* drop by exactly 1, which is what happens correctly. However, the test only adds 1 card to verify cascade. A stronger test would add 2+ cards and assert `Card.count` drops by 2, making the cascade assertion unambiguous.

2. **`cards_reorder_test.rb`: "moves card to another lane" only checks `swimlane_id`, not `position`** — `test/integration/cards_reorder_test.rb:28-29`
   ```ruby
   assert_equal @lane2.id, @card1.reload.swimlane_id
   assert_equal 0, @card1.reload.position
   ```
   This is actually fine — position 0 is checked. No issue.

3. **No test for `reorder` with out-of-bounds `position`** — `test/integration/cards_reorder_test.rb`
   The `reorder` action has a bug (see Code Quality finding #2) where `position` beyond the array size will raise `NoMethodError`. There is no test covering this case — a malformed or adversarial PATCH to `reorder` with `position: 999` would blow up with a 500 rather than returning a validation error or clamping.

4. **`SwimlanesFlowTest`: success path asserts redirect, not Turbo Stream response** — `test/integration/swimlanes_flow_test.rb:14`
   ```ruby
   post board_swimlanes_path(@board), params: { swimlane: { name: "To Do" } }
   assert_redirected_to board_path(@board)
   ```
   The HTML format response redirects, but the primary client-facing format is Turbo Stream (since the form includes `data: { turbo_frame: }` and is submitted via Turbo). The test covers the HTML fallback but the turbo_stream path is covered by the separate "creates a swimlane via turbo stream" test. This is adequate but slightly backwards — the Turbo Stream path is the primary path in production.

5. **No test for `boards#show` rendering swimlanes** — `test/integration/`
   There is no integration test that performs `get board_path(@board)` and asserts the response renders swimlane data. This is the spec's primary acceptance criterion ("Navigating to `/boards/:id` shows the board name and all its swimlanes in order") but it has no corresponding Minitest coverage.

6. **Card model test missing cascade-destroy test** — `test/models/card_test.rb`
   `CardTest` covers validations, position, and association, but does not test that deleting the parent swimlane destroys cards (though this is tested in `SwimlaneTest`). This is adequate given the cascade is defined on `Swimlane`, not `Card`.

7. **E2E "drag card" tests use `page.evaluate` to call the PATCH endpoint directly rather than DOM drag** — `e2e/board_canvas.spec.js:8-33`
   The drag-and-drop E2E tests bypass the actual SortableJS drag interaction and instead call the server PATCH endpoint via `fetch`. This means the tests verify server-side persistence but do NOT test: (a) that SortableJS initializes correctly, (b) that the Stimulus controller's `onEnd` fires and reads the correct `data-sortable-url-value`, (c) that the CSRF token is correctly read from the meta tag. These are real failure modes that the current E2E suite would not catch. The comment in the file acknowledges this ("simulates what SortableJS does on drag-end"), but it's a significant coverage gap for the drag-and-drop feature.

8. **E2E "rename swimlane" not tested** — `e2e/board_canvas.spec.js`
   The E2E suite covers create/delete swimlane, create/delete card, and drag. It does not cover the rename (inline edit) flow for swimlanes or cards. Given the Cancel link bug (Code Quality finding #6) this gap is particularly risky.

### Test Coverage
- **Line Coverage**: 85.59% (202/236) — above the 80% floor ✓
- **Missing test cases identified**:
  - `boards#show` integration test (board canvas renders with swimlanes)
  - `reorder` with out-of-bounds position (server-side robustness)
  - Cascade destroy with 2+ cards to make the assertion unambiguous
  - E2E: rename swimlane and card inline edit flows
  - E2E: actual DOM drag interaction (not just the PATCH endpoint call)
