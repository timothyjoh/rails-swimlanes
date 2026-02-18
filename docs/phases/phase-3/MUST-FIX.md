# Must-Fix Items: Phase 3

## Summary

3 issues found: 1 critical, 2 minor. All fixed.

- **Critical**: Description and due-date forms use `turbo_frame: "_top"`, causing full-page reloads on save instead of Turbo Stream updates (spec violation).
- **Minor**: E2E drag test does not assert card order changed — assertion is vacuous.
- **Minor**: Integration test for overdue badge asserts model state only, not rendered HTML.

---

## Tasks

### Task 1: Fix description and due-date forms to save via Turbo Stream (no full-page reload)

**Priority:** Critical
**Files:** `app/views/cards/_detail.html.erb`
**Status:** ✅ Fixed
**What was done:** Removed `data: { turbo_frame: "_top" }` from the description form (line 4) and the due-date form (line 15) in `_detail.html.erb`. Both forms now submit within the surrounding Turbo Frame context, routing through `format.turbo_stream` in the controller instead of triggering a full-page redirect.

---

### Task 2: Fix E2E drag test to assert DOM order changed after drag

**Priority:** Minor
**Files:** `e2e/board_canvas.spec.js`
**Status:** ✅ Fixed
**What was done:** Replaced the vacuous `toHaveCount(2)` assertion with an order assertion using `allTextContents()`. After the drag, the test now finds the indices of "Second Card" and "First Card" in the DOM and asserts `secondIdx < firstIdx`, confirming the card actually moved.

---

### Task 3: Strengthen overdue badge integration test to assert rendered HTML

**Priority:** Minor
**Files:** `test/integration/cards_flow_test.rb`
**Status:** ✅ Fixed
**What was done:** Added `assert_match "overdue", response.body` after `assert card.reload.overdue?` in the `"update card with past due date shows overdue indicator"` test. This confirms the Turbo Stream response body includes the overdue CSS class string, not just that the model was saved correctly.
