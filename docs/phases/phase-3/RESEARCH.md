# Research: Phase 3

## Phase Context

Phase 3 adds rich card detail to the existing Trello-like board. Five carry-over bugs from Phase 2 are fixed first (Ruby `sort_by` replaced by DB-level ordering, `turbo_frame_tag` wrapper on swimlane header, reorder bounds guard, new-swimlane append order, and E2E drag stub replaced with real DOM interaction). New features then layer on top: clicking a card title opens a detail view (Turbo Frame) where users can edit description (plain textarea), set a due date (date input), and toggle color-coded labels (predefined enum join table). Changes are reflected on the card face via Turbo Streams without a page reload. All new actions are authorization-scoped through the existing `Current.user.boards.find` chain.

---

## Previous Phase Learnings

From `docs/phases/phase-2/REFLECTIONS.md`:

- **`sort_by(&:position)` anti-pattern**: `app/views/swimlanes/_swimlane.html.erb:21` sorts cards in Ruby after an eager load, bypassing DB ordering. Fix goes on the `Swimlane` model's `has_many :cards` with `-> { order(:position) }`, not just the partial.
- **Reorder bounds guard deferred**: `app/controllers/cards_controller.rb` `reorder` action is missing `clamp` on out-of-bound positions; already fixed in the current code (line 71 shows the clamp), but a negative-input integration test must accompany it (the test file `cards_reorder_test.rb` already includes `test "clamps out-of-bounds position to last"`).
- **Swimlane header `<div>` vs `turbo_frame_tag`**: the header partial and the swimlane partial both now use `turbo_frame_tag dom_id(swimlane, :header)` — this was fixed before this research snapshot.
- **New-swimlane append order**: `create.turbo_stream.erb` uses `turbo_stream.append "swimlanes"` which places new lanes after the "Add Lane" div (which lives outside `#swimlanes` — see below). May actually be correct; see Open Questions.
- **E2E drag tests use `page.evaluate` fetch stub**: `e2e/board_canvas.spec.js` lines 8–33. Must be replaced with Playwright `dragAndDrop()`.
- **Turbo Frame ID uniqueness**: frame IDs must be globally unique per page. Card detail frames must be scoped (e.g., `card_1` via `dom_id(card)`) not generic.
- **Authorization**: `Current.user.boards.find()` pattern consistently produced correct 404s across swimlanes and cards in Phase 2.
- **SimpleCov floor**: 85.59% at Phase 2 close; floor is 80%.

---

## Current Codebase State

### Models

- **`Card`** — `app/models/card.rb:1`
  - Columns: `id`, `name` (string, not null), `position` (integer, default 0, not null), `swimlane_id` (FK), `created_at`, `updated_at`
  - `belongs_to :swimlane`
  - `validates :name, presence: true` with `before_validation { name&.strip! }`
  - `before_create :set_position` — sets `position` to `max(position) + 1` within the swimlane
  - **No** `description`, `due_date`, or label associations yet — these are Phase 3 additions

- **`Swimlane`** — `app/models/swimlane.rb:1`
  - Columns: `id`, `name` (string, not null), `position` (integer, default 0, not null), `board_id` (FK), `created_at`, `updated_at`
  - `belongs_to :board`
  - `has_many :cards, dependent: :destroy` — **no default scope**; this is the source of the `sort_by` anti-pattern
  - `before_create :set_position` — same max+1 pattern

- **`Board`** — `app/models/board.rb:1`
  - Columns: `id`, `name` (string, not null), `user_id` (FK), `created_at`, `updated_at`
  - `belongs_to :user`
  - `has_many :swimlanes, dependent: :destroy` — no explicit order scope
  - No labels or card detail associations

- **`User`** — `app/models/user.rb`
  - `has_many :boards, dependent: :destroy`
  - `has_many :sessions, dependent: :destroy`

- **`Current`** — `app/models/current.rb` — thread-local `Current.user` and `Current.session` via `ActiveSupport::CurrentAttributes`

### Controllers

