# Research: Phase 5

## Phase Context

Phase 5 adds real-time collaboration to Swimlanes via ActionCable. When any board member creates, updates, moves, or deletes a card or swimlane, all other members currently viewing that board see the change instantly — no page reload. This requires a `BoardChannel` that authenticates subscribers via session cookie and verifies board membership using `Board.accessible_by`, a `turbo_stream_from` tag on the board show page, and broadcast callbacks triggered after each write operation on Card and Swimlane models.

## Previous Phase Learnings

From Phase 4 REFLECTIONS.md, relevant to Phase 5:

- **Channel auth is the hard problem first**: Prove `BoardChannel` authenticates and rejects connections before adding any broadcast logic. Phase 4 warned this explicitly.
- **Use `BoardMembership.exists?()` not association check**: Phase 4's deviation from `@board.members.include?(user)` (memory-heavy) to `BoardMembership.exists?()` (DB-efficient) is the established pattern — use it in channel subscription auth.
- **Dual assertions in integration tests**: Assert both HTTP response status AND broadcast enqueued. Phase 4 showed HTTP-only assertions leave side effects untested.
- **Design E2E helpers before writing specs**: Phase 4's unused `signIn` import was from writing specs without resolving the helper interface. The SPEC requires defining `signInAs(page, email, password)` once before writing specs.
- **Documentation as a checklist item**: AGENTS.md project structure section must be updated explicitly as a sub-task, not implied.
- **Check plan deviations before committing**: Add self-review against plan checklist before commit.

## Current Codebase State

### Relevant Components

- **ActionCable Connection** (already implemented): `app/channels/application_cable/connection.rb:1` — `identified_by :current_user`; `connect` method looks up `Session.find_by(id: cookies.signed[:session_id])` and sets `current_user` from that session; calls `reject_unauthorized_connection` if no valid session. **This is the full auth infrastructure needed — unauthenticated WebSocket connections are already rejected here.**

- **No BoardChannel exists yet**: Only `app/channels/application_cable/connection.rb` is present. `BoardChannel` does not exist and must be created at `app/channels/board_channel.rb`.

- **Board model**: `app/models/board.rb:10` — `Board.accessible_by(user)` scope: `joins(:board_memberships).where(board_memberships: { user_id: user.id })`. This is the exact predicate to gate channel subscriptions.

- **BoardMembership model**: `app/models/board_membership.rb:1` — `belongs_to :board`, `belongs_to :user`, `enum :role, { owner: 0, member: 1 }`. Used in subscription auth via `BoardMembership.exists?(board: @board, user: current_user)`.

- **Card model**: `app/models/card.rb:1` — `belongs_to :swimlane`; has `before_create :set_position` callback; no existing broadcast callbacks. Broadcasts must be added here or in controllers.

- **Swimlane model**: `app/models/swimlane.rb:1` — `belongs_to :board`; has `before_create :set_position` callback; no existing broadcast callbacks.

- **CardsController**: `app/controllers/cards_controller.rb:1`
  - `create` (line 11): saves card, responds `format.turbo_stream` → renders `cards/create.turbo_stream.erb`
  - `update` (line 36): updates card, responds `format.turbo_stream` → renders `cards/update.turbo_stream.erb`
  - `destroy` (line 56): destroys card, renders inline `turbo_stream.remove(dom_id(@card))`
  - `reorder` (line 64): moves card to destination swimlane, returns `head :ok` — **this is where card-move broadcast must be added**
  - All actions use `set_board` which calls `Board.accessible_by(Current.user).find(...)` for authorization

- **SwimlanesController**: `app/controllers/swimlanes_controller.rb:1`
  - `create` (line 6): saves swimlane, responds `format.turbo_stream` → renders `swimlanes/create.turbo_stream.erb`
  - `update` (line 29): updates swimlane, responds `format.turbo_stream` → renders `swimlanes/update.turbo_stream.erb`
  - `destroy` (line 43): destroys swimlane, renders inline `turbo_stream.remove(dom_id(@swimlane))`
  - `set_board` (line 53) also uses `Board.accessible_by(Current.user).find(...)`

- **Board show page**: `app/views/boards/show.html.erb:1` — **No `turbo_stream_from` tag exists yet.** Has `<div id="swimlanes" class="flex gap-4 items-start">` at line 15 (the swimlane column container). `turbo_stream_from @board` must be added here.

### Existing Turbo Stream Views (HTTP path — these are for the requesting user's response)

- **Card create**: `app/views/cards/create.turbo_stream.erb:1`
  - `turbo_stream.append dom_id(@swimlane, :cards)` — appends `_card` partial
  - `turbo_stream.replace dom_id(@swimlane, :new_card_form)` — resets the form

- **Card update**: `app/views/cards/update.turbo_stream.erb:1`
  - `turbo_stream.replace dom_id(@card, :face)` — replaces the card face partial

