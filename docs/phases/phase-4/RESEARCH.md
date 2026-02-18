# Research: Phase 4

## Phase Context

Phase 4 introduces board sharing between registered users. It requires a new `BoardMembership` join table connecting boards to users with an `owner` or `member` role, a sharing UI on the board page for the owner to add/remove collaborators by email (with Turbo Stream updates — no page reloads), updated authorization across all controllers to scope access by membership rather than `user_id`, and collaborator access to boards, swimlanes, and cards — while keeping delete/rename board as owner-only actions.

## Previous Phase Learnings

From the Phase 3 review/must-fix notes embedded in `docs/phases/phase-4/SPEC.md`:

1. **Cosmetic fix first**: README is missing a `✓` for Phase 3 completion — fix before Phase 4 work.
2. **No `turbo_frame: "_top"` escape hatches**: The Phase 3 critical bug was using `_top` for description/due-date forms causing full-page reloads. Phase 4 member add/remove must use Turbo Streams from the start.
3. **Assert response body, not only model state**: Phase 3 integration tests checked `model.reload` but not the Turbo Stream HTML in the response. Phase 4 member tests must assert the Turbo Stream response body contains updated member list HTML.
4. **Audit every controller for the auth scope change**: Every controller currently uses `Current.user.boards.find()`. The plan needs an explicit checklist.
5. **Manual smoke test before committing**: Phase 2 lesson — run a manual walkthrough of add-member flow before committing.

## Current Codebase State

### Relevant Components

#### Models

- **Board** — `app/models/board.rb:1`
  - `belongs_to :user` — single FK `user_id` on `boards` table
  - `has_many :swimlanes, dependent: :destroy`
  - Validates `name` presence; strips whitespace in `before_validation`
  - No membership-scoped scope or method yet

- **User** — `app/models/user.rb:1`
  - `has_secure_password`
  - `has_many :sessions, dependent: :destroy`
  - `has_many :boards, dependent: :destroy` — this is the relationship Phase 4 must supplement with membership-scoped access
  - Normalizes `email_address` (strip + downcase)
  - Validates `email_address` presence, uniqueness case-insensitive
  - `email_address` column (not `email`) — important for lookup: `User.find_by(email_address:)`

- **Swimlane** — `app/models/swimlane.rb:1`
  - `belongs_to :board`
  - `has_many :cards, -> { order(:position) }, dependent: :destroy`
  - Validates name, strips whitespace
  - `before_create :set_position` — auto-positions on creation

- **Card** — `app/models/card.rb:1`
  - `belongs_to :swimlane`
  - `has_many :card_labels, dependent: :destroy`; `has_many :labels, through: :card_labels`
  - Validates name, strips whitespace
  - Scopes: `overdue`, `upcoming`
  - Method: `overdue?`
  - `before_create :set_position`

- **CardLabel** — `app/models/card_label.rb`
  - Join model between Card and Label
  - Unique composite index on `[card_id, label_id]`

- **Label** — `app/models/label.rb`
  - `color` string, unique index
  - Seeded with 5 predefined labels

- **Session** — `app/models/session.rb`
  - `belongs_to :user`

- **Current** — `app/models/current.rb`
  - Rails `CurrentAttributes` — exposes `Current.user` via `Current.session`

#### Database Schema

Current schema (`db/schema.rb`) — no `board_memberships` table yet:

- `boards`: `id`, `name`, `user_id` (FK → users), `created_at`, `updated_at` — `app/schema.rb:14`
- `users`: `id`, `email_address`, `password_digest`, `created_at`, `updated_at` — `app/schema.rb:68`
- `sessions`: `id`, `user_id`, `ip_address`, `user_agent`, `created_at`, `updated_at` — `app/schema.rb:50`
- `swimlanes`: `id`, `board_id`, `name`, `position`, `created_at`, `updated_at` — `app/schema.rb:59`
- `cards`: `id`, `swimlane_id`, `name`, `description`, `due_date`, `position`, `created_at`, `updated_at` — `app/schema.rb:32`
- `labels`: `id`, `color`, `created_at`, `updated_at` — `app/schema.rb:43`
- `card_labels`: `id`, `card_id`, `label_id`, `created_at`, `updated_at` — `app/schema.rb:21`

