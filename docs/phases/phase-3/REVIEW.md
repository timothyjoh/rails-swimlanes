# Phase Review: Phase 3

## Overall Verdict

**NEEDS-FIX** — see MUST-FIX.md

Two issues require fixing: the drag E2E test does not verify that card order changed (it only confirms count), and the `update card with past due date` integration test asserts the model is overdue but never asserts the Turbo Stream response body contains the overdue CSS class. Both tests are misleading — they pass regardless of whether the UI behavior is correct.

---

## Code Quality Review

### Summary

Phase 3 is a solid, complete implementation. All spec requirements are delivered: description, due date, labels, card detail modal, DB-level ordering, E2E drag replacement, and documentation updates. Authorization chains are correct. The Tailwind dynamic-color lookup-hash mitigation (from the risk register) is implemented correctly in both `_face.html.erb` and `_detail.html.erb`. The N+1 risk is addressed with `includes(cards: :labels)` in `BoardsController#show`. The `hidden_field_tag` sentinel for empty `label_ids` arrays is present. SimpleCov is at 87.05% (above the 80% threshold).

One minor structural concern: the description and due-date forms in `_detail.html.erb` use `data: { turbo_frame: "_top" }`, which causes the page to fully reload on save (redirecting to the board path). This means the modal closes and the page reloads rather than staying in the detail view. This is functional but inconsistent with the spec's intent ("saved via Turbo Stream"). The label form does NOT have `turbo_frame: "_top"` so it behaves differently (stays in frame). This inconsistency is confusing UX and a spec compliance gap.

### Findings

1. **Spec Compliance — Description/due-date forms use `_top` navigation, not Turbo Stream**: `app/views/cards/_detail.html.erb:4` and `:15` — both description and due-date forms are tagged with `data: { turbo_frame: "_top" }`. This causes a full-page navigation on save (the controller's `format.html { redirect_to @board }` fires), not a Turbo Stream partial update. The spec requires "saved via Turbo Stream" and "no page reload". The label form (line 29) does not set this attribute, so label saves stay in-frame. This creates an inconsistent UX.

2. **Minor — Close button uses inline JS**: `app/views/cards/show.html.erb:6` — the close button uses an inline `onclick` with raw DOM manipulation (`removeChild` loop). This works but is fragile: if the Turbo Frame element structure changes, the script breaks silently. A tiny Stimulus action (`data-action="click->dialog#close"`) or a simple `<a>` navigating the frame to an empty path would be more maintainable.

3. **Minor — README still lists Phase 3 as in-progress**: `README.md:77` — `Phase 3 — Card details (descriptions, due dates, labels, checklists)` lacks the `✓` checkmark that Phases 1 and 2 have. This is cosmetic but inconsistent with the completed state.

4. **Minor — `update_card_with_past_due_date` integration test assertion is weak**: `test/integration/cards_flow_test.rb:125` — the test asserts `card.reload.overdue?` (model state) but the SPEC and PLAN both say to assert the Turbo Stream response body contains the overdue CSS class. The response body check is the meaningful test here — verifying the HTML rendered to the browser.

### Spec Compliance Checklist

- [x] Clicking a card opens the card detail view via Turbo Frame — no full page reload
- [ ] Card description saves via Turbo Stream — description form uses `_top` causing full page redirect
- [ ] Card due date saves via Turbo Stream — due-date form uses `_top` causing full page redirect
- [x] Labels save correctly (label form does not force `_top`)
- [x] Card face shows description indicator when description is present
- [x] Card face shows due date badge; overdue badge is red
- [x] Card face shows label color chips
- [x] DB-level card ordering via association scope (`has_many :cards, -> { order(:position) }`)
- [x] `sort_by(&:position)` removed from swimlane partial
- [x] Reorder bounds guard (clamp) in place — `cards_controller.rb:75`
- [x] E2E drag test replaced with real DOM mouse interaction (no fetch stub)
- [x] Authorization: wrong-user card show returns 404
- [x] Labels table + card_labels join table created and migrated
- [x] 5 predefined label colors seeded via `db/seeds.rb`
- [x] Tailwind dynamic color classes use lookup hash (no purge risk)
- [x] `hidden_field_tag` sentinel for empty label_ids array present
- [x] N+1 on label loading addressed with `includes(cards: :labels)`
- [x] AGENTS.md updated with Label, CardLabel, card detail route
- [x] README updated with Phase 3 feature list
- [ ] README Phase 3 entry missing `✓` checkmark (minor)
- [x] SimpleCov ≥ 80% (87.05%)

---

## Adversarial Test Review

### Summary

Test quality is **adequate** overall. Model unit tests are thorough. Integration tests cover auth boundaries and the main happy paths. The main weaknesses are: (1) the drag E2E test does not assert order changed — it only asserts count, making it vacuous as a drag-reorder test; (2) the overdue CSS integration test is too shallow.

### Findings

1. **Vacuous assertion — drag reorder E2E test**: `e2e/board_canvas.spec.js:70` — `await expect(cards).toHaveCount(2)` only confirms both cards still exist after drag. It does NOT assert that `secondCard` is now before `firstCard` in the DOM. The drag may have had zero effect and the test would still pass. This directly contradicts the acceptance criterion: "E2E drag test... verifies the DOM order has changed." The test replaced the fetch stub as required but the meaningful assertion — order verification — was not added.

2. **Weak assertion — overdue badge in turbo stream response**: `test/integration/cards_flow_test.rb:125` — `assert card.reload.overdue?` verifies the model was saved correctly but does NOT verify the rendered Turbo Stream response includes the overdue CSS class (`overdue` or `bg-red-100`). If the `_face.html.erb` template had a bug in the overdue conditional, this test would still pass. The plan explicitly calls for asserting the "overdue CSS class in response."

3. **Missing test — upcoming scope today boundary**: `test/models/card_test.rb:79` — the `upcoming` scope tests "future" and "past" cards but the scope is `due_date >= Date.current`. Today's date is the boundary — a card due today should be in `upcoming`, not `overdue`. There is an `overdue?` test for today (`overdue? returns false when due_date is today`) but no corresponding `upcoming` scope test asserting today is included in upcoming results.

4. **Missing test — label N+1 verified**: No test asserts that `BoardsController#show` loads labels without N+1 queries. This is lower-priority but the risk was explicitly flagged in the plan. A Minitest `assert_queries` or Bullet gem check would catch regressions.

5. **Happy-path only — label toggle**: `test/integration/cards_flow_test.rb:128-147` — the "add label" test sends a valid label ID and the "remove label" test uses the sentinel `[""]`. Neither tests sending an invalid/nonexistent label ID. This is a minor gap (Rails will silently ignore unknown IDs through `label_ids=`) but worth noting for completeness.

6. **No integration test for Turbo Stream response body on label save**: The plan calls for "assert response includes label color class" in `test/integration/cards_flow_test.rb`. The `add label to card` test (line 128) asserts `card.reload.labels` includes the label (model state) but does not check the rendered Turbo Stream for label chip HTML. Same pattern as finding #2.

### Test Coverage

- SimpleCov line coverage: **87.05%** (above 80% threshold — pass)
- Missing test cases identified:
  - E2E drag test: assertion that second card appears before first card after drag
  - Integration: Turbo Stream response body contains overdue CSS class after past-due date update
  - Integration: Turbo Stream response body contains label chip HTML after label add
  - Model: `upcoming` scope includes today's date (boundary condition)
