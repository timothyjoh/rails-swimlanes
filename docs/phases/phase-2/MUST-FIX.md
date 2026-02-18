# Must-Fix Items: Phase 2

## Summary
4 issues found: 2 critical (runtime error + UI defect), 2 minor (missing test + CSS sort deviation).

---

### Task 1: Guard `reorder` against out-of-bounds position
**Status:** ✅ Fixed
**What was done:** Moved the clamp `target_position = [[target_position, 0].max, cards.length].min` to after the `cards` array is built (so `cards.length` is the correct upper bound). Added `test "clamps out-of-bounds position to last"` to `test/integration/cards_reorder_test.rb`.

---

### Task 2: Fix Turbo Stream append order — new swimlane renders after "Add Lane" form
**Status:** ✅ Fixed
**What was done:** Restructured `app/views/boards/show.html.erb` so `#swimlanes` is a nested div containing only swimlane columns, and the "Add Lane" form wrapper is a sibling div outside `#swimlanes`. `turbo_stream.append "swimlanes"` now inserts new swimlanes before the form column.

---

### Task 3: Fix Cancel link in swimlane edit form
**Status:** ✅ Fixed
**What was done:** Added `get :header` member route to swimlanes in `config/routes.rb`. Added `header` action to `SwimlanesController` that renders the `_header.html.erb` partial. Added `:header` to the `set_swimlane` before_action. Updated the Cancel link in `_edit_form.html.erb` to point to `header_board_swimlane_path(board, swimlane)`. Added `test "gets swimlane header"` to `test/integration/swimlanes_flow_test.rb`.

---

### Task 4: Add `boards#show` authorization integration test
**Status:** ✅ Fixed
**What was done:** Added `test "shows board with swimlanes"` to `test/integration/boards_flow_test.rb` — creates a board + swimlane, GETs the board path, asserts 200 and the swimlane name appears in the response body. The "cannot view another user's board" test already existed in that file.