Latest migration timestamp: `20260218200003` — `db/migrate/20260218200003_create_card_labels.rb`

#### Controllers

- **ApplicationController** — `app/controllers/application_controller.rb:1`
  - `include Authentication` (Rails 8 built-in)
  - `before_action :require_authentication` — all actions require login
  - No custom authorization beyond authentication

- **BoardsController** — `app/controllers/boards_controller.rb:1`
  - `index`: `Current.user.boards.order(created_at: :desc)` — **must change to membership scope** — `:5`
  - `new`: `Current.user.boards.new` — `:13`
  - `create`: `Current.user.boards.new(board_params)` — `:17` — **must create BoardMembership owner row here**
  - `set_board`: `Current.user.boards.find(params[:id])` — `:43` — **must change to membership scope for show/edit; owner-only scope for update/destroy**
  - `board_params`: permits `:name` only — `:46`

- **SwimlanesController** — `app/controllers/swimlanes_controller.rb:1`
  - `set_board`: `Current.user.boards.find(params[:board_id])` — `:53` — **must change to membership scope** (all swimlane actions allowed for members)
  - Uses `turbo_stream` responds via `.turbo_stream.erb` view files
  - Uses `dom_id` helper via `include ActionView::RecordIdentifier`

- **CardsController** — `app/controllers/cards_controller.rb:1`
  - `set_board`: `Current.user.boards.find(params[:board_id])` — `:88` — **must change to membership scope**
  - `reorder`: has its own inline auth check at `:67` — `Current.user.boards.joins(swimlanes: :cards).where(cards: { id: card.id }).exists?` — **must also be updated to membership scope**
  - Uses `dom_id` via `include ActionView::RecordIdentifier`
  - Turbo Stream responses for create, update, destroy

#### Routes

`config/routes.rb:1` — current routes:

```
resource :session
resources :passwords, param: :token
resource :registration, only: [:new, :create]
resources :boards do
  resources :swimlanes, only: [:create, :edit, :update, :destroy] do
    member { get :header }
    resources :cards, only: [:show, :create, :edit, :update, :destroy] do
      collection { patch :reorder }
    end
  end
end
root "boards#index"
```

Phase 4 will add a nested `memberships` resource under `boards` (e.g., `boards/:id/memberships`).

#### Views

- **boards/index.html.erb** — `app/views/boards/index.html.erb:1`
  - Shows `@boards` — Phase 4 changes the query in the controller; the view stays the same or gains a role indicator
  - Shows "Edit" and "Delete" for every board card in the grid — Phase 4 must conditionally hide "Delete" for collaborators

- **boards/show.html.erb** — `app/views/boards/show.html.erb:1`
  - Shows "Edit Board" link — must be owner-only in Phase 4
  - No members panel yet — Phase 4 adds one, visible only to the owner

- **swimlanes/_swimlane.html.erb** — `app/views/swimlanes/_swimlane.html.erb:1`
  - Renders "Rename" link and "Delete" button for every swimlane — these stay available to collaborators (SPEC says members can create/edit/delete swimlanes and cards)

#### Turbo Stream Patterns

Already-established pattern (used for swimlanes and cards):

1. Controller action responds to `format.turbo_stream`
2. A `.turbo_stream.erb` view file appends/replaces/removes DOM elements
3. `dom_id(record)` generates consistent element IDs
4. Inline turbo_stream render for error cases (validation failures):
   - `render turbo_stream: turbo_stream.replace("target_id", partial: ...), status: :unprocessable_entity`

Example — `app/views/swimlanes/create.turbo_stream.erb`:
```erb
<%= turbo_stream.append "swimlanes", partial: "swimlanes/swimlane", locals: { ... } %>
<%= turbo_stream.replace "new_swimlane_form", partial: "swimlanes/new_form", locals: { ... } %>
```