- **`CardsController`** — `app/controllers/cards_controller.rb:1`
  - Actions: `create`, `edit`, `update`, `destroy`, `reorder`
  - `before_action :set_board` — `Current.user.boards.find(params[:board_id])` (line 84)
  - `before_action :set_swimlane` — `@board.swimlanes.find(params[:swimlane_id])` (line 88)
  - `before_action :set_card, only: [:edit, :update, :destroy]` — `@swimlane.cards.find(params[:id])` (line 92)
  - `card_params` permits only `[:name]` (line 96) — **needs expansion** for description, due_date, and labels
  - `reorder` action (lines 60–79): finds card, verifies ownership via joins query, clamps position (line 71: `[[target_position, 0].max, cards.length].min`), moves card, rebuilds positions

- **`SwimlanesController`** — `app/controllers/swimlanes_controller.rb:1`
  - Actions: `create`, `header`, `edit`, `update`, `destroy`
  - `header` action (line 22): renders `swimlanes/header` partial — used by the cancel link in `_edit_form.html.erb`
  - `before_action :set_board` — same `Current.user.boards.find` pattern
  - `swimlane_params` permits only `[:name]`

- **`BoardsController`** — `app/controllers/boards_controller.rb:1`
  - `show` action (line 9): `@swimlanes = @board.swimlanes.order(:position).includes(:cards)` — eager-loads cards, but `includes(:cards)` loads them **without order**, causing the `sort_by` in the partial

- **`ApplicationController`** — `app/controllers/application_controller.rb`
  - Includes `Authentication` concern, which sets `before_action :require_authentication`

### Routes

`config/routes.rb:1`:
```
boards → swimlanes (only: create, edit, update, destroy + member: header)
                  → cards (only: create, edit, update, destroy + collection: reorder)
```

- No `show` action on `cards` — **Phase 3 adds this** for the card detail view
- Route for card detail will likely be `GET /boards/:board_id/swimlanes/:swimlane_id/cards/:id` (`cards#show`) or a top-level `GET /cards/:id`

### Views

**Swimlane partial** — `app/views/swimlanes/_swimlane.html.erb:1`
- Outer div: `id="<%= dom_id(swimlane) %>"` (e.g. `swimlane_1`)
- Header section: wrapped in `turbo_frame_tag dom_id(swimlane, :header)` (line 2) — this is the fixed version; cancel link in edit form targets this same frame ID
- Cards container: `id="<%= dom_id(swimlane, :cards) %>"` (line 16), `data-controller="sortable"`, `data-sortable-url-value`
- Card collection rendered via: `swimlane.cards.sort_by(&:position)` (line 21) — **this is the Ruby-sort anti-pattern still present**
- New card form: wrapped in `turbo_frame_tag dom_id(swimlane, :new_card_form)` (line 24)

**Swimlane header partial** — `app/views/swimlanes/_header.html.erb:1`
- Renders inside a `turbo_frame_tag dom_id(swimlane, :header)` wrapper
- Contains Rename link (targets `dom_id(swimlane, :header)` frame) and Delete button

**Swimlane edit form** — `app/views/swimlanes/_edit_form.html.erb:1`
- Contains Cancel link pointing to `header_board_swimlane_path(board, swimlane)` with `data: { turbo_frame: dom_id(swimlane, :header) }` — fetches the header partial into the frame

**Card partial** — `app/views/cards/_card.html.erb:1`
- Outer div: `id="<%= dom_id(card) %>"` (e.g. `card_1`), carries `data-card-id` and `data-swimlane-id`
- Renders `cards/card_name` partial — **Phase 3 needs to add description indicator, due date badge, and label chips here**

**Card name partial** — `app/views/cards/_card_name.html.erb:1`
- Wrapped in `turbo_frame_tag dom_id(card, :name)` (e.g. `card_1_name`)
- Shows card name, edit (✎) link (targets `card_N_name` frame), delete button
- Edit link targets `edit_board_swimlane_card_path` — **Phase 3 needs a separate detail link targeting a new frame ID**

**Card edit form** — `app/views/cards/_edit_form.html.erb:1`
- Wrapped in `turbo_frame_tag dom_id(card, :name)` — replaces the name display in-place

