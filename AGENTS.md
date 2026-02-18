# AGENTS.md

## Project: Swimlanes
A Trello-like board management app built with Rails 8, Hotwire (Turbo + Stimulus), Tailwind CSS, and SQLite.

## Prerequisites
- Ruby 3.4+ (Homebrew: `/usr/local/opt/ruby/bin/ruby`)
- Node.js 18+ and npm
- No Docker required

## Ruby PATH Note
The system Ruby (2.6.10) is too old for Rails 8. Always use the Homebrew Ruby 3.4:

```bash
export PATH="/usr/local/lib/ruby/gems/3.4.0/bin:/usr/local/opt/ruby/bin:$PATH"
```

## Install

```bash
export PATH="/usr/local/lib/ruby/gems/3.4.0/bin:/usr/local/opt/ruby/bin:$PATH"
bin/setup --skip-server   # installs gems, npm packages, prepares database
```

## Run

```bash
export PATH="/usr/local/lib/ruby/gems/3.4.0/bin:/usr/local/opt/ruby/bin:$PATH"
bin/rails server
```

Visit: http://localhost:3000

## Test

```bash
# Unit + integration tests with SimpleCov coverage
export PATH="/usr/local/lib/ruby/gems/3.4.0/bin:/usr/local/opt/ruby/bin:$PATH"
bin/rails test

# Coverage report (auto-generated after bin/rails test)
open coverage/index.html

# End-to-end tests (auto-starts a Rails test server)
npx playwright test
```

## Project Structure

```
app/
  controllers/     # ApplicationController, BoardsController, SwimlanesController,
                   # CardsController, RegistrationsController, SessionsController, PasswordsController
  models/          # User, Board, Swimlane, Card, Session, Current
  views/           # boards/, swimlanes/, cards/, sessions/, registrations/, passwords/, layouts/
  javascript/
    controllers/   # sortable_controller.js (SortableJS drag-and-drop)
config/
  routes.rb        # Nested routes: boards → swimlanes → cards
  importmap.rb     # SortableJS pinned via CDN
db/
  schema.rb        # Current DB schema (users, sessions, boards, swimlanes, cards)
test/
  models/          # User, Board, Swimlane, Card unit tests
  controllers/     # Sessions, Passwords controller tests
  integration/     # Auth flow, Boards, Swimlanes, Cards CRUD + reorder integration tests
  test_helpers/    # SessionTestHelper for signing in during tests
e2e/               # Playwright end-to-end tests
  helpers/         # auth.js shared helpers (signUp, uniqueEmail, createBoard, PASSWORD)
  auth.spec.js
  boards.spec.js
  board_canvas.spec.js
docs/phases/       # Phase specs, research, plans, reflections
```

## Nested Route Structure (Phase 2)

Swimlane and card routes are nested under boards:

```
/boards/:board_id/swimlanes                       → swimlanes#create
/boards/:board_id/swimlanes/:id                   → swimlanes#update, #destroy
/boards/:board_id/swimlanes/:id/edit              → swimlanes#edit
/boards/:board_id/swimlanes/:swimlane_id/cards    → cards#create
/boards/:board_id/swimlanes/:swimlane_id/cards/reorder  → cards#reorder (PATCH)
/boards/:board_id/swimlanes/:swimlane_id/cards/:id      → cards#update, #destroy
/boards/:board_id/swimlanes/:swimlane_id/cards/:id/edit → cards#edit
```

## Authorization Chain (Phase 2)

All swimlane/card actions scope through the current user's boards:

```ruby
@board = Current.user.boards.find(params[:board_id])      # raises 404 for wrong user
@swimlane = @board.swimlanes.find(params[:swimlane_id])   # raises 404 if not under board
@card = @swimlane.cards.find(params[:id])                 # raises 404 if not under swimlane
```

## SortableJS Drag-and-Drop (Phase 2)

- Pinned via importmap: `pin "sortablejs", to: "https://cdn.jsdelivr.net/npm/sortablejs@1.15.6/Sortable.min.js"`
- Stimulus controller: `app/javascript/controllers/sortable_controller.js`
- Each swimlane's card container has `data-controller="sortable"` and `data-sortable-url-value`
- `group: "cards"` enables cross-lane drag-and-drop

### Position Update Pattern

After a drag, the Stimulus controller sends:

```
PATCH /boards/:board_id/swimlanes/:destination_swimlane_id/cards/reorder
Content-Type: application/json
{ card_id: X, position: Y }
```

The `reorder` action moves the card to the destination swimlane and rebuilds all positions in that lane.

## Phase Roadmap
- Phase 1 ✓ — Setup, auth, board CRUD
- Phase 2 ✓ — Swimlanes (columns) and cards
- Phase 3: Card details (descriptions, due dates, labels, checklists)
- Phase 4: Board sharing between users
- Phase 5: Real-time updates (ActionCable)
- Phase 6: Board background customization

## Key Decisions
- Authentication: Rails 8 built-in (`rails generate authentication`) — no Devise
- CSS: Tailwind via `tailwindcss-rails` standalone binary — no webpack/esbuild
- JS: Importmap + Hotwire (Turbo + Stimulus) — no bundler
- Database: SQLite for local development
- Testing: Minitest + SimpleCov (≥80% coverage) + Playwright for E2E