#### Authentication

Rails 8 built-in authentication via `Authentication` concern. `Current.user` resolves from `Current.session` which is set from the signed `session_id` cookie. `sign_in_as` in `SessionTestHelper` sets `Current.session` and the test cookie.

### Existing Patterns to Follow

- **Authorization pattern**: `Current.user.boards.find(params[:board_id])` — raises `ActiveRecord::RecordNotFound` (→ 404) for unauthorized access; this exact pattern must be replicated with the new membership scope — `app/controllers/boards_controller.rb:43`, `app/controllers/swimlanes_controller.rb:53`, `app/controllers/cards_controller.rb:88`

- **Turbo Stream response pattern**: Controller responds to `format.turbo_stream`, delegates to `.turbo_stream.erb` view; errors use inline `render turbo_stream:` with `status: :unprocessable_entity` — `app/controllers/swimlanes_controller.rb:14-15`, `app/views/swimlanes/create.turbo_stream.erb`

- **Model validation + strip pattern**: `validates :name, presence: true` + `before_validation { name&.strip! }` — `app/models/board.rb:4-5`, `app/models/swimlane.rb:5-6`

- **`dom_id` for Turbo targets**: All DOM element IDs are generated via `dom_id(record)` or `dom_id(record, :suffix)` — consistent across views and Turbo Stream responses

- **Inline vs. view file Turbo Streams**: Successful actions use `.turbo_stream.erb` files; validation failures use inline `render turbo_stream:` in the controller — e.g., `app/controllers/swimlanes_controller.rb:36-38`

- **Integration test pattern**: `ActionDispatch::IntegrationTest` + `sign_in_as @user` from `SessionTestHelper`; creates records inline in setup, asserts response codes and response body content — `test/integration/boards_flow_test.rb`, `test/integration/cards_flow_test.rb`

- **E2E helper pattern**: `signUp`, `uniqueEmail`, `createBoard` in `e2e/helpers/auth.js` — reused across all spec files; Phase 4 will likely need `signIn` (sign in to existing account) and possibly `addMember` helpers

- **Fixtures**: Two users (`one`, `two`) pre-exist in `test/fixtures/users.yml`; two boards in `test/fixtures/boards.yml` each owned by a different user. Fixture data is available via `users(:one)`, `boards(:one)` etc. in tests that use fixtures.

- **User email column name**: `email_address` (not `email`) — `db/schema.rb:70`, `app/models/user.rb:6`

### Dependencies & Integration Points

- **`Current.user.boards`** is used in 3 places that must change:
  - `BoardsController#index` — `:5`
  - `BoardsController#set_board` — `:43`
  - `SwimlanesController#set_board` — `:53`
  - `CardsController#set_board` — `:88`
  - `CardsController#reorder` inline check — `:67`

- **Board creation** (`BoardsController#create`) — must also create the `BoardMembership` owner row after `@board.save` succeeds

- **`BoardsController#new`**: `Current.user.boards.new` builds with `user_id: Current.user.id` — this can stay as-is since `user_id` column remains on boards for the owner association

- **`User.find_by(email_address:)`** — the lookup for adding a member by email; the column is `email_address` not `email`

- **No external libraries needed**: Turbo Streams are already in place; enum support is built into Rails ActiveRecord

- **Fixtures must gain a `board_memberships.yml`** if any fixture-based tests reference memberships; however, existing integration tests create records inline (no fixture dependency), so a `board_memberships.yml` fixture file may only be needed if model tests reference board memberships via fixtures

### Test Infrastructure