- **Swimlane create**: `app/views/swimlanes/create.turbo_stream.erb:1`
  - `turbo_stream.append "swimlanes"` — appends `_swimlane` partial to `#swimlanes` container
  - `turbo_stream.replace "new_swimlane_form"` — resets the new lane form

- **Swimlane update**: `app/views/swimlanes/update.turbo_stream.erb:1`
  - `turbo_stream.replace dom_id(@swimlane, :header)` — replaces the header partial

### DOM IDs to Target for Broadcasts

- Card container root: `dom_id(card)` → e.g., `card_42`
- Card face (updated on edit): `dom_id(card, :face)` → e.g., `face_card_42`
- Swimlane container root: `dom_id(swimlane)` → e.g., `swimlane_7`
- Swimlane header: `dom_id(swimlane, :header)` → e.g., `header_swimlane_7`
- Swimlane cards container: `dom_id(swimlane, :cards)` → e.g., `cards_swimlane_7`
- Swimlane new card form: `dom_id(swimlane, :new_card_form)` → e.g., `new_card_form_swimlane_7`
- Global swimlanes container: `"swimlanes"` (bare string in board show view, line 15)

### Partials Available for Broadcasting

- `_card` partial: `app/views/cards/_card.html.erb` — renders full card DOM including `dom_id(card)` wrapper
- `_face` partial: `app/views/cards/_face.html.erb` — card face with name, labels, due date
- `_swimlane` partial: `app/views/swimlanes/_swimlane.html.erb` — full lane column including header, cards list
- `_header` partial: `app/views/swimlanes/_header.html.erb` — swimlane name + rename/delete controls

### Dependencies & Integration Points

- **`turbo-rails` gem**: `Gemfile:14` — provides `turbo_stream_from` view helper and `Turbo::StreamsChannel`. Already present.
- **`ActionCable`**: Built into Rails 8. No additional gems needed.
- **`cable.yml`**: `config/cable.yml:5` — `async` adapter for development; `test` adapter for test environment (enables `assert_broadcasts` in Minitest); `solid_cable` for production.
- **Session cookie**: `Authentication` concern (`app/controllers/concerns/authentication.rb:29`) sets `cookies.signed.permanent[:session_id]` with `httponly: true, same_site: :lax`. The ActionCable connection reads this same cookie at `app/channels/application_cable/connection.rb:11`.
- **`Current.user`**: Provided via `Current < ActiveSupport::CurrentAttributes` (`app/models/current.rb:3`). In channels, `current_user` is set directly on the connection — it is **not** `Current.user` but the channel's own `current_user` method.
- **`Board.accessible_by(user)`**: `app/models/board.rb:10` — the membership predicate for channel subscription gating.

### Test Infrastructure

- **Test framework**: Minitest with `ActionDispatch::IntegrationTest` for integration tests
- **SimpleCov**: `test/test_helper.rb:2` — `minimum_coverage 80`, configured with `SimpleCov.start "rails"`
- **ActionCable test adapter**: `config/cable.yml:8` — `adapter: test` in test env; this adapter supports `assert_broadcasts` and `assert_no_broadcasts` assertions
- **Session helper**: `test/test_helpers/session_test_helper.rb:2` — `sign_in_as(user)`, `sign_out`, `create_owned_board(user, name:)` — available to all `ActionDispatch::IntegrationTest` subclasses via `ActiveSupport.on_load` hook
- **Turbo headers pattern**: `TURBO_HEADERS = { "Accept" => "text/vnd.turbo-stream.html" }` — used in `memberships_flow_test.rb:6`, `cards_flow_test.rb`, `swimlanes_flow_test.rb`
- **Parallel workers**: `test/test_helper.rb:15` — `parallelize(workers: 1)` — tests run sequentially
- **Fixtures**: `test/test_helper.rb:18` — `fixtures :all` — label fixtures exist (`:red`, `:yellow`, etc. used in cards tests)
- **Channel test class**: Rails provides `ActionCable::Channel::TestCase` for unit-testing channels — not yet used in this codebase

### E2E Test Infrastructure

- **Playwright config**: `playwright.config.js` — `testDir: './e2e'`, `workers: 1`, `baseURL: 'http://localhost:3000'`, auto-starts Rails in test mode
- **Auth helpers**: `e2e/helpers/auth.js` — exports `signUp(page, email)`, `signIn(page, email, password)`, `uniqueEmail(prefix)`, `createBoard(page, name)`, `PASSWORD`
  - `signIn` at line 16 already matches the `signInAs(page, email, password)` signature the SPEC requests — **this function exists as `signIn`; Phase 5 can either use `signIn` directly or add a `signInAs` alias**
- **Existing spec files**: `auth.spec.js`, `boards.spec.js`, `board_canvas.spec.js`, `board_sharing.spec.js`, `card_detail.spec.js`
- **Multi-context pattern**: `board_sharing.spec.js` already uses `browser.newContext()` for separate user sessions — this exact pattern is needed for Phase 5 real-time E2E tests

