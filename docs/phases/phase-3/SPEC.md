# Phase 3: Card Details

## Objective
Phase 3 turns cards from simple titles into rich work items. Users can open a card detail view and add a description, set a due date, and attach color-coded labels — making cards useful for tracking real work. The phase also closes five pieces of technical debt carried forward from Phase 2 before any new features land, ensuring the foundation is stable before it grows.

## Scope

### In Scope
- **Carry-over bug fixes** (first, before new features):
  - Replace `sort_by(&:position)` in the swimlane partial with DB-level ordering via association scope
  - Add `turbo_frame_tag` wrapper to swimlane header so inline-edit cancel works correctly
  - Add reorder bounds guard (`clamp`) to cards reorder action
  - Fix new-swimlane append order so new lanes appear before the "Add Lane" button
  - Replace E2E drag test fetch stub with real Playwright `dragAndDrop()` DOM interaction
- **Card detail modal/slide-over**: clicking a card title opens an expanded card view (Turbo Frame or Turbo Modal pattern)
- **Card description**: free-text area on the detail view; saved via Turbo Stream; truncated preview shown on the card face if present
- **Due date**: date input on the detail view; displayed on the card face; overdue cards styled distinctly (e.g., red badge)
- **Labels**: a small set of color-coded tags (e.g., Red, Yellow, Green, Blue, Purple) that can be toggled on/off from the card detail view; selected labels shown as color chips on the card face

### Out of Scope
- Checklists / checklist items (deferred to Phase 4 — introduces a new sub-model with complex Turbo interactions)
- Card attachments or image uploads
- Rich-text / WYSIWYG for card description (plain textarea is sufficient)
- Custom label names or user-defined label colors
- Board sharing or real-time collaboration (Phase 4+)
- Activity log or card history

## Requirements
- Clicking a card opens a card detail view without a full page reload (Turbo Frame)
- The card detail view displays and allows editing of: title, description, due date, and labels
- Each editable field saves independently (no single "Save All" button required, but it is acceptable)
- The card face (swimlane view) updates to reflect description presence, due date, and labels after saving — no page reload
- Labels are stored as a join table (`card_labels`) with a predefined color enum; no free-form label names in this phase
- Overdue cards (due date in the past) display a visual indicator on the card face
- All new functionality is authorization-scoped: users can only see/edit cards on boards they own
- Reorder bounds guard prevents `NoMethodError` on out-of-range position values
- DB-level card ordering (`.order(:position)`) replaces Ruby-level `sort_by` in the swimlane partial
- Turbo Frame IDs for card detail frames must be globally unique per page (scoped to card, not just swimlane)

## Acceptance Criteria
- [ ] Clicking a card in the board view opens the card detail view (modal or slide-over) via Turbo Frame — no full page reload
- [ ] A user can type and save a card description from the detail view; the card face shows a description indicator when one exists
- [ ] A user can set a due date on a card; the date appears on the card face; a card with a past due date shows an overdue indicator
- [ ] A user can add and remove color-coded labels on a card from the detail view; labels appear as color chips on the card face
- [ ] Swimlane inline-edit cancel link returns to the swimlane view without loading the full board page into the frame
- [ ] Creating a new swimlane appends it before the "Add Lane" button (correct visual order)
- [ ] Sending `position: 9999` to the cards reorder endpoint returns a valid response (no 500 / NoMethodError)
- [ ] E2E drag test uses Playwright `dragAndDrop()` (or `mouse` API) on real DOM elements, not a fetch stub
- [ ] Cards within a swimlane are ordered by `position` at the DB level — no Ruby-side `sort_by` in views
- [ ] A user cannot access card detail for a card on another user's board (returns 404 or redirect)
- [ ] All existing tests continue to pass
- [ ] SimpleCov coverage remains at or above 80%
- [ ] All tests pass

## Testing Strategy
- **Minitest** for unit and integration tests (existing framework)
  - Unit: Label model (enum values, validations), Card model (due date scopes: overdue, upcoming)
  - Integration: Card detail show/update for description, due date, labels — happy path and auth boundary
  - Integration: Cards reorder with out-of-bounds position value (negative input test)
  - Integration: Swimlane create verifies new lane appears before "Add Lane" button in Turbo Stream response
  - Integration: Swimlane header edit/cancel round-trip via Turbo Frame (cancel returns to display state)
- **Playwright E2E** (existing framework)
  - E2E: Open card detail, add description, verify card face updates
  - E2E: Set due date, verify badge on card face; set past due date, verify overdue style
  - E2E: Add a label, verify chip on card face; remove label, verify chip disappears
  - E2E: Drag a card to a new position using `page.dragAndDrop()` — replaces the existing fetch stub
- **Plan-level Turbo Frame audit**: before implementation begins, list all Turbo Frame IDs that will exist on the board page and verify uniqueness (card detail frames must be scoped, e.g., `card_1`, not just `detail`)
- **Manual smoke test checklist** (to run before committing each UI feature):
  - Create a new swimlane → verify it appears before "Add Lane" button
  - Click card → detail view opens without reload
  - Cancel swimlane edit → returns to display state (not full page)

## Documentation Updates
- **AGENTS.md**: Add Label model to the data model section; document the card detail route (nested under boards/swimlanes or a top-level cards/:id path — whichever is chosen); note the predefined label color enum values
- **README.md**: Update the feature list to include card descriptions, due dates, and labels; add a screenshot or description of the card detail view

## Dependencies
- Phase 1 (auth, boards) and Phase 2 (swimlanes, cards, drag-and-drop) must be complete and passing
- No new external libraries required — SortableJS (drag), Hotwire (Turbo + Stimulus), and Tailwind CSS already present
- No new services or environment variables required

## Adjustments from Previous Phase

Based on Phase 2 reflections:

1. **Fix bugs before features**: The five carry-over items are the first tasks in the plan, not deferred cleanup. They are acceptance criteria, not nice-to-haves.
2. **Turbo Frame IDs verified in the plan**: The plan step for card detail will explicitly list the frame IDs and confirm no collisions before implementation.
3. **Negative-input tests are mandatory**: The reorder bounds fix must be accompanied by an integration test sending `position: 9999`. This is not optional.
4. **E2E tests must use real DOM interactions**: The drag test stub is replaced. New E2E tests for card detail must click/type in the UI — no raw API calls.
5. **Manual smoke test before committing UI work**: The append-order bug was a one-second visual check. The plan will include a reminder to smoke-test each new-item flow before committing.
6. **Ruby `sort_by` anti-pattern eliminated at the association level**: Fix goes in the `Swimlane` model's `has_many :cards` with `-> { order(:position) }`, not just the partial.
