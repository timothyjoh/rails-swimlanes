# Swimlanes

A Trello-like board management application built with Rails 8, Hotwire (Turbo + Stimulus), Tailwind CSS, and SQLite.

## Features

**Phase 1 — Boards**
- Sign up and log in with email/password
- Create, rename, and delete boards
- Boards are private — only the owner can view or manage them
- Secure session management via Rails 8 built-in authentication

**Phase 2 — Swimlanes and Cards**
- Add, rename, and delete swimlane columns within a board
- Add, rename, and delete cards within a lane
- Drag cards to reorder within a lane or move between lanes
- Positions persist across page reloads
- All interactions use Turbo Streams (no full-page reloads) and inline Turbo Frames for editing

**Phase 3 — Card Details**
- Card descriptions: plain text descriptions shown as an indicator on the card face
- Due dates with overdue indicator: red badge for past-due cards
- Color-coded labels (red, yellow, green, blue, purple) toggled from the card detail view
- Card detail modal: click a card title to open an expanded view with description, due date, and labels

**Phase 4 — Board Sharing**
- Board owners can share boards with other registered users by email address
- Collaborators (members) can create, edit, and delete swimlanes and cards
- Owner-only controls (rename board, delete board) are hidden from collaborators
- Members panel on the board page shows current members; add/remove updates live via Turbo Streams
- Shared boards appear on the collaborator's boards index page
- Non-members receive 404 when accessing a board URL directly

**Phase 5 — Real-time Collaboration**
- Live updates via ActionCable: cards and swimlanes created, updated, or deleted by one user appear instantly for all board members
- Connection-level authentication ensures only signed-in users can open WebSocket connections
- Channel-level authorization verifies board membership before subscribing to updates
- No page reload required — Turbo Streams are broadcast over WebSocket to all connected members

## Getting Started

### Prerequisites
- Ruby 3.4+ (via Homebrew: `/usr/local/opt/ruby/bin/ruby`)
- Node.js 18+ and npm
- No Docker required

### Install

```bash
export PATH="/usr/local/lib/ruby/gems/3.4.0/bin:/usr/local/opt/ruby/bin:$PATH"
git clone <repo>
cd rails-swimlanes
bin/setup --skip-server
```

### Run

```bash
export PATH="/usr/local/lib/ruby/gems/3.4.0/bin:/usr/local/opt/ruby/bin:$PATH"
bin/rails server
```

Open http://localhost:3000, sign up, and start creating boards.

## Testing

```bash
# Unit and integration tests (with SimpleCov coverage report)
export PATH="/usr/local/lib/ruby/gems/3.4.0/bin:/usr/local/opt/ruby/bin:$PATH"
bin/rails test

# End-to-end tests (auto-starts a Rails test server)
npx playwright test
```

Coverage report generated to `coverage/index.html` after running `bin/rails test`.

## Tech Stack
- **Rails 8** with built-in authentication (no Devise)
- **SQLite** for local development
- **Tailwind CSS** via `tailwindcss-rails` standalone binary
- **Hotwire** (Turbo + Stimulus) for dynamic interactions
- **Importmap** for JavaScript (no webpack/esbuild)
- **Minitest** + **SimpleCov** for unit/integration testing (≥80% coverage)
- **Playwright** for end-to-end testing

## Project Roadmap
- Phase 1 ✓ — Setup, authentication, board CRUD
- Phase 2 ✓ — Swimlanes (columns) and cards
- Phase 3 ✓ — Card details (descriptions, due dates, labels, checklists)
- Phase 4 ✓ — Board sharing between users
- Phase 5 ✓ — Real-time collaboration (ActionCable)
- Phase 6 — Board background customization
