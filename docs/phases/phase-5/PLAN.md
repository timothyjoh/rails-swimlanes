# Implementation Plan: Phase 5

## Overview
Add real-time collaboration to Swimlanes via ActionCable: create `BoardChannel` with membership-scoped authentication, then broadcast Turbo Stream updates from CardsController and SwimlanesController so all board members see card and swimlane changes instantly without a page reload.

## Current State (from Research)

- **`ApplicationCable::Connection`** already rejects unauthenticated WebSocket connections via session cookie lookup — no changes needed.
- **`BoardChannel`** does not exist yet; `Turbo::StreamsChannel` (from turbo-rails) handles all current WebSocket subscriptions (none for boards currently).
- **Board show page** has no `turbo_stream_from` tag — browsers never subscribe to board updates.
- **CardsController** and **SwimlanesController** have no broadcast calls — mutations affect only the requesting user via HTTP Turbo Stream responses.
- **`config/cable.yml`** uses `adapter: test` in test environment — `assert_broadcasts` is available.
- **`e2e/helpers/auth.js`** exports `signIn(page, email, password)` — matches the SPEC's `signInAs` signature exactly; we'll add a non-breaking alias.
- **`e2e/board_sharing.spec.js`** establishes the `browser.newContext()` multi-user pattern we'll reuse for real-time E2E tests.
- **Partials available**: `cards/_card.html.erb` (locals: `card`, `board`, `swimlane`), `cards/_face.html.erb` (locals: `card`, `board`, `swimlane`), `swimlanes/_swimlane.html.erb` (locals: `swimlane`, `board`), `swimlanes/_header.html.erb` (locals: `swimlane`, `board`).

## Desired End State

- `app/channels/board_channel.rb` exists, inherits from `Turbo::StreamsChannel`, overrides `subscribed` to check `BoardMembership.exists?` and rejects non-members.
- `app/views/boards/show.html.erb` has `turbo_stream_from @board, channel: BoardChannel` near the top of the body.
- `app/controllers/cards_controller.rb` broadcasts after each successful `create`, `update`, `destroy`, and `reorder`.
- `app/controllers/swimlanes_controller.rb` broadcasts after each successful `create`, `update`, and `destroy`.
- `test/channels/board_channel_test.rb` covers: valid member accepted, non-member rejected, nil user rejected.
- `test/integration/cards_flow_test.rb` and `test/integration/swimlanes_flow_test.rb` each have dual assertions (HTTP response AND broadcast enqueued) for all write actions.
- `e2e/realtime.spec.js` has multi-context Playwright tests for the primary real-time scenarios.
- `AGENTS.md` and `README.md` updated.
- All existing Minitest and Playwright tests continue to pass. SimpleCov ≥ 80%.

**Verification command**:
```bash
bin/rails test && npx playwright test
```

## What We're NOT Doing

- Presence indicators or user avatars on the board
- "User is typing" / cursor tracking
- Activity feed / audit log
- Real-time membership change events (member added/removed)
- Drag-and-drop reorder position sync within a lane (card moves between lanes are in scope; reorder-within-lane sync is not)
- Push notifications or email triggers
- Redis / multi-server ActionCable setup (async adapter for dev is sufficient)
- Modifying `ApplicationCable::Connection` (it already handles unauthenticated rejection)

## Implementation Approach

**Broadcasts in controllers**: Each write action in `CardsController` and `SwimlanesController` calls `Turbo::StreamsChannel.broadcast_*_to(@board, ...)` after the successful save/update/destroy. This is explicit, easy to test with `assert_broadcasts` in integration tests, and avoids ActiveRecord-level coupling.

**`BoardChannel` inherits from `Turbo::StreamsChannel`**: Overrides `subscribed` to verify the signed stream name (provided by `turbo_stream_from` via the `channel:` option), extract the board record from its GID, check membership with `BoardMembership.exists?`, then call `stream_from` (allowed) or `reject` (denied). This reuses the signed-stream infrastructure already in turbo-rails and keeps the client-side subscription setup to a single view tag with no custom JavaScript.

