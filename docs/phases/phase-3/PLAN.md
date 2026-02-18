# Implementation Plan: Phase 3

## Overview

Phase 3 enriches cards with a detail view (description, due date, color-coded labels) surfaced via a Turbo Frame–driven `<dialog>` modal, and first closes five pieces of technical debt from Phase 2 before any new features land.

## Current State (from Research)

- **`Card`** has only `name` and `position`; no description, due_date, or label associations
- **`Swimlane#has_many :cards`** has no default order scope → the partial uses Ruby `sort_by(&:position)` anti-pattern (line 21 of `_swimlane.html.erb`)
- **`CardsController#card_params`** permits only `:name`
- No `cards#show` route or action exists
- The `reorder` action already has the `clamp` guard (line 71) but the negative-input integration test still needs to be confirmed/run
- Swimlane header is already wrapped in `turbo_frame_tag dom_id(swimlane, :header)` — this carry-over bug is already fixed
- New-swimlane append order is confirmed correct — `#swimlanes` and the "Add Lane" div are siblings; `append "swimlanes"` inserts before the "Add Lane" div
- E2E drag test in `e2e/board_canvas.spec.js` uses a `page.evaluate` fetch stub (lines 8–33)
- Existing Turbo Frame IDs: `swimlane_N_header`, `swimlane_N_new_card_form`, `card_N_name`, `new_swimlane_form`

## Desired End State

After this phase:

- `Card` model has `description` (text, nullable) and `due_date` (date, nullable)
- A `labels` table exists with a color enum (red, yellow, green, blue, purple); a `card_labels` join table links cards to labels
- `cards#show` renders a card detail modal via Turbo Frame at `/boards/:board_id/swimlanes/:swimlane_id/cards/:id`
- Card face shows: description indicator (icon/dot when description present), due date badge (overdue badge in red when past due), label color chips
- Swimlane partial uses DB-level ordering via association scope (no Ruby `sort_by`)
- E2E drag test uses Playwright `dragAndDrop()` on real DOM elements
- All existing + new tests pass; SimpleCov ≥ 80%

**Verification**: Run `bin/rails test`, check SimpleCov output ≥ 80%; run `npx playwright test`; manually open the board, click a card, edit description/due date/label, confirm card face updates without page reload.

## What We're NOT Doing

