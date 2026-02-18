# Research: Phase 2

## Phase Context
Phase 2 delivers the core Trello-like canvas: swimlane columns and cards within a board. It promotes the existing sparse `boards#show` stub into a full board view that renders swimlanes side-by-side, adds Swimlane and Card models with `name` and `position` fields, wires full CRUD for both via Turbo Frames/Streams, integrates SortableJS for drag-and-drop card reordering within and across lanes, and adds a `PATCH` endpoint to persist sort order server-side. All actions must be scoped to the current user's boards. The phase also resolves three items of Phase 1 technical debt: adding an explicit `before_action :require_authentication` to `ApplicationController`, adding strip-then-validate behavior to all name fields (including the existing `Board` model), and committing each logical task separately.

## Previous Phase Learnings

1. **Missing explicit `before_action :require_authentication`** — `ApplicationController` uses implicit concern behavior; SPEC requires an explicit declaration at the top of `ApplicationController` (`app/controllers/application_controller.rb:2`).
2. **`boards#show` is untested and out-of-scope from Phase 1** — the action exists at `app/controllers/boards_controller.rb:8` and the view at `app/views/boards/show.html.erb`, but there are zero authorization tests for it. Phase 2 fully owns this action.
3. **Whitespace-only board names pass `presence: true`** — `app/models/board.rb:3` uses only `validates :name, presence: true`; strip + presence pattern needs to be applied here and to all new name fields.
4. **Single large commit** — Phase 1 was one commit. Phase 2 must commit per logical task (model+migration, controller, views, tests).
5. **E2E tests sign up fresh in every test** — a shared seed/setup helper is recommended for more complex Phase 2 interactions (drag-and-drop).
6. **`parallelize(workers: 1)` is required** — `test/test_helper.rb:15` sets `parallelize(workers: 1)` to make SimpleCov report correctly; do not change this.

## Current Codebase State

### Relevant Components

#### Models
- **`Board`** — `app/models/board.rb:1-4`
  - `belongs_to :user`
  - `validates :name, presence: true` (no strip; known debt)
  - No `has_many :swimlanes` association yet
- **`User`** — `app/models/user.rb:1-9`
  - `has_many :boards, dependent: :destroy`
  - `normalizes :email_address` shows `strip.downcase` pattern — the existing model-level normalization approach for Phase 2's strip requirement
  - `has_secure_password`
- **`Session`** — `app/models/session.rb` (auth session, not test session)
- **`Current`** — `app/models/current.rb` (thread-local store; provides `Current.user` via `Current.session`)

#### Controllers
- **`ApplicationController`** — `app/controllers/application_controller.rb:1-8`
  - Includes `Authentication` concern at line 2 (implicit `before_action`)
  - No explicit `before_action :require_authentication` line — Phase 2 must add it
  - `allow_browser versions: :modern` at line 4
  - `stale_when_importmap_changes` at line 7
- **`BoardsController`** — `app/controllers/boards_controller.rb:1-47`
  - `before_action :set_board, only: [:show, :edit, :update, :destroy]` at line 2
  - `set_board` uses `Current.user.boards.find(params[:id])` — raises `ActiveRecord::RecordNotFound` (404) for wrong user, correct pattern for Phase 2
  - `show` action at line 8 is empty — no instance variable assignments, no authorization beyond `set_board`
  - All write actions (`create`, `update`, `destroy`) are scoped via `Current.user.boards`
- **`Authentication` concern** — `app/controllers/concerns/authentication.rb:1-52`
  - `included` block at line 4 declares `before_action :require_authentication` for all controllers that include it
  - `allow_unauthenticated_access` class method at line 10 skips the before_action
  - `require_authentication` at line 20: calls `resume_session || request_authentication`
  - `request_authentication` at line 32: redirects to `new_session_path`
  - `start_new_session_for` at line 41: sets `httponly: true, same_site: :lax` cookie

#### Views
- **`app/views/boards/show.html.erb`** — sparse scaffold at lines 1-9
  - Renders `@board.name`, Edit link, Back to Boards link
  - No swimlane rendering; this is the canvas Phase 2 will populate
- **`app/views/boards/index.html.erb`** — full listing at lines 1-29
  - Uses Tailwind grid layout (`grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4`)
  - Uses `button_to` with `data: { turbo_confirm: }` pattern for delete
  - No Turbo Frames; uses full-page redirects
- **`app/views/boards/_form.html.erb`** — shared form partial at lines 1-12
  - Uses `form_with model: board` (Rails UJS/Turbo aware)
  - Renders `board.errors.full_messages.to_sentence` in red alert box
  - Pattern to follow for swimlane/card inline forms
- **`app/views/layouts/application.html.erb`** — main layout at lines 1-41
  - Flash notice/alert rendered in `<body>` before `<main>`
  - `<main class="container mx-auto mt-8 px-5 flex">` — horizontal flex on main; important context for swimlane column layout (horizontal scroll or overflow needed)