**Swimlane create stream** — `app/views/swimlanes/create.turbo_stream.erb:1`
- `turbo_stream.append "swimlanes"` — appends to `<div id="swimlanes">` in `boards/show`
- The "Add Lane" form is in a separate `<div class="flex-shrink-0 w-64">` outside `#swimlanes` — so `append` does put new lanes before the "Add Lane" div. **This may already be correct.**

**Board show** — `app/views/boards/show.html.erb:1`
- `<div id="swimlanes">` wraps the swimlane collection (line 11)
- "Add Lane" form is in a sibling div outside `#swimlanes` (line 15) — new swimlanes append inside `#swimlanes`, which is before the sibling

### Turbo Frame ID Inventory (Current)

| Frame ID | Location | Scope |
|---|---|---|
| `swimlane_N_header` | `_swimlane.html.erb` line 2, `_header.html.erb` line 1 | Per swimlane |
| `swimlane_N_new_card_form` | `_swimlane.html.erb` line 24, `_new_form.html.erb` line 1 | Per swimlane |
| `card_N_name` | `_card_name.html.erb` line 1, `_edit_form.html.erb` line 1 | Per card |
| `new_swimlane_form` | `boards/show.html.erb` line 16, `create.turbo_stream.erb` line 2 | Global (unique — only one at a time) |

**Phase 3 adds**: `card_N` or `card_N_detail` for the card detail panel.

### JavaScript

**`sortable_controller.js`** — `app/javascript/controllers/sortable_controller.js:1`
- `values: { url: String, swimlaneId: Number }` (lines 6–8)
- On `onEnd`: reads `event.item.dataset.cardId`, `event.newIndex`, fetches the destination container's URL, sends `PATCH /boards/:board_id/swimlanes/:swimlane_id/cards/reorder` with JSON body
- On error: reverts card to original DOM position

### Test Infrastructure

**Framework**: Minitest + SimpleCov (configured in `test/test_helper.rb:1`)
- SimpleCov starts with `"rails"` profile, filters `/test/`, minimum coverage 80%
- `parallelize(workers: 1)` — single-threaded test execution
- Fixtures: `test/fixtures/{boards,cards,swimlanes,sessions,users}.yml` — minimal fixtures (two rows each)

**Session helper** — `test/test_helpers/session_test_helper.rb:1`
- `sign_in_as(user)` — creates a session record, sets signed cookie
- `sign_out` — destroys session, deletes cookie
- Auto-included in `ActionDispatch::IntegrationTest`

**Integration tests**:
- `test/integration/authentication_flow_test.rb` — auth flows
- `test/integration/boards_flow_test.rb` — board CRUD + auth boundary
- `test/integration/swimlanes_flow_test.rb` — swimlane CRUD, header, auth boundary, turbo stream
- `test/integration/cards_flow_test.rb` — card CRUD, auth boundary, turbo stream
- `test/integration/cards_reorder_test.rb` — reorder within/across lanes, out-of-bounds clamp (test exists at line 43), auth boundary, unauthenticated redirect

**Model tests**:
- `test/models/card_test.rb` — validity, position auto-assignment, swimlane scoping
- `test/models/swimlane_test.rb` — basic validations
- `test/models/board_test.rb` — basic validations
- `test/models/user_test.rb` — basic validations

**E2E tests** — Playwright (`e2e/`):
- `e2e/auth.spec.js` — sign up, sign in, sign out
- `e2e/boards.spec.js` — board CRUD
- `e2e/board_canvas.spec.js` — swimlane/card CRUD + drag reorder (uses fetch stub, not DOM drag)
- `e2e/helpers/auth.js` — shared `signUp`, `uniqueEmail`, `createBoard`, `PASSWORD` exports

### Dependencies & Integration Points

- **Hotwire Turbo**: `turbo-rails` gem — drives Turbo Frame and Turbo Stream responses
- **Stimulus**: `stimulus-rails` gem — `sortable_controller.js` is the only custom controller
- **SortableJS**: pinned via importmap at `https://cdn.jsdelivr.net/npm/sortablejs@1.15.6/Sortable.min.js`; imported in `sortable_controller.js`
- **Tailwind CSS**: `tailwindcss-rails` standalone binary; classes used inline in all views
- **SQLite**: development and test database
- **SimpleCov**: enforces ≥80% coverage at test end
- **Playwright**: E2E tests; `playwright.config.js` auto-starts a Rails test server

