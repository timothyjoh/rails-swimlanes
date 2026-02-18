# Reflections: Phase 2

## Looking Back

### What Went Well

- **Incremental delivery matched the plan closely**: 8 tasks in PLAN.md mapped almost 1:1 to the git log — models, routes, controllers, views, drag-and-drop, E2E tests, and docs all landed in the expected order.
- **Authorization pattern held**: The `Current.user.boards.find()` approach consistently produced 404s for cross-user access across swimlanes and cards. No scope leaks were found in review.
- **Coverage floor maintained**: SimpleCov hit 85.59%, above the 80% hard floor, even after adding two new controllers and a Stimulus reorder endpoint.
- **N+1 addressed proactively**: The swimlane partial N+1 was caught during build (not review) and fixed by passing `board` as a local variable — `eae9ce0`.
- **E2E shared auth helpers**: Extracting the shared signup helper into a common module (`87f7c00`) was the right call and reduced test duplication across spec files.
- **Reorder race condition fixed**: The PATCH reorder endpoint race was identified and resolved (`2cb8b91`) before review, showing good defensive instinct on async operations.

### What Didn't Work

- **`sort_by(&:position)` in Ruby instead of SQL order**: The swimlane partial sorted cards in Ruby after loading, bypassing the DB-level ordering that was already in place. This is fragile under load and inconsistent with the project's established pattern of `.order(:position)` in scopes. Root cause: the partial was written quickly without checking how the parent query fetched associations.
- **Reorder lacks bounds guard**: Passing `position` values larger than the card count hits `NoMethodError` on `nil`. A one-line guard (`position.clamp(0, cards.length - 1)`) was deferred past review. Root cause: happy-path testing only; no negative input tests for the reorder action.
- **Swimlane partial used `<div>` instead of `turbo_frame_tag`**: The PLAN explicitly called for a `turbo_frame_tag` wrapping swimlane headers, but the implementation used a plain div. This means turbo frame scoping doesn't work as intended for inline edits. The cancel link then had nowhere to return to, causing it to load the full board page into the frame.
- **New swimlane append order**: Turbo Stream `append` puts new lanes after the "Add Lane" button column because that column is inside the same container. Order matters with Turbo Streams and this wasn't verified manually until review.
- **Missing boards#show authorization test**: The board canvas rendering under auth constraints was called out in RESEARCH.md as untested and wasn't added until the fix commit (`b3f839a`). Should have been caught during the build step.
- **E2E drag tests simulate via PATCH instead of DOM**: The Playwright drag tests issue a direct `fetch` PATCH call rather than actually dragging DOM elements. This tests the endpoint but not the Stimulus controller or SortableJS integration. It's the weakest part of E2E coverage.

### Spec vs Reality

- **Delivered as spec'd**: Swimlane CRUD with Turbo Frames/Streams; Card CRUD with Turbo Streams; drag-and-drop reorder within and across lanes; authorization scoped to current user; position auto-assignment; AGENTS.md and README.md updated; coverage above 80%.
- **Deviated from spec**: Swimlane header used `<div>` wrapper instead of `turbo_frame_tag` as PLAN specified. Cancel link behavior is broken as a result.
- **Deferred**: Reorder bounds validation (still needs a guard clause). True DOM-level E2E drag testing (currently mocked via fetch). Swimlane rename flow E2E coverage.

### Review Findings Impact

- **Ruby sort vs SQL order**: Acknowledged, partial fix possible by adding `.order(:position)` to the association includes — not yet committed; should be first task in Phase 3 cleanup.
- **Reorder bounds guard**: Identified; not yet fixed. Risk: any client that sends a bad position value crashes the action.
- **`<div>` vs `turbo_frame_tag` in swimlane partial**: Root cause of the cancel-link bug. Needs a targeted fix to wrap the swimlane header in a proper Turbo Frame.
- **boards#show auth test**: Fixed in `b3f839a` — integration test added for authenticated and cross-user board access.
- **Append order for new swimlanes**: Not yet fixed; visual regression that puts new lanes after the Add button.

---

## Looking Forward

### Recommendations for Next Phase

- **Fix the three carried-over bugs before adding features**: (1) `turbo_frame_tag` wrapper in swimlane partial + cancel link, (2) reorder bounds guard, (3) new-swimlane append order. These are shallow fixes but will create compounding confusion if left in.
- **Establish a DOM-level E2E drag test**: The Playwright drag test should actually drag an element. Use `page.dragAndDrop()` or the Playwright `mouse` API. The current PATCH stub tests the API, not the UI.
- **Add the `.order(:position)` scope to the card association**: Fix the Ruby sort anti-pattern by adding a default scope or explicit order on the `has_many :cards` association in Swimlane, then remove the `sort_by` from the partial.
- **Watch for Turbo Frame ID collisions**: As the UI grows, `turbo_frame_tag` IDs based on `dom_id(record)` must remain globally unique per page. With nested records (cards inside swimlanes), verify that card frame IDs are scoped to their swimlane.

### What Should Next Phase Build?

Based on BRIEF.md, Phase 3 should target **Card Details** — the expanded card view with:
- Card description (rich text or plain text area)
- Due date field
- Labels (color tags, likely a simple enum or join table)
- Checklist items (a sub-model `ChecklistItem` with card_id, text, completed)

Suggested scope for Phase 3:
1. **Carry-over fixes** (turbo_frame, reorder guard, append order, sort order) — small, do first
2. **Card detail modal or slide-over**: clicking a card opens an expanded view (Turbo Frame or modal)
3. **Description field**: textarea, saved via Turbo Stream, displayed on card face if present
4. **Due date**: date field, shown on card face with overdue styling
5. **Labels**: simple color-coded tags, added/removed from card detail view

Defer checklists to Phase 4 — they introduce a new model and more complex Turbo interactions; keep Phase 3 focused.

### Technical Debt Noted

- **Ruby sort instead of SQL order in swimlane partial**: `app/views/swimlanes/_swimlane.html.erb` — replace `sort_by(&:position)` with DB-level ordering via association scope.
- **Reorder action missing bounds guard**: `app/controllers/cards_controller.rb` `reorder` action — add `position.clamp(0, swimlane.cards.count - 1)` before indexing.
- **Swimlane header wrapped in `<div>` not `turbo_frame_tag`**: `app/views/swimlanes/_swimlane.html.erb` — the header partial needs a proper Turbo Frame so inline edit cancel works correctly.
- **New swimlane append order**: `app/views/swimlanes/_swimlane.html.erb` or boards template — use `prepend` or restructure the "Add Lane" button out of the swimlane container so `append` places new lanes correctly.
- **E2E drag test uses fetch stub**: `e2e/` spec — replace with actual Playwright `dragAndDrop()` call to test the Stimulus + SortableJS integration end-to-end.

### Process Improvements

- **Verify Turbo Frame IDs in the plan, not in review**: The `<div>` vs `turbo_frame_tag` mistake was visible in the PLAN but wasn't caught until code review. Next phase should include a plan-level checklist item: "confirm all Turbo Frame IDs are unique and correctly scoped."
- **Add negative-input integration tests as part of each controller task**: The reorder bounds bug would have been caught if PLAN.md had included a test for `position: 999` alongside the happy path.
- **E2E tests should be written against real DOM interactions from the start**: The shortcut of issuing direct fetch calls in Playwright produces weak coverage. Consider adding a rule: E2E tests must interact through the UI (click, type, drag) — no raw API calls unless testing the API itself.
- **Manual smoke test of new-item append before committing**: The swimlane append order bug is a one-second visual check. Add a step in the build checklist: "create a new item and verify it appears in the correct position in the UI."