#### Routes
- **`config/routes.rb`** — lines 1-10
  - `resources :boards` — standard 7 routes, currently no nesting
  - Phase 2 needs nested routes: `resources :boards do resources :swimlanes do resources :cards end end`
  - Or boards + swimlanes nested, with cards doubly nested under swimlanes

#### Database
- **`db/schema.rb`** — current schema at lines 13-41
  - `boards`: `id`, `created_at`, `name` (null: false), `updated_at`, `user_id` (null: false)
  - `sessions`: `id`, `created_at`, `ip_address`, `updated_at`, `user_agent`, `user_id` (null: false)
  - `users`: `id`, `created_at`, `email_address` (null: false, unique), `password_digest` (null: false), `updated_at`
  - No `swimlanes` or `cards` tables yet; both need migrations in Phase 2
  - Foreign keys: `boards.user_id → users`, `sessions.user_id → users`

#### JavaScript / Frontend
- **`config/importmap.rb`** — lines 1-7
  - Pins `@hotwired/turbo-rails`, `@hotwired/stimulus`, `@hotwired/stimulus-loading`
  - `pin_all_from "app/javascript/controllers"` — auto-discovers controllers
  - **No SortableJS pin** — Phase 2 must add it via `./bin/importmap pin sortablejs` or manually
- **`app/javascript/application.js`** — lines 1-3
  - Imports Turbo and controllers; minimal setup
- **`app/javascript/controllers/hello_controller.js`** — example Stimulus controller
  - Pattern: `export default class extends Controller { connect() { ... } }`
  - Phase 2's drag-and-drop controller will follow this structure
- **`app/javascript/controllers/index.js`** — auto-loader using `eagerLoadControllersFrom`

#### Tests
- **`test/test_helper.rb`** — lines 1-22
  - SimpleCov configured with `minimum_coverage 80` at line 4
  - `parallelize(workers: 1)` at line 15 (required for SimpleCov)
  - `fixtures :all` at line 17
  - Requires `test_helpers/session_test_helper`
- **`test/test_helpers/session_test_helper.rb`** — lines 1-19
  - `sign_in_as(user)` helper: creates a session and sets signed cookie
  - `sign_out` helper: destroys session and deletes cookie
  - Included in `ActionDispatch::IntegrationTest` via `on_load` hook at line 17
  - Available in all integration tests; Phase 2 controller/integration tests use this
- **`test/integration/boards_flow_test.rb`** — lines 1-71
  - Pattern: `setup` block creates `@user` and calls `sign_in_as @user`
  - Cross-user tests create a second user inline (no fixtures for users)
  - Asserts `:not_found` for cross-user access (line 54, 62, 68) — same pattern Phase 2 must follow
- **`test/models/board_test.rb`** — lines 1-28
  - Unit tests: valid, invalid without name, invalid without user, association
  - Pattern to follow for `SwimlanesTest` and `CardsTest`

#### E2E (Playwright)
- **`playwright.config.js`** — lines 1-15
  - `testDir: './e2e'`, `baseURL: http://localhost:3000`
  - `webServer` auto-starts `bin/rails server -e test -p 3000`
  - `reuseExistingServer: false` — fresh server per run
- **`e2e/auth.spec.js`** and **`e2e/boards.spec.js`**
  - Both duplicate a `signUp` helper function — known pattern, not a shared module
  - Every test calls `signUp` directly — per REFLECTIONS.md, Phase 2 should use a shared seed/setup helper
  - `page.fill('[name="board[name]"]', ...)` — attribute selector pattern for form inputs

### Existing Patterns to Follow

- **Authorization scoping**: `Current.user.boards.find(params[:id])` — raises 404 automatically for wrong user. Phase 2 uses same pattern: `Current.user.boards.find(params[:board_id])` then `.swimlanes.find(...)` then `.cards.find(...)`
- **Name validation**: `validates :name, presence: true` in Board — Phase 2 adds strip before validation. `User` model uses `normalizes` for strip; an `before_validation` callback with `name.strip!` or `attribute.strip.downcase` is the existing approach.
- **Flash + redirect pattern**: controllers redirect with `notice:` on success, render with `status: :unprocessable_entity` on failure
- **`button_to` for destructive actions**: `button_to "Delete", path, method: :delete, data: { turbo_confirm: "..." }` — used in boards index, follow for swimlane/card deletes
- **Tailwind utility classes**: max-w-*, flex, gap-*, bg-white, border, rounded, shadow-sm, text-*, hover:* — consistent design language
- **`form_with model:` partial**: shared `_form.html.erb` with error display — follow for swimlane/card forms
- **Integration test structure**: `setup` + `sign_in_as`, create data inline, assert response + state — no fixtures for domain objects

### Dependencies & Integration Points