- Checklists / checklist items (Phase 4)
- Card file attachments or image uploads
- Rich-text / WYSIWYG description (plain textarea only)
- Custom user-defined label names or colors
- Board sharing or real-time collaboration
- Activity log or card history
- Swimlane-level ordering fix (board already uses `.order(:position)` for swimlanes)
- Fixing the new-swimlane append order (confirmed not broken — it's already correct)

## Turbo Frame ID Audit (Phase 3 additions)

| Frame ID | Location | Unique? |
|---|---|---|
| `swimlane_N_header` | existing | ✓ per swimlane |
| `swimlane_N_new_card_form` | existing | ✓ per swimlane |
| `card_N_name` | existing | ✓ per card |
| `new_swimlane_form` | existing | ✓ global |
| `card_N_detail` | **new** — card detail modal frame | ✓ per card (uses `dom_id(card, :detail)`) |

No collisions. `card_N_detail` is scoped per card via `dom_id`.

## Implementation Approach

**Debt-first**: Tasks 1–2 close carry-over bugs and establish the DB-level ordering foundation. No new features until these are done.

**Feature tasks 3–7** follow a vertical-slice pattern — each delivers a testable behavior end-to-end (model → controller → view → test).

**Label storage**: A `labels` table (seeded with 5 colors) + `card_labels` join table. Labels are accessed as `card.labels` via `has_many :through`. The label color is a string enum on the `Label` model.

**Card detail modal**: A `<dialog>` element rendered inside a Turbo Frame (`card_N_detail`). The card title link triggers a Turbo Frame navigation to `cards#show`, which renders the dialog partial. No custom Stimulus controller needed — the dialog is shown via CSS `open` attribute set by Turbo's frame load.

**Authorization**: All new controller actions go through the existing `set_board` / `set_swimlane` / `set_card` chain. Label toggle will go through `cards#show` and a new `cards#update_labels` or inline within `cards#update` with label IDs param.

---

## Task 1: Fix Ruby `sort_by` Anti-Pattern — DB-Level Card Ordering

### Overview

Add `-> { order(:position) }` scope to `Swimlane#has_many :cards` and update `BoardsController#show` to use `.includes(:cards)` with the association order respected. Remove `sort_by(&:position)` from the swimlane partial.

### Changes Required

**File**: `app/models/swimlane.rb`
```ruby
has_many :cards, -> { order(:position) }, dependent: :destroy
```

**File**: `app/controllers/boards_controller.rb` (line 9)
- The `includes(:cards)` call will now respect the association scope order since Rails 6+. No additional change needed beyond the model scope — but verify with a test.

**File**: `app/views/swimlanes/_swimlane.html.erb` (line 21)
```erb
# Change:
collection: swimlane.cards.sort_by(&:position)
# To:
collection: swimlane.cards
```

### Success Criteria
- [ ] `swimlane.cards` returns cards in position order without Ruby sorting
- [ ] `bin/rails test` passes (existing card model tests verify ordering behavior)
- [ ] Board page renders cards in correct position order

---

## Task 2: Replace E2E Drag Fetch Stub with Real DOM Interaction

### Overview

Replace the `reorderCard` function in `e2e/board_canvas.spec.js` (lines 8–33) that issues a raw `fetch` PATCH with Playwright's `dragAndDrop()` API to test the actual SortableJS + Stimulus controller integration.

### Changes Required

**File**: `e2e/board_canvas.spec.js`

Remove the `reorderCard` helper and the drag reorder test that calls it. Replace with a test that:
1. Creates a board with a swimlane and two cards
2. Uses `page.dragAndDrop(sourceSelector, targetSelector)` to drag card B above card A
3. Verifies the DOM order has changed (card B appears before card A)

Key selectors:
- Cards are `div[data-card-id="N"]` or `#card_N`
- The SortableJS container is `div[data-controller="sortable"]` scoped to the swimlane

Example approach:
```js
const cards = await page.locator('[data-card-id]').all()
// drag second card above first
await page.dragAndDrop(`#card_${card2Id}`, `#card_${card1Id}`)
// verify order
```

### Success Criteria
- [ ] `npx playwright test e2e/board_canvas.spec.js` passes using DOM drag (no fetch stubs)
- [ ] The test actually exercises the Stimulus controller and SortableJS event

---

## Task 3: Add `description` and `due_date` to Card Model

### Overview

Migration, model update, controller params expansion, and basic unit tests for the new `Card` columns.

### Changes Required

**Migration**: `db/migrate/TIMESTAMP_add_details_to_cards.rb`
```ruby
def change
  add_column :cards, :description, :text
  add_column :cards, :due_date, :date
end
```

**File**: `app/models/card.rb`
Add scopes:
```ruby
scope :overdue, -> { where("due_date < ?", Date.current).where.not(due_date: nil) }
scope :upcoming, -> { where("due_date >= ?", Date.current).where.not(due_date: nil) }

def overdue?
  due_date.present? && due_date < Date.current
end
```

**File**: `app/controllers/cards_controller.rb` (line 96)
```ruby
def card_params
  params.require(:card).permit(:name, :description, :due_date)
end
```

**File**: `test/models/card_test.rb`
Add tests:
- `test "overdue? returns true when due date is in the past"`
- `test "overdue? returns false when due date is today or future"`
- `test "overdue? returns false when due date is nil"`
- `test "overdue scope returns only past-due cards"`

### Success Criteria
- [ ] Migration runs cleanly: `bin/rails db:migrate`
- [ ] `Card.new(description: "hello", due_date: Date.tomorrow)` saves without error
- [ ] `bin/rails test test/models/card_test.rb` passes with new scope tests

---

## Task 4: Add Label Model and `card_labels` Join Table

### Overview

Create `Label` model with a color string enum (seeded with 5 values) and `CardLabel` join model. Wire `Card has_many :labels through card_labels`.

### Changes Required

**Migration 1**: `db/migrate/TIMESTAMP_create_labels.rb`
```ruby
def change
  create_table :labels do |t|
    t.string :color, null: false
    t.timestamps
  end
  add_index :labels, :color, unique: true
end
```

**Migration 2**: `db/migrate/TIMESTAMP_create_card_labels.rb`
```ruby
def change
  create_table :card_labels do |t|
    t.references :card, null: false, foreign_key: true
    t.references :label, null: false, foreign_key: true
    t.timestamps
  end
  add_index :card_labels, [:card_id, :label_id], unique: true
end
```

**File**: `app/models/label.rb`
```ruby
class Label < ApplicationRecord
  COLORS = %w[red yellow green blue purple].freeze
  validates :color, inclusion: { in: COLORS }, uniqueness: true
  has_many :card_labels, dependent: :destroy
  has_many :cards, through: :card_labels
end
```

**File**: `app/models/card_label.rb`
```ruby
class CardLabel < ApplicationRecord
  belongs_to :card
  belongs_to :label
end
```

**File**: `app/models/card.rb` — add associations:
```ruby
has_many :card_labels, dependent: :destroy
has_many :labels, through: :card_labels
```

**File**: `db/seeds.rb`
```ruby
Label::COLORS.each { |color| Label.find_or_create_by!(color: color) }
```

**File**: `test/fixtures/labels.yml`
```yaml
red:
  color: red
yellow:
  color: yellow
green:
  color: green
blue:
  color: blue
purple:
  color: purple
```

**File**: `test/models/label_test.rb` (new)
- `test "valid with known color"`
- `test "invalid with unknown color"`
- `test "color must be unique"`

### Success Criteria
- [ ] `bin/rails db:migrate db:seed` completes cleanly
- [ ] `Label.count` returns 5 after seed
- [ ] `card.labels << Label.find_by(color: "red")` saves without error
- [ ] `bin/rails test test/models/label_test.rb` passes

---

## Task 5: Card Detail Route, Controller Action, and Modal View

### Overview

Add `cards#show` nested route and action. Render a `<dialog>` partial inside a Turbo Frame (`card_N_detail`). The card title on the card face becomes a Turbo Frame link that loads the detail modal.

### Changes Required

**File**: `config/routes.rb`
```ruby
resources :cards, only: [:create, :edit, :update, :destroy, :show] do
```
(add `:show` to the only list)

**File**: `app/controllers/cards_controller.rb`
Add `show` to `set_card` before_action:
```ruby
before_action :set_card, only: [:show, :edit, :update, :destroy]
```

Add action:
```ruby
def show
  @labels = Label.all.order(:color)
end
```

**File**: `app/views/cards/show.html.erb` (new)
```erb
<%= turbo_frame_tag dom_id(@card, :detail) do %>
  <dialog open class="...modal styles...">
    <div class="modal-content">
      ...render card detail partial...
    </div>
  </dialog>
<% end %>
```

**File**: `app/views/cards/_detail.html.erb` (new)
- Card title (editable inline, targeting `card_N_name` frame — reuse existing edit flow)
- Description textarea form (targets `cards#update`, turbo stream response)
- Due date input form (targets `cards#update`, turbo stream response)
- Label toggle buttons (targets `cards#update` with `label_ids`, turbo stream response)
- Close button (`<a>` or `<button>` that navigates Turbo Frame back or removes the dialog)

**File**: `app/views/cards/_card.html.erb`
Add Turbo Frame wrapper for card face that includes a detail link:
```erb
<%= turbo_frame_tag dom_id(card, :detail) do %>
  <%# empty frame on board page - gets filled when detail link is clicked %>
<% end %>
```
Add clickable title link (inside the existing card face):
```erb
<%= link_to card.name, board_swimlane_card_path(board, swimlane, card),
    data: { turbo_frame: dom_id(card, :detail) } %>
```

**File**: `app/views/cards/update.turbo_stream.erb` (update existing)
Add streams to update the card face when description/due_date/labels change:
```erb
<%= turbo_stream.replace dom_id(@card) do %>
  <%= render "cards/card", card: @card, board: @board, swimlane: @swimlane %>
<% end %>
```

**File**: `test/integration/cards_flow_test.rb`
Add:
- `test "show card detail — authenticated"` — GET card show, asserts 200 and detail content
- `test "show card detail — wrong user gets 404"` — cross-user card show returns 404

### Success Criteria
- [ ] `GET /boards/:id/swimlanes/:id/cards/:id` returns 200 for the card owner
- [ ] Cross-user access returns 404
- [ ] Clicking the card title on the board opens the detail modal (Turbo Frame navigation)
- [ ] `bin/rails test test/integration/cards_flow_test.rb` passes

---

## Task 6: Description and Due Date Save from Detail View

### Overview

Wire the description textarea and due date input in the card detail view to save via `cards#update`. Update the card face via Turbo Stream to reflect changes without a page reload.

### Changes Required

**File**: `app/views/cards/_detail.html.erb`

Description form:
```erb
<%= form_with model: [@board, @swimlane, @card], data: { turbo_frame: "_top" } do |f| %>
  <%= f.text_area :description, rows: 4, class: "..." %>
  <%= f.submit "Save", class: "..." %>
<% end %>
```

Due date form (can be separate form or combined with description):
```erb
<%= form_with model: [@board, @swimlane, @card] do |f| %>
  <%= f.date_field :due_date, class: "..." %>
  <%= f.submit "Save", class: "..." %>
<% end %>
```

**File**: `app/controllers/cards_controller.rb`
`card_params` already includes `:description` and `:due_date` from Task 3.
`update` action already has `format.turbo_stream` — the stream template handles the response.

**File**: `app/views/cards/update.turbo_stream.erb`
Add card face replacement stream:
```erb
<%= turbo_stream.replace dom_id(@card) do %>
  <%= render "cards/card", card: @card, board: @board, swimlane: @swimlane %>
<% end %>
```

**File**: `app/views/cards/_card.html.erb`
Add description indicator and due date badge:
```erb
<%# description indicator %>
<% if card.description.present? %>
  <span class="text-xs text-gray-400">≡</span>
<% end %>

<%# due date badge %>
<% if card.due_date.present? %>
  <span class="text-xs <%= card.overdue? ? 'bg-red-100 text-red-700' : 'bg-gray-100 text-gray-600' %> px-1 rounded">
    <%= card.due_date.strftime("%b %-d") %>
  </span>
<% end %>
```

**File**: `test/integration/cards_flow_test.rb`
Add:
- `test "update card description"` — PATCH with description param, assert turbo stream replaces card face
- `test "update card due date"` — PATCH with due_date, assert turbo stream response
- `test "update card with past due date — card face shows overdue indicator"` — assert response contains overdue CSS class

### Success Criteria
- [ ] Submitting description form saves to DB and Turbo Stream updates card face
- [ ] Submitting due date form saves to DB; past due cards show red badge on card face
- [ ] `bin/rails test test/integration/cards_flow_test.rb` passes

---

## Task 7: Label Toggle from Detail View

### Overview

Wire label toggle buttons in the card detail view to add/remove labels via `cards#update` with `label_ids[]` param. Card face updates to show color chips via Turbo Stream.

### Changes Required

**File**: `app/controllers/cards_controller.rb`
Expand `card_params`:
```ruby
def card_params
  params.require(:card).permit(:name, :description, :due_date, label_ids: [])
end
```

The `update` action handles `label_ids` automatically through the `has_many :through` association — Rails will add/remove `card_labels` records when `label_ids` is assigned.

**File**: `app/views/cards/_detail.html.erb`
Add label toggle section:
```erb
<%= form_with model: [@board, @swimlane, @card] do |f| %>
  <div class="flex gap-2 flex-wrap">
    <% @labels.each do |label| %>
      <%
        color_classes = {
          "red" => "bg-red-400", "yellow" => "bg-yellow-400",
          "green" => "bg-green-400", "blue" => "bg-blue-400", "purple" => "bg-purple-400"
        }
        checked = @card.labels.include?(label)
      %>
      <label class="flex items-center gap-1 cursor-pointer">
        <%= f.check_box :label_ids, { multiple: true, checked: checked }, label.id, false %>
        <span class="w-4 h-4 rounded <%= color_classes[label.color] %>"></span>
        <%= label.color.capitalize %>
      </label>
    <% end %>
  </div>
  <%= f.submit "Save Labels" %>
<% end %>
```

**File**: `app/views/cards/_card.html.erb`
Add label chips:
```erb
<% if card.labels.any? %>
  <div class="flex gap-1 flex-wrap mt-1">
    <% card.labels.each do |label| %>
      <span class="w-3 h-3 rounded-full bg-<%= label.color %>-400" title="<%= label.color %>"></span>
    <% end %>
  </div>
<% end %>
```

Note: Tailwind purge requires explicit class names — use inline style or a lookup hash for dynamic colors:
```erb
<%
  chip_colors = {
    "red" => "bg-red-400", "yellow" => "bg-yellow-400",
    "green" => "bg-green-400", "blue" => "bg-blue-400", "purple" => "bg-purple-400"
  }
%>
<span class="w-3 h-3 rounded-full <%= chip_colors[label.color] %>"></span>
```

**File**: `app/views/cards/update.turbo_stream.erb`
Already handles card face replacement from Task 6 — label chips will appear automatically.

**File**: `test/integration/cards_flow_test.rb`
Add:
- `test "add label to card"` — PATCH with `label_ids: [label.id]`, assert label associated
- `test "remove label from card"` — PATCH with `label_ids: []`, assert label disassociated
- `test "update card turbo stream replaces card face with label chips"` — assert response includes label color class

### Success Criteria
- [ ] Submitting label form adds/removes card_labels records
- [ ] Card face shows color chips for selected labels after Turbo Stream update
- [ ] `bin/rails test test/integration/cards_flow_test.rb` passes

---

## Task 8: E2E Tests for Card Detail

### Overview

Add Playwright E2E tests that interact through the UI: open card detail, save description, set due date, toggle labels, verify card face updates.

### Changes Required

**File**: `e2e/card_detail.spec.js` (new)

Tests to implement:
1. Open card detail modal (click card title, assert dialog opens)
2. Add description, save, assert card face shows description indicator
3. Set a future due date, assert date badge on card face
4. Set a past due date, assert overdue badge (red) on card face
5. Toggle a label on, assert color chip on card face; toggle off, assert chip gone

Shared setup: use `createBoard` helper from `e2e/helpers/auth.js`; add a `createSwimlane` and `createCard` helper if not already present.

```js
// e2e/helpers/board.js (new or extend existing auth.js helpers)
export async function createSwimlane(page, boardUrl, name) {
  await page.goto(boardUrl)
  await page.getByPlaceholder("Lane name").fill(name)
  await page.getByRole("button", { name: "Add Lane" }).click()
}

export async function createCard(page, laneName, cardName) {
  await page.getByPlaceholder("Card name").first().fill(cardName)
  await page.getByRole("button", { name: "Add Card" }).first().click()
}
```

### Success Criteria
- [ ] `npx playwright test e2e/card_detail.spec.js` passes
- [ ] All assertions use `page.getByRole`, `page.getByText`, `page.locator` — no raw `page.evaluate` fetch calls

---

## Task 9: Update AGENTS.md and README.md

### Overview

Document the new Label model, card detail route, and predefined color enum values as required by the SPEC.

### Changes Required

**File**: `AGENTS.md`
- Add `Label` to the data model section: color (string enum: red/yellow/green/blue/purple), `has_many :cards through card_labels`
- Add `CardLabel` join model
- Document `GET /boards/:board_id/swimlanes/:swimlane_id/cards/:id` as the card detail route
- Note that labels are seeded via `db/seeds.rb`
- Update card model docs: add `description`, `due_date`, `overdue?` method

**File**: `README.md`
- Update feature list to include: card descriptions, due dates with overdue indicator, color-coded labels
- Add brief description of card detail view UX (click card → dialog opens)

### Success Criteria
- [ ] AGENTS.md data model section reflects Label, CardLabel, and updated Card
- [ ] Card detail route is documented
- [ ] README feature list is accurate

---

## Testing Strategy

### Unit Tests (Minitest)
- **`test/models/card_test.rb`**: `overdue?` method, `overdue` scope, `upcoming` scope — use real date values
- **`test/models/label_test.rb`** (new): color enum validation, uniqueness, COLORS constant values
- No mocking — use real DB records via fixtures

### Integration Tests (Minitest)
- **`test/integration/cards_flow_test.rb`**: card show (auth boundary), description update (turbo stream), due date update (overdue class in response), label toggle (add/remove)
- **`test/integration/cards_reorder_test.rb`**: confirm existing out-of-bounds clamp test passes (this test already exists per RESEARCH.md line 157)
- Use `sign_in_as(users(:one))` pattern; assert `turbo_stream` content includes expected DOM IDs

### E2E Tests (Playwright)
- `e2e/board_canvas.spec.js`: drag reorder with `dragAndDrop()` — real DOM interaction
- `e2e/card_detail.spec.js` (new): full card detail flow — description, due date, labels
- All E2E tests interact through the UI (click, type, drag) — no raw fetch/API calls

### Anti-Mock Bias
- Use `Label.find_by(color: "red")` in tests (seeded or fixture data), not doubles
- Use `sign_in_as` cookie-based auth helper (real session creation)
- Mocking is NOT needed for any of these features

---

## Risk Assessment

- **Tailwind dynamic color classes purged at build**: Label chip colors use dynamic strings like `bg-red-400`. Tailwind's JIT/purge will strip these if not referenced statically. **Mitigation**: use a lookup hash in the partial that maps color → full class string (e.g., `{ "red" => "bg-red-400" }`), not string interpolation.
- **`label_ids: []` empty array not sent in form**: Browser doesn't submit unchecked checkboxes, so removing all labels requires a hidden field sentinel. **Mitigation**: Add `<%= hidden_field_tag "card[label_ids][]", "" %>` before the checkboxes so an empty array is always sent when no labels are checked.
- **`<dialog>` browser support**: Native `<dialog>` is well-supported in modern browsers but has no Turbo-specific open/close behavior. **Mitigation**: Use the `open` attribute to show the dialog; the close button navigates the frame back (or uses `data-action="click->modal#close"` if a simple Stimulus controller is needed). Start without Stimulus — a plain `<a>` targeting the frame with `src` set to blank may suffice.
- **N+1 on label loading**: `card.labels` in the card face partial will trigger a query per card if not eager-loaded. **Mitigation**: update `BoardsController#show` to `includes(cards: :labels)` so labels are batch-loaded.
- **`cards#update` Turbo Stream response needs `@board` and `@swimlane`**: The stream template renders the card face partial which needs `board` and `swimlane` locals. These are set by `before_action` so they'll be available — but verify `@board` and `@swimlane` are assigned before `update` runs (they are, via `set_board` and `set_swimlane`).
