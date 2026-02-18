# Phase 1: Project Setup, Authentication, and Board CRUD

## Objective
Scaffold the Rails 8 application with built-in authentication and full board management (create, read, update, delete). By the end of this phase, a user can sign up, log in, create boards, rename them, delete them, and log out. This is the foundational vertical slice: real authentication protecting real data, with a working UI a user can navigate.

## Scope

### In Scope
- Rails 8 application scaffold with SQLite
- Tailwind CSS integration
- Hotwire/Turbo/Stimulus setup (comes with Rails 8 defaults)
- Rails 8 built-in authentication (`rails generate authentication`)
- Sign up, log in, log out flows
- Board model with CRUD (create, list, show, edit, delete)
- Boards index as the authenticated landing page
- AGENTS.md, README.md, updated CLAUDE.md
- Minitest setup with coverage reporting (SimpleCov)
- Playwright end-to-end tests for auth and board flows

### Out of Scope
- Swimlanes (columns) — Phase 2
- Cards — Phase 2
- Drag-and-drop — Phase 2
- Card details (descriptions, due dates, labels, checklists) — Phase 3
- Board sharing between users — Phase 4
- Real-time updates via ActionCable — Phase 5
- Board background customization — Phase 6
- Email/password reset flows
- Image uploads of any kind

## Requirements
- The app must use Rails 8 with no Docker dependency
- Authentication uses `rails generate authentication` (no Devise)
- SQLite for local development
- All board actions require authentication; unauthenticated requests redirect to login
- A board belongs to the user who created it; only that user can view, edit, or delete it
- Board name is required and must not be blank
- Tailwind CSS used for all styling
- Turbo Drive enabled for navigation (default Rails 8 behavior)

## Acceptance Criteria
- [ ] `bin/setup` installs dependencies and prepares the database
- [ ] `bin/rails server` starts the app with no errors
- [ ] A new visitor can sign up with email and password
- [ ] A registered user can log in and is redirected to the boards index
- [ ] An unauthenticated user visiting `/boards` is redirected to the login page
- [ ] A logged-in user can create a board with a name
- [ ] The boards index lists all boards belonging to the current user
- [ ] A logged-in user can edit a board name inline or via an edit form
- [ ] A logged-in user can delete a board (with confirmation)
- [ ] A logged-in user can log out and is redirected to the login page
- [ ] All Minitest unit and integration tests pass (`bin/rails test`)
- [ ] SimpleCov reports test coverage (output to `coverage/` directory)
- [ ] All Playwright end-to-end tests pass
- [ ] Code compiles without warnings

## Testing Strategy
- **Framework**: Minitest (Rails default) with SimpleCov for coverage
- **Unit tests**: User model validations, Board model validations (name presence, user association)
- **Integration tests**: Authentication flows (sign up, log in, log out), Board CRUD flows (create, list, edit, delete), authorization (board not accessible by other users)
- **Coverage expectation**: ≥ 80% line coverage reported by SimpleCov
- **E2E tests**: Playwright tests covering:
  - Sign up → boards index
  - Log in → boards index
  - Create a board → see it listed
  - Edit a board name → see the update
  - Delete a board → confirm it disappears
  - Log out → redirected away from boards
- **Test commands**:
  - Unit + integration: `bin/rails test`
  - Coverage: same command; SimpleCov auto-generates `coverage/index.html`
  - E2E: `npx playwright test`

## Documentation Updates
- **AGENTS.md** (create at project root): install steps (`bin/setup`), run commands (`bin/rails server`), test commands (`bin/rails test`, `npx playwright test`), coverage command, project structure overview
- **README.md** (create at project root): project description, getting started (clone, `bin/setup`, `bin/rails server`), test instructions, Playwright setup note
- **CLAUDE.md** (update, do NOT overwrite): add emphatic instruction to read AGENTS.md first, add brief project description above the cc-pipeline section; keep all existing content

## Dependencies
- Ruby (version matching `.ruby-version` or >= 3.2)
- Node.js and npm/yarn (for Tailwind CSS build pipeline and Playwright)
- No external services required for Phase 1

## Adjustments from Previous Phase
First phase — no prior adjustments.