- **Turbo Rails** (`gem "turbo-rails"`) — installed and pinned. `turbo_stream` responses, `turbo_frame_tag`, `dom_id` helpers all available. No Turbo Streams used yet in boards — Phase 2 introduces them.
- **Stimulus Rails** (`gem "stimulus-rails"`) — installed and pinned. `eagerLoadControllersFrom` auto-discovers controllers in `app/javascript/controllers/`. Phase 2's SortableJS controller goes here.
- **Tailwind CSS** (`gem "tailwindcss-rails"`) — standalone binary pipeline. CSS is scanned from views; any new Tailwind classes in ERB templates are auto-included on rebuild.
- **Propshaft** (`gem "propshaft"`) — asset pipeline (not Sprockets). Static assets served from `app/assets/`.
- **SortableJS** — not yet installed. SPEC says to use importmap or npm. Given the project uses importmap (no bundler), the standard approach is `./bin/importmap pin sortablejs` which adds a CDN pin to `config/importmap.rb`.
- **SimpleCov** (`gem "simplecov"`) — configured in `test/test_helper.rb`, `minimum_coverage 80`. Reports to `coverage/` directory.
- **Playwright** (`@playwright/test ^1.58.2`) — in `package.json` devDependencies. E2E tests in `e2e/`.

### Test Infrastructure

- **Test framework**: Minitest (`ActiveSupport::TestCase`, `ActionDispatch::IntegrationTest`)
- **Coverage**: SimpleCov with 80% floor; `parallelize(workers: 1)` required
- **Fixtures**: `fixtures :all` loaded; `test/fixtures/` exists but domain objects (users, boards) are created inline in tests — no user/board fixtures
- **Test helper**: `SessionTestHelper#sign_in_as(user)` available in all integration tests
- **E2E**: Playwright with auto-started test Rails server; tests in `e2e/`; sign-up done inline per test (no seed script yet)
- **Controller tests**: `test/controllers/` has `sessions_controller_test.rb` and `passwords_controller_test.rb` — no `boards_controller_test.rb` (boards uses integration tests instead)

## Code References

- `app/controllers/application_controller.rb:2` — `include Authentication` (no explicit `before_action :require_authentication`)
- `app/controllers/boards_controller.rb:8` — empty `show` action, no instance vars beyond `@board`
- `app/controllers/boards_controller.rb:41` — `set_board` uses `Current.user.boards.find` — the authorization-by-scoping pattern
- `app/controllers/concerns/authentication.rb:4-7` — `included` block that adds `before_action :require_authentication` via concern
- `app/models/board.rb:3` — `validates :name, presence: true` with no strip
- `app/models/user.rb:6` — `normalizes :email_address, with: ->(e) { e.strip.downcase }` — existing normalization pattern
- `app/views/boards/show.html.erb:1-9` — sparse board show canvas, ready to be expanded
- `app/views/layouts/application.html.erb:37` — `<main class="container mx-auto mt-8 px-5 flex">` — horizontal flex layout; swimlane columns will scroll horizontally within this
- `config/importmap.rb:1-7` — no SortableJS pin yet
- `config/routes.rb:6` — `resources :boards` with no nesting
- `db/schema.rb:13-41` — no swimlanes or cards tables
- `test/test_helper.rb:4-5` — SimpleCov config with 80% minimum
- `test/test_helper.rb:15` — `parallelize(workers: 1)` — required, do not change
- `test/test_helpers/session_test_helper.rb:3` — `sign_in_as(user)` helper
- `test/integration/boards_flow_test.rb:50-54` — cross-user `show` returns `:not_found` — pattern for Phase 2 swimlane/card auth tests
- `e2e/boards.spec.js:9-16` — `signUp` helper function (duplicated in auth.spec.js; Phase 2 should share)
- `playwright.config.js:9-14` — `webServer` config; `reuseExistingServer: false`

## Open Questions

1. **SortableJS CDN vs vendored**: The importmap approach will pin SortableJS from a CDN. If offline dev is needed or CSP is strict, vendoring in `vendor/javascript/` may be preferred. The `content_security_policy.rb` initializer should be checked — it exists at `config/initializers/content_security_policy.rb` and may need `script-src` updated for CDN usage.
2. **Turbo Stream vs Turbo Frame for CRUD**: The SPEC mentions both Frames and Streams. Frames (inline replacement) work well for inline edit forms; Streams (append/remove/replace) work well for create/delete without page reload. The design choice for each action needs to be made in the planning step.
3. **`PATCH /boards/:board_id/swimlanes/:swimlane_id/cards/:id` for position**: The SPEC defines this endpoint. Whether it returns `head :ok`, a Turbo Stream, or JSON needs to be decided. SortableJS can work with any of the three.
4. **E2E seed strategy**: Phase 1 REFLECTIONS recommend a shared seed helper for E2E. Phase 2 has drag-and-drop tests that require pre-existing swimlanes and cards. A shared `beforeEach` or global setup fixture in Playwright (`globalSetup`) would reduce test fragility.
5. **`layout/application.html.erb` main container**: The `<main>` uses `flex` which is horizontal. Swimlane columns will be flex children. If there are many swimlanes, horizontal overflow/scroll on the board canvas will need to be handled, potentially requiring a different wrapper structure for the `show` view.
6. **Board `name` strip fix**: The SPEC requires strip on Board names too (`board.rb:3`). This is in scope as technical debt cleanup. Needs a test update in `test/models/board_test.rb` to cover whitespace-only names.