### Schema State (Before Phase 3)

```
users:     id, email_address, password_digest, created_at, updated_at
sessions:  id, user_id, user_agent, ip_address, created_at, updated_at
boards:    id, user_id, name, created_at, updated_at
swimlanes: id, board_id, name, position, created_at, updated_at
cards:     id, swimlane_id, name, position, created_at, updated_at
```

Phase 3 will add:
- `cards.description` (text, nullable)
- `cards.due_date` (date, nullable)
- New `labels` table (id, color enum)
- New `card_labels` join table (card_id, label_id)

---

## Code References

- `app/models/card.rb:1` — Card model; no description/due_date/labels yet
- `app/models/swimlane.rb:3` — `has_many :cards, dependent: :destroy` — missing `-> { order(:position) }` scope
- `app/controllers/boards_controller.rb:9` — `includes(:cards)` without order; feeds the `sort_by` anti-pattern
- `app/controllers/cards_controller.rb:60` — `reorder` action with clamp already in place (line 71)
- `app/controllers/cards_controller.rb:96` — `card_params` permits only `[:name]`; needs `:description`, `:due_date`
- `app/views/swimlanes/_swimlane.html.erb:21` — `sort_by(&:position)` Ruby sort anti-pattern
- `app/views/swimlanes/_swimlane.html.erb:2` — `turbo_frame_tag dom_id(swimlane, :header)` — already fixed
- `app/views/swimlanes/create.turbo_stream.erb:1` — `append "swimlanes"` — "Add Lane" div is outside `#swimlanes`, so append order appears correct
- `app/views/cards/_card.html.erb:1` — card face; will need description indicator, due date badge, label chips added
- `app/views/cards/_card_name.html.erb:1` — `turbo_frame_tag dom_id(card, :name)` — inline edit frame; detail link goes here or alongside
- `app/views/boards/show.html.erb:11` — `<div id="swimlanes">` container and sibling "Add Lane" div (line 15)
- `app/javascript/controllers/sortable_controller.js:1` — SortableJS Stimulus controller
- `e2e/board_canvas.spec.js:8` — `reorderCard` fetch stub function; to be replaced with DOM drag
- `test/integration/cards_reorder_test.rb:43` — out-of-bounds clamp test already exists
- `test/test_helpers/session_test_helper.rb:1` — `sign_in_as` / `sign_out` helpers used in all integration tests

---

## Open Questions

1. **Card detail route placement**: Should `cards#show` be nested under boards/swimlanes (`/boards/:board_id/swimlanes/:swimlane_id/cards/:id`) or top-level (`/cards/:id`)? A top-level route simplifies the URL but breaks the `Current.user.boards.find` authorization chain. A nested route keeps the chain intact at the cost of longer URLs.

2. **Append order for new swimlanes — is it actually broken?**: `boards/show.html.erb` places `<div id="swimlanes">` and the "Add Lane" form div as siblings, with `#swimlanes` first. `create.turbo_stream.erb` appends to `#swimlanes`. Visual inspection suggests new lanes appear before the "Add Lane" div — this may already be correct. Needs manual smoke test to confirm before treating it as a bug.

3. **Turbo Frame vs. modal for card detail**: The SPEC says "modal or slide-over." A Turbo Frame embedded in the board page avoids a full navigation but requires a frame target on every card. A `<dialog>`-based modal driven by a Turbo Frame offers better UX. The plan step needs to commit to one approach.

4. **Label storage**: The SPEC says a `card_labels` join table with a predefined color enum. The enum values (Red, Yellow, Green, Blue, Purple) need a canonical representation — string enum in the join table or a separate `labels` table with color as enum. Either approach works; the plan must choose one.

5. **`boards/show.html.erb` layout**: The outer `<main>` in `application.html.erb` uses `mt-8 px-5 flex` which may constrain the full-height board canvas. The board show uses `flex flex-col h-full` (line 1) — `h-full` only works if the parent chain has defined heights. This is pre-existing; the card detail overlay should not assume a specific viewport layout.