- **Framework**: Minitest
- **Coverage**: SimpleCov, minimum 80% — `test/test_helper.rb:2-5`
- **Parallelism**: `workers: 1` (single-threaded tests) — `test/test_helper.rb:16`
- **Fixtures**: All fixtures loaded — `test/test_helper.rb:20`
- **Session helper**: `sign_in_as(user)` and `sign_out` — `test/test_helpers/session_test_helper.rb`
- **Test types**:
  - Model unit tests: `test/models/` — validate model behavior
  - Controller tests: `test/controllers/` — sessions and passwords
  - Integration tests: `test/integration/` — full request cycle with auth
  - E2E tests: `e2e/` (Playwright) — `npx playwright test`
- **Pattern for integration tests**: `ActionDispatch::IntegrationTest`, inline record creation in setup, `sign_in_as`, HTTP verbs (`get`, `post`, `patch`, `delete`), `assert_response`, `assert_match`/`assert_no_match` on `response.body` — `test/integration/boards_flow_test.rb`
- **Turbo Stream header for tests**: `headers: { "Accept" => "text/vnd.turbo-stream.html" }` — `test/integration/cards_flow_test.rb:19-24`

## Code References

- `app/models/board.rb:1` — Board model (belongs_to :user, has_many :swimlanes)
- `app/models/user.rb:1` — User model (email_address column, has_many :boards)
- `app/controllers/boards_controller.rb:5` — `Current.user.boards.order(...)` in index
- `app/controllers/boards_controller.rb:43` — `Current.user.boards.find(params[:id])` in set_board
- `app/controllers/swimlanes_controller.rb:53` — `Current.user.boards.find(params[:board_id])` in set_board
- `app/controllers/cards_controller.rb:88` — `Current.user.boards.find(params[:board_id])` in set_board
- `app/controllers/cards_controller.rb:67` — inline reorder auth check using `Current.user.boards.joins(...)`
- `app/controllers/application_controller.rb:1` — ApplicationController with Authentication concern
- `config/routes.rb:6` — boards resource (nests swimlanes → cards)
- `db/schema.rb:14` — boards table (has user_id FK)
- `db/schema.rb:68` — users table (email_address column)
- `app/views/boards/index.html.erb:15-18` — Edit/Delete links shown for all boards (must gate Delete on ownership)
- `app/views/boards/show.html.erb:5` — "Edit Board" link (must become owner-only)
- `app/views/swimlanes/_swimlane.html.erb:6-11` — Rename/Delete controls on swimlane header
- `app/views/swimlanes/create.turbo_stream.erb:1` — Turbo Stream append + replace pattern
- `test/test_helpers/session_test_helper.rb:3` — `sign_in_as` sets Current.session + cookie
- `test/integration/boards_flow_test.rb:58-85` — Existing non-member access → 404 tests (will need updating for membership model)
- `e2e/helpers/auth.js:1` — signUp, uniqueEmail, createBoard E2E helpers

## Open Questions

1. **Fixture strategy for `board_memberships`**: Should a `test/fixtures/board_memberships.yml` be added to ensure existing fixture-dependent tests stay consistent after the migration, or do all integration tests create records inline (avoiding fixture dependency)?

2. **`user_id` column on boards**: The column stays (it still identifies the owner), but the authorization scope shifts to `board_memberships`. Should `Board#user` remain as the direct "creator/owner" association, or should owner identification go through `BoardMembership` only? This affects how `set_board` distinguishes members vs. owners for owner-only actions.

3. **Scope naming**: The SPEC mentions `Board.accessible_by(user)` (or equivalent). The plan needs to decide whether this lives as a class-level scope on `Board`, a method on `User`, or a query helper — it will be used in at least 4 controller locations.

4. **Existing test compatibility**: `boards_flow_test.rb` lines 58-84 test that `other_board` (owned by `other_user`) returns 404 to `@user`. After Phase 4, those tests will still pass as long as no membership is created for `@user` on `other_board`. These tests do not need modification for the membership model, but the plan should confirm this.

5. **`BoardsController#new` / `create`**: `@board = Current.user.boards.new(board_params)` still works since `user_id` is on the boards table. The only addition is creating the `BoardMembership` owner row after save. Should this be a model callback (`after_create`) or explicit controller code?
