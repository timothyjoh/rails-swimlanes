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
  controllers/     # ApplicationController, BoardsController, RegistrationsController,
                   # SessionsController, PasswordsController
  models/          # User, Board, Session, Current
  views/           # boards/, sessions/, registrations/, passwords/, layouts/
config/
  routes.rb        # All routes: session, registration, boards, root
db/
  schema.rb        # Current DB schema (users, sessions, boards)
test/
  models/          # User, Board unit tests
  controllers/     # Sessions, Passwords controller tests
  integration/     # Auth flow, Boards CRUD integration tests
  test_helpers/    # SessionTestHelper for signing in during tests
e2e/               # Playwright end-to-end tests (auth.spec.js, boards.spec.js)
docs/phases/       # Phase specs, research, plans, reflections
```

## Phase Roadmap
- Phase 1 (current): Setup, auth, board CRUD
- Phase 2: Swimlanes (columns) and cards
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