**Two-layer auth**:
1. Connection level (`ApplicationCable::Connection`) — already rejects unauthenticated connections.
2. Channel level (`BoardChannel#subscribed`) — rejects non-members even if they have a valid session.

**Stream identifier**: `turbo_stream_from @board, channel: BoardChannel` generates a signed stream name from `@board`'s Global ID. The verified stream name (unsigned GID) is what `stream_from` registers. `Turbo::StreamsChannel.broadcast_*_to(@board, ...)` broadcasts to that same GID-based stream name automatically.

---

## Task 1: Create BoardChannel with Membership Authentication

### Overview
Create `app/channels/board_channel.rb` that inherits from `Turbo::StreamsChannel`, overrides `subscribed` to add membership gating, and write channel unit tests.

### Changes Required

**File**: `app/channels/board_channel.rb` *(new file)*

```ruby
class BoardChannel < Turbo::StreamsChannel
  def subscribed
    verified_stream_name = verify_stream_name(params[:signed_stream_name])
    return reject unless verified_stream_name

    board = GlobalID::Locator.locate(verified_stream_name)
    return reject unless board.is_a?(Board) && BoardMembership.exists?(board: board, user: current_user)

    stream_from verified_stream_name
  end
end
```

- `verify_stream_name` is inherited from `Turbo::StreamsChannel` — it verifies the HMAC signature and returns the raw stream name (board's GID string) or `nil`.
- `GlobalID::Locator.locate(verified_stream_name)` finds the Board record using its GID — no auth check here.
- `BoardMembership.exists?(board: board, user: current_user)` is the established Phase 4 membership check pattern. When `current_user` is `nil` (unauthenticated connection somehow reached here), this returns `false` and `reject` is called.
- `stream_from verified_stream_name` subscribes to the same stream that `Turbo::StreamsChannel.broadcast_*_to(@board, ...)` will broadcast to.

**File**: `test/channels/board_channel_test.rb` *(new file)*

```ruby
require "test_helper"

class BoardChannelTest < ActionCable::Channel::TestCase
  setup do
    @owner = User.create!(email_address: "owner@test.com", password: "pass1234", password_confirmation: "pass1234")
    @board = create_owned_board(@owner, name: "Test Board")
    @signed_stream_name = Turbo.signed_stream_verifier.generate(@board.to_gid_param)
  end

  test "member can subscribe" do
    stub_connection current_user: @owner
    subscribe signed_stream_name: @signed_stream_name
    assert_has_stream @board.to_gid_param
  end

  test "non-member subscription is rejected" do
    stranger = User.create!(email_address: "stranger@test.com", password: "pass1234", password_confirmation: "pass1234")
    stub_connection current_user: stranger
    subscribe signed_stream_name: @signed_stream_name
    assert_reject_subscription
  end

  test "nil user subscription is rejected" do
    stub_connection current_user: nil
    subscribe signed_stream_name: @signed_stream_name
    assert_reject_subscription
  end

  test "invalid signed stream name is rejected" do
    stub_connection current_user: @owner
    subscribe signed_stream_name: "tampered_value"
    assert_reject_subscription
  end
end
```

Note: `create_owned_board` is available via `session_test_helper.rb`'s `ActiveSupport.on_load` hook — verify it applies to `ActionCable::Channel::TestCase` or include the helper explicitly in this test file.

### Success Criteria
- [ ] `bin/rails test test/channels/board_channel_test.rb` — all 4 tests pass
- [ ] Member subscription accepted (stream registered)
- [ ] Non-member subscription rejected
- [ ] Nil user subscription rejected
- [ ] Invalid stream name rejected

---

## Task 2: Add `turbo_stream_from` to Board Show Page

### Overview
Add `turbo_stream_from @board, channel: BoardChannel` to `app/views/boards/show.html.erb` so browsers subscribe to the board's ActionCable stream via `BoardChannel` when the page loads.

### Changes Required

**File**: `app/views/boards/show.html.erb`

Add on line 2 (after the `is_owner` assignment, before the outer `<div>`):

```erb
<%= turbo_stream_from @board, channel: BoardChannel %>
```

This generates a `<turbo-cable-stream-source>` element that subscribes to `BoardChannel` with `{ signed_stream_name: signed_gid }` as params. The `channel: BoardChannel` option tells the Turbo JS client to use `BoardChannel` instead of the default `Turbo::StreamsChannel`.

### Success Criteria
- [ ] `bin/rails test` — all existing tests still pass (this change is non-functional for Minitest; it renders HTML only)
- [ ] Manual verification: open a board in the browser, check browser DevTools > Network > WS — a WebSocket connection is established to `/cable` and a subscription to `BoardChannel` is confirmed in the cable logs

---

## Task 3: Card Broadcasts in CardsController

### Overview
Add `Turbo::StreamsChannel.broadcast_*_to(@board, ...)` calls after each successful card write in `CardsController`: create, update, destroy, reorder. Add dual assertions (HTTP response + broadcast count) to the integration test file.

### Changes Required

**File**: `app/controllers/cards_controller.rb`

**`create` action** — after `@card.save` succeeds, before `respond_to`:
```ruby
Turbo::StreamsChannel.broadcast_append_to(
  @board,
  target: dom_id(@swimlane, :cards),
  partial: "cards/card",
  locals: { card: @card, board: @board, swimlane: @swimlane }
)
```

**`update` action** — after `@card.update(card_params)` succeeds, before `respond_to`:
```ruby
Turbo::StreamsChannel.broadcast_replace_to(
  @board,
  target: dom_id(@card, :face),
  partial: "cards/face",
  locals: { card: @card, board: @board, swimlane: @swimlane }
)
```

**`destroy` action** — after `@card.destroy`, before `respond_to`:
```ruby
Turbo::StreamsChannel.broadcast_remove_to(@board, target: dom_id(@card))
```

**`reorder` action** — capture old swimlane before the move; broadcast after:

Before `card.update!(swimlane_id: @swimlane.id)`:
```ruby
# (no variable needed — dom_id(card) is stable regardless of swimlane)
```

After `cards.each_with_index { |c, i| c.update_columns(position: i) }`, before `head :ok`:
```ruby
Turbo::StreamsChannel.broadcast_remove_to(@board, target: dom_id(card))
Turbo::StreamsChannel.broadcast_append_to(
  @board,
  target: dom_id(@swimlane, :cards),
  partial: "cards/card",
  locals: { card: card, board: @board, swimlane: @swimlane }
)
```

Note: `broadcast_remove_to(@board, target: dom_id(card))` removes the card element from wherever it currently appears in any subscriber's DOM. `broadcast_append_to` then appends the fresh card to the destination swimlane's cards container.

**File**: `test/integration/cards_flow_test.rb`

Add a `# --- Phase 5: broadcasts ---` section with these tests:

```ruby
test "card create broadcasts to board stream" do
  assert_broadcasts @board.to_gid_param, 1 do
    post board_swimlane_cards_path(@board, @swimlane),
         params: { card: { name: "Broadcast Card" } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
  end
  assert_response :success
end

test "card update broadcasts to board stream" do
  card = @swimlane.cards.create!(name: "Old Name")
  assert_broadcasts @board.to_gid_param, 1 do
    patch board_swimlane_card_path(@board, @swimlane, card),
          params: { card: { name: "New Name" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
  end
  assert_response :success
end

test "card destroy broadcasts to board stream" do
  card = @swimlane.cards.create!(name: "Doomed")
  assert_broadcasts @board.to_gid_param, 1 do
    delete board_swimlane_card_path(@board, @swimlane, card),
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
  end
  assert_response :success
end

test "card reorder broadcasts remove and append to board stream" do
  card = @swimlane.cards.create!(name: "Mover")
  lane2 = @board.swimlanes.create!(name: "Done")
  assert_broadcasts @board.to_gid_param, 2 do
    patch reorder_board_swimlane_cards_path(@board, lane2),
          params: { card_id: card.id, position: 0 },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
  end
  assert_response :success
end
```

### Success Criteria
- [ ] `bin/rails test test/integration/cards_flow_test.rb` — all tests pass (including new broadcast tests)
- [ ] `assert_broadcasts @board.to_gid_param, 1` passes for create, update, destroy
- [ ] `assert_broadcasts @board.to_gid_param, 2` passes for reorder (remove + append)
- [ ] No existing card tests regress

---

## Task 4: Swimlane Broadcasts in SwimlanesController

### Overview
Add broadcasts after each successful swimlane write in `SwimlanesController`: create, update, destroy. Add dual assertions to the swimlanes integration test.

### Changes Required

**File**: `app/controllers/swimlanes_controller.rb`

**`create` action** — after `@swimlane.save` succeeds, before `respond_to`:
```ruby
Turbo::StreamsChannel.broadcast_append_to(
  @board,
  target: "swimlanes",
  partial: "swimlanes/swimlane",
  locals: { swimlane: @swimlane, board: @board }
)
```

**`update` action** — after `@swimlane.update(swimlane_params)` succeeds, before `respond_to`:
```ruby
Turbo::StreamsChannel.broadcast_replace_to(
  @board,
  target: dom_id(@swimlane, :header),
  partial: "swimlanes/header",
  locals: { swimlane: @swimlane, board: @board }
)
```

**`destroy` action** — after `@swimlane.destroy`, before `respond_to`:
```ruby
Turbo::StreamsChannel.broadcast_remove_to(@board, target: dom_id(@swimlane))
```

**File**: `test/integration/swimlanes_flow_test.rb`

Add a `# --- Phase 5: broadcasts ---` section:

```ruby
test "swimlane create broadcasts to board stream" do
  assert_broadcasts @board.to_gid_param, 1 do
    post board_swimlanes_path(@board),
         params: { swimlane: { name: "Broadcast Lane" } },
         headers: { "Accept" => "text/vnd.turbo-stream.html" }
  end
  assert_response :success
end

test "swimlane update broadcasts to board stream" do
  swimlane = @board.swimlanes.create!(name: "Old Name")
  assert_broadcasts @board.to_gid_param, 1 do
    patch board_swimlane_path(@board, swimlane),
          params: { swimlane: { name: "New Name" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
  end
  assert_response :success
end

test "swimlane destroy broadcasts to board stream" do
  swimlane = @board.swimlanes.create!(name: "Doomed Lane")
  assert_broadcasts @board.to_gid_param, 1 do
    delete board_swimlane_path(@board, swimlane),
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
  end
  assert_response :success
end
```

### Success Criteria
- [ ] `bin/rails test test/integration/swimlanes_flow_test.rb` — all tests pass
- [ ] Broadcast assertions confirm 1 broadcast each for create, update, destroy
- [ ] No existing swimlane tests regress

---

## Task 5: E2E Helper Update (signInAs alias)

### Overview
Add a non-breaking `signInAs` alias to `e2e/helpers/auth.js` so Phase 5 specs can use the SPEC-required name without breaking existing specs that use `signIn`.

### Changes Required

**File**: `e2e/helpers/auth.js`

Add at end of file:
```js
export const signInAs = signIn;
```

No other changes. Existing specs (`board_sharing.spec.js`, etc.) continue to import and use `signIn` unchanged.

**File**: `e2e/realtime.spec.js` *(new file — stub only at this step)*

Create with just the imports to verify the alias resolves:
```js
import { test, expect } from "@playwright/test";
import { signInAs, signUp, uniqueEmail, createBoard, PASSWORD } from "./helpers/auth.js";
```

### Success Criteria
- [ ] `npx playwright test e2e/board_sharing.spec.js` — all existing sharing tests still pass
- [ ] `signInAs` is importable from `./helpers/auth.js` without error

---

## Task 6: E2E Real-Time Collaboration Tests

### Overview
Write `e2e/realtime.spec.js` with multi-context Playwright tests covering the primary real-time scenarios. Uses the `browser.newContext()` pattern from `board_sharing.spec.js`.

### Changes Required

**File**: `e2e/realtime.spec.js` *(complete implementation)*

Tests to implement:

1. **Card created by owner appears for collaborator** — owner creates a card; collaborator's page shows the card without navigation.
2. **Card deleted by owner disappears for collaborator** — owner deletes a card; collaborator's page no longer shows it.
3. **Card moved between swimlanes** — owner moves a card from lane 1 to lane 2; collaborator sees card leave lane 1 and appear in lane 2.
4. **Swimlane created by owner appears for collaborator** — owner creates a swimlane; collaborator sees the new column.
5. **Swimlane deleted by owner disappears for collaborator** — owner deletes a swimlane; collaborator sees the column removed.

**Setup pattern** (reuse from `board_sharing.spec.js`):
```js
test.describe("Real-time collaboration", () => {
  test("owner creates card; collaborator sees it without reload", async ({ browser }) => {
    const ownerCtx = await browser.newContext();
    const collabCtx = await browser.newContext();
    const ownerPage = await ownerCtx.newPage();
    const collabPage = await collabCtx.newPage();

    const ownerEmail = uniqueEmail("rt_owner");
    const collabEmail = uniqueEmail("rt_collab");

    await signUp(ownerPage, ownerEmail);
    await signUp(collabPage, collabEmail);

    // Owner creates board and adds collaborator
    await createBoard(ownerPage, "RT Board");
    await ownerPage.fill('[placeholder="user@example.com"]', collabEmail);
    await ownerPage.click('#membership_form [type="submit"]');

    // Owner adds a swimlane
    await ownerPage.fill('[placeholder="Lane name..."]', "Todo");
    await ownerPage.click('[type="submit"][value="Add Lane"]');
    await expect(ownerPage.locator("text=Todo")).toBeVisible();

    // Collaborator navigates to the board and stays on it
    await collabPage.goto("/");
    await collabPage.click('a:has-text("RT Board")');
    await collabPage.waitForURL(/\/boards\/\d+/);

    // Owner creates a card — collaborator should see it appear
    await ownerPage.fill('[placeholder="Add a card..."]', "Live Card");
    await ownerPage.click('[type="submit"][value="Add"]');

    await expect(collabPage.locator("text=Live Card")).toBeVisible();

    await ownerCtx.close();
    await collabCtx.close();
  });
  // ... additional tests following same pattern
});
```

**Key assertions pattern for real-time**: Use `await expect(collabPage.locator("text=...")).toBeVisible()` — Playwright's auto-waiting handles the WebSocket latency.

For card delete: `await expect(collabPage.locator("text=...")).not.toBeVisible()`.

For card move between swimlanes: assert card NOT in source lane container + IS in dest lane container using `locator()` with parent constraint.

For swimlane delete: `await expect(collabPage.locator(`[id="swimlane_${id}"]`)).not.toBeVisible()`.

### Success Criteria
- [ ] `npx playwright test e2e/realtime.spec.js` — all real-time E2E tests pass
- [ ] Multi-context tests confirm live updates without `page.reload()`
- [ ] Full Playwright suite passes: `npx playwright test`

---

## Task 7: Documentation Updates

### Overview
Update `AGENTS.md` project structure section and `README.md` feature list. These are explicit checklist items, not implied.

### Changes Required

**File**: `AGENTS.md`

In the project structure section under `app/channels/`:
- Add entry: `app/channels/board_channel.rb` — BoardChannel; inherits from Turbo::StreamsChannel; overrides subscribed to verify board membership before streaming; non-members (and nil users) are rejected
- Add entry for `app/channels/application_cable/connection.rb` if not already listed — authenticates WebSocket connections via session cookie; rejects unauthenticated connections

Add or update a "ActionCable Authentication" section:
- Connection-level: `ApplicationCable::Connection` reads `cookies.signed[:session_id]`, finds the Session record, sets `current_user`; rejects if no session
- Channel-level: `BoardChannel#subscribed` verifies the signed stream name (HMAC-protected GID), locates the Board, checks `BoardMembership.exists?`, rejects non-members
- Broadcast callbacks live in controllers (`CardsController`, `SwimlanesController`) — called after each successful write via `Turbo::StreamsChannel.broadcast_*_to(@board, ...)`

**File**: `README.md`

- Mark Phase 5 complete in the feature list
- Add: "Changes to cards and swimlanes are broadcast live to all board members via ActionCable"

### Success Criteria
- [ ] `AGENTS.md` top-level project structure lists `app/channels/board_channel.rb`
- [ ] `AGENTS.md` has ActionCable auth section documenting both layers and broadcast approach
- [ ] `README.md` Phase 5 marked complete with real-time collaboration description

---

## Self-Review Checklist (Before Commit)

Per Phase 4 lessons — verify each item against this plan before committing:

- [ ] `BoardChannel` uses `BoardMembership.exists?` (not `@board.members.include?`)
- [ ] All 4 write actions in CardsController have broadcast calls
- [ ] All 3 write actions in SwimlanesController have broadcast calls
- [ ] Integration tests assert BOTH HTTP response AND broadcast count
- [ ] `turbo_stream_from` uses `channel: BoardChannel` (not default)
- [ ] `signInAs` alias added; existing specs unchanged
- [ ] AGENTS.md project structure AND auth section both updated (two separate checks)
- [ ] README.md Phase 5 marked complete

---

## Testing Strategy

### Unit Tests (Channel)
- `test/channels/board_channel_test.rb` — `ActionCable::Channel::TestCase`
- Test: member accepted, non-member rejected, nil user rejected, invalid stream name rejected
- Use `stub_connection current_user: user` to set channel identity
- Use `Turbo.signed_stream_verifier.generate(@board.to_gid_param)` to generate valid signed stream names

### Integration Tests (Controllers)
- `test/integration/cards_flow_test.rb` and `test/integration/swimlanes_flow_test.rb`
- Each write action test: `assert_broadcasts @board.to_gid_param, N do ... end` + `assert_response :success`
- Reorder gets `assert_broadcasts ..., 2` (remove + append = 2 broadcasts)
- Existing tests unchanged — broadcasts are additive side effects, not response changes

### E2E Tests (Playwright)
- `e2e/realtime.spec.js` — multi-context pattern from `board_sharing.spec.js`
- 5 scenarios: card create, card delete, card move, swimlane create, swimlane delete
- All use `signInAs` (alias of `signIn`)
- Use Playwright's auto-waiting (`toBeVisible`, `not.toBeVisible`) — no `page.waitForTimeout`

### Regression
- `bin/rails test` — all Phase 1–4 tests pass unchanged
- `npx playwright test` — all existing E2E specs pass

## Risk Assessment

- **`ActionCable::Channel::TestCase` + session_test_helper**: The `create_owned_board` helper is loaded via `ActiveSupport.on_load` hook for `ActionDispatch::IntegrationTest`. It may not auto-load for `ActionCable::Channel::TestCase`. **Mitigation**: In `board_channel_test.rb`, add `include SessionTestHelper` explicitly if `create_owned_board` is not available — or inline the board setup.

- **`turbo_stream_from @board, channel: BoardChannel` client support**: The `channel:` option requires turbo-rails ≥ 7.x. **Mitigation**: `Gemfile:14` confirms `gem "turbo-rails"` is present; Rails 8 ships with a compatible version. Verify after Task 2 that the HTML output includes `channel="BoardChannel"`.

- **Idempotent card update broadcast**: The requesting user receives the broadcast AND the HTTP Turbo Stream response — both replace the same `dom_id(card, :face)`. Replacing already-current HTML is safe (no flicker in practice). No mitigation needed per SPEC.

- **Reorder broadcast timing**: The `reorder` action calls `update_columns` (bypasses callbacks, faster), then broadcasts. If the broadcast renders the `_card` partial before `update_columns` completes for all cards, position could be stale — but position is not rendered in `_card`, only `swimlane_id` matters for placement. No issue.

- **E2E WebSocket timing**: ActionCable WebSocket establishment takes ~100–500ms in test mode. Playwright's default timeout (30s) is more than sufficient. If flaky, wrap the collab page navigation with `waitForURL` before the owner action.