### Authentication Flow in ActionCable (existing)

The `ApplicationCable::Connection` (`app/channels/application_cable/connection.rb`) already implements the full unauthenticated-rejection flow:
1. `connect` calls `set_current_user || reject_unauthorized_connection`
2. `set_current_user` reads `cookies.signed[:session_id]`
3. Finds a `Session` record; sets `self.current_user = session.user`
4. If no session found, returns `nil` → connection is rejected

`BoardChannel` only needs to implement board-level membership gating in its `subscribed` method (reject if `Board.accessible_by(current_user).where(id: params[:board_id]).none?` or similar).

## Code References

- `app/channels/application_cable/connection.rb:1` — Full ActionCable auth via session cookie; `current_user` is set here
- `app/models/board.rb:10` — `Board.accessible_by(user)` scope (membership join)
- `app/models/board_membership.rb:5` — `enum :role, { owner: 0, member: 1 }`
- `app/models/card.rb:12` — `before_create :set_position` callback (broadcast callbacks will be added alongside)
- `app/models/swimlane.rb:8` — `before_create :set_position` callback
- `app/controllers/cards_controller.rb:11` — `create` action; turbo stream response path
- `app/controllers/cards_controller.rb:36` — `update` action; turbo stream response path
- `app/controllers/cards_controller.rb:56` — `destroy` action; inline turbo_stream.remove
- `app/controllers/cards_controller.rb:64` — `reorder` action; `head :ok` — broadcast of card move must be triggered here
- `app/controllers/swimlanes_controller.rb:6` — `create` action
- `app/controllers/swimlanes_controller.rb:29` — `update` action
- `app/controllers/swimlanes_controller.rb:43` — `destroy` action; inline turbo_stream.remove
- `app/views/boards/show.html.erb:15` — `<div id="swimlanes">` — where `turbo_stream_from @board` must be added (near top of page)
- `app/views/cards/create.turbo_stream.erb:1` — HTTP turbo stream for card create (broadcast mirrors this)
- `app/views/cards/update.turbo_stream.erb:1` — HTTP turbo stream for card update (broadcast mirrors this)
- `app/views/swimlanes/create.turbo_stream.erb:1` — HTTP turbo stream for swimlane create
- `app/views/swimlanes/update.turbo_stream.erb:1` — HTTP turbo stream for swimlane update
- `app/views/cards/_card.html.erb:1` — Full card partial with `dom_id(card)` root element
- `app/views/swimlanes/_swimlane.html.erb:1` — Full lane partial with `dom_id(swimlane)` root element
- `config/cable.yml:8` — `adapter: test` in test env (enables `assert_broadcasts`)
- `e2e/helpers/auth.js:16` — `signIn(page, email, password)` — existing helper matching SPEC's `signInAs` shape
- `e2e/board_sharing.spec.js:6` — `browser.newContext()` multi-user E2E pattern to reuse
- `test/test_helpers/session_test_helper.rb:2` — `sign_in_as(user)`, `create_owned_board` helpers
- `test/integration/memberships_flow_test.rb:6` — `TURBO_HEADERS` pattern and multi-user sign-in/sign-out test flow
- `Gemfile:14` — `gem "turbo-rails"` confirmed present

## Open Questions

1. **Broadcast location — models vs. after-action service objects vs. controllers**: The SPEC says "callbacks or service objects." Models are simple but create ActiveRecord-level coupling; controllers are explicit and easier to test with `assert_broadcasts`. The plan must choose one approach and document it in AGENTS.md.

2. **`turbo_stream_from` signed vs. unsigned**: `turbo_stream_from @board` generates a signed stream tag. The `BoardChannel` subscription must be gated separately — the signed stream alone doesn't enforce membership. The plan needs to clarify the two-layer auth: (1) connection-level user auth, (2) channel `subscribed` membership check.

3. **Card move broadcast**: The `reorder` action (`cards_controller.rb:64`) currently returns `head :ok` — no turbo stream response for the requesting user. A move broadcast needs to produce a `remove` from source lane and `append` to destination lane. The plan must decide what partial to broadcast (full `_card` partial) and what DOM IDs to target.

4. **`signInAs` vs. `signIn`**: The SPEC says "define `signInAs(page, email, password)`" as a shared helper. `e2e/helpers/auth.js` already exports `signIn` with the same signature. The plan must decide: rename existing `signIn` to `signInAs` (breaking change to existing specs), export both, or use `signIn` directly in Phase 5 specs.

5. **Board stream identifier**: `turbo_stream_from @board` uses `board.to_gid_param` as the stream name. Broadcasting from controllers/models must use the same identifier: `Turbo::StreamsChannel.broadcast_*_to(@board, ...)`.
