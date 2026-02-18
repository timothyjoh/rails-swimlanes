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
  channels/        # ApplicationCable::Connection, BoardChannel
  controllers/     # ApplicationController, BoardsController, SwimlanesController,
                   # CardsController, MembershipsController, RegistrationsController,
                   # SessionsController, PasswordsController
  models/          # User, Board, BoardMembership, Swimlane, Card, Label, CardLabel, Session, Current
  views/           # boards/, swimlanes/, cards/, sessions/, registrations/, passwords/, layouts/
  javascript/
    controllers/   # sortable_controller.js (SortableJS drag-and-drop)
config/
  routes.rb        # Nested routes: boards → swimlanes → cards
  importmap.rb     # SortableJS pinned via CDN
db/
  schema.rb        # Current DB schema (users, sessions, boards, swimlanes, cards, labels, card_labels)
  seeds.rb         # Creates 5 predefined labels (run: bin/rails db:seed)
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
  realtime.spec.js
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
/boards/:board_id/swimlanes/:swimlane_id/cards/:id      → cards#show, #update, #destroy
/boards/:board_id/swimlanes/:swimlane_id/cards/:id/edit → cards#edit
```

## Authorization Chain (Phase 4 — membership-scoped)

All board/swimlane/card access is scoped via `Board.accessible_by(Current.user)`, which joins `board_memberships`. Edit and delete board are owner-only (checked via `BoardMembership` role=owner). Members can create/edit/delete swimlanes and cards.

```ruby
@board = Board.accessible_by(Current.user).find(params[:board_id])   # raises 404 for non-members
@swimlane = @board.swimlanes.find(params[:swimlane_id])               # raises 404 if not under board
@card = @swimlane.cards.find(params[:id])                             # raises 404 if not under swimlane
# Owner-only actions (edit/update/destroy board):
raise ActiveRecord::RecordNotFound unless BoardMembership.exists?(board: @board, user: Current.user, role: :owner)
```

## Data Models (Phase 3 additions)

- **Card** (updated): added `description` (text, nullable), `due_date` (date, nullable), `overdue?` method, `overdue` and `upcoming` scopes
- **Label**: `color` (string, one of: red/yellow/green/blue/purple), unique index on color. Seeded via `db/seeds.rb` — run `bin/rails db:seed` to create the 5 predefined labels
- **CardLabel**: join model between Card and Label (`card_id` FK, `label_id` FK, unique composite index)

## Data Models (Phase 4 additions)

- **BoardMembership**: join table connecting boards to users with a `role` enum
  - `board_id` (FK → boards), `user_id` (FK → users)
  - `role`: integer enum — `0=owner`, `1=member`
  - Unique index on `[board_id, user_id]` prevents duplicate memberships
  - When a board is created, an owner membership row is automatically created for the creating user
- **Board** (updated): `Board.accessible_by(user)` scope — returns boards where user has any membership
- **MembershipsController**: `POST /boards/:board_id/memberships` (add member by email, owner only), `DELETE /boards/:board_id/memberships/:id` (remove member, owner only)

### Card Detail Route

```
GET /boards/:board_id/swimlanes/:swimlane_id/cards/:id  → cards#show
```

Displays the card detail view with description, due date, and label management.

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

## ActionCable Real-time Updates (Phase 5)

- **Connection-level auth**: `ApplicationCable::Connection` reads the session cookie, looks up the authenticated user, and rejects unauthenticated connections
- **Channel-level auth**: `BoardChannel#subscribed` verifies the signed stream name (HMAC-based Global ID), checks `BoardMembership.exists?` for the current user, and rejects non-members
- **Broadcasts**: Live updates are triggered in controllers (`CardsController`, `SwimlanesController`) after each write operation using `Turbo::StreamsChannel.broadcast_*_to`
- **View integration**: `boards/show.html.erb` includes `turbo_stream_from @board, channel: BoardChannel` to subscribe the browser to real-time updates

## Phase Roadmap
- Phase 1 ✓ — Setup, auth, board CRUD
- Phase 2 ✓ — Swimlanes (columns) and cards
- Phase 3 ✓ — Card details (descriptions, due dates, labels, checklists)
- Phase 4 ✓ — Board sharing between users (BoardMembership, membership-scoped auth, sharing UI)
- Phase 5 ✓ — Real-time updates (ActionCable)
- Phase 6: Board background customization

## Key Decisions
- Authentication: Rails 8 built-in (`rails generate authentication`) — no Devise
- CSS: Tailwind via `tailwindcss-rails` standalone binary — no webpack/esbuild
- JS: Importmap + Hotwire (Turbo + Stimulus) — no bundler
- Database: SQLite for local development
- Testing: Minitest + SimpleCov (≥80% coverage) + Playwright for E2E
