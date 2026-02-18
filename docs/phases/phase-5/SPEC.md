# Phase 5: Real-Time Collaboration via ActionCable

## Objective
Phase 5 makes Swimlanes a live collaborative tool. When any board member creates, updates, moves, or deletes a card or swimlane, all other members currently viewing that board see the change appear instantly — no page reload required. This is delivered via ActionCable broadcasting Turbo Streams to a membership-scoped channel. The result is verifiable: two browser sessions on the same board, one user makes a change, the other sees it without any action on their part.

## Scope

### In Scope
- **ActionCable channel** (`BoardChannel`) authenticated to board members only — non-members are rejected at subscription time
- **Card real-time events**: card created, updated (title/description/due date/labels), deleted, and moved between swimlanes broadcast to all board members
- **Swimlane real-time events**: swimlane created, updated (name), and deleted broadcast to all board members
- **Broadcast on model change**: callbacks or service objects that trigger broadcasts after each card/swimlane write operation
- **`turbo_stream_from` tag** on the board show page to subscribe the browser to the board's ActionCable stream
- **Channel authentication** using the session cookie — `Current.user` equivalent in the channel context; reject unauthenticated or non-member connections

### Out of Scope
- Presence indicators ("2 users online", user avatars on the board)
- "User is typing" / optimistic UI cursor tracking
- Activity feed / audit log of who changed what
- Real-time membership change events (member added/removed appearing live) — lower value, deferred
- Drag-and-drop reorder broadcasting (position sync is complex; moves between swimlanes are in scope but ordered reorder-within-lane sync is not)
- Push notifications or emails triggered by changes

## Requirements
- A `BoardChannel` exists; it authenticates the subscriber using the session cookie and verifies the user is a member of the requested board via `Board.accessible_by(user)`; non-members are rejected with a `reject` call
- The board show page includes `<%= turbo_stream_from @board %>` (or equivalent signed stream tag) so the browser establishes a WebSocket subscription when the page loads
- After a card is created, the new card HTML is broadcast to the board stream; all subscribed clients append it to the correct swimlane column without a page reload
- After a card is updated (any attribute), the updated card HTML is broadcast; all subscribed clients replace the card in place
- After a card is deleted, a broadcast removes the card from all subscribed clients
- After a card is moved to a different swimlane, the card is removed from the source swimlane and appended to the destination swimlane on all subscribed clients
- After a swimlane is created, the new swimlane column HTML is broadcast; all subscribed clients append it to the board
- After a swimlane is updated (name), the updated swimlane header is broadcast; all subscribed clients replace it in place
- After a swimlane is deleted, a broadcast removes the swimlane column from all subscribed clients
- The user who triggered the change also receives the broadcast update (idempotent — replacing HTML that was already updated by the HTTP response is safe)
- No existing Minitest or Playwright tests are broken by the addition of broadcast callbacks

## Acceptance Criteria
- [ ] Opening a board in two separate browser sessions (two different logged-in users, both board members) establishes a live WebSocket connection to `BoardChannel`
- [ ] User A creates a card in a swimlane; User B sees the card appear in their browser without reloading the page
- [ ] User A updates a card's title; User B sees the updated title replace the old one without reloading
- [ ] User A deletes a card; User B sees the card disappear without reloading
- [ ] User A moves a card from swimlane 1 to swimlane 2; User B sees the card leave swimlane 1 and appear in swimlane 2 without reloading
- [ ] User A creates a new swimlane; User B sees the new column appear without reloading
- [ ] User A renames a swimlane; User B sees the updated name without reloading
- [ ] User A deletes a swimlane; User B sees the column removed without reloading
- [ ] A user who is not a board member cannot subscribe to that board's ActionCable stream (connection rejected at subscription)
- [ ] An unauthenticated WebSocket connection (no valid session) is rejected
- [ ] All existing Minitest tests continue to pass
- [ ] SimpleCov coverage remains at or above 80%
- [ ] All tests pass

## Testing Strategy
- **Minitest** for unit and channel tests:
  - **Unit — `BoardChannel`**: `subscribe` with a valid board member is accepted; `subscribe` with a non-member is rejected; `subscribe` with no authenticated user is rejected
  - **Unit — Broadcast helpers / callbacks**: after `Card.create`, a Turbo Stream broadcast is enqueued targeting the board stream; verify using `assert_broadcasts` or mock assertions; same for card update, delete, move; same for swimlane create, update, delete
  - **Integration — Cards controller**: POST `/boards/:id/swimlanes/:id/cards` still returns a successful response AND enqueues a broadcast; verify both the HTTP response AND the broadcast side effect
  - **Integration — Swimlanes controller**: same dual assertion for create/update/delete
  - **Regression**: all Phase 1–4 integration tests continue to pass unchanged
- **Playwright E2E**:
  - E2E: Two browser contexts (owner + collaborator) both open the same board; owner creates a card; assert the card appears in the collaborator's page without any navigation
  - E2E: Owner moves a card to a different swimlane; collaborator sees the card in the new lane without reload
  - E2E: Owner deletes a swimlane; collaborator sees the column disappear without reload
  - E2E: Non-member attempts to open the board URL; no WebSocket connection is established (verify via network tab or ActionCable rejection)
- **E2E helper design**: Before writing E2E specs, define a `signInAs(page, email, password)` helper function that the specs will share. Do not import helpers that are not used.
- **Coverage**: SimpleCov must stay at or above 80%; broadcast and channel code paths are covered

## Documentation Updates
- **AGENTS.md**:
  - Add `BoardChannel` to the project structure section under `app/channels/`
  - Document how ActionCable is authenticated (session cookie + `Board.accessible_by` check)
  - Note that broadcast callbacks live in models or after-action service objects (document the chosen approach)
  - Add the project structure entry for any new files (`app/channels/board_channel.rb`, `app/channels/application_cable/connection.rb` if modified)
- **README.md**:
  - Mark Phase 5 complete in the feature list
  - Add a sentence describing real-time collaboration: "Changes to cards and swimlanes are broadcast live to all board members via ActionCable"

## Dependencies
- Phases 1–4 complete and all tests passing
- ActionCable is included in Rails 8 by default; no new gems required
- `turbo-rails` gem already provides `Turbo::StreamsChannel` and `turbo_stream_from` helper — verify it's in the Gemfile (it ships with Rails 8 / Hotwire)
- Playwright already configured from earlier phases; no new E2E infrastructure needed
- No external services (no Redis required for ActionCable in development with the async adapter; verify `config/cable.yml` uses `async` for development)

## Adjustments from Previous Phase

Based on Phase 4 REFLECTIONS.md:

1. **Verify ActionCable channel auth before building any UI**: Phase 4 reflections flagged session-cookie WebSocket auth as the hard problem. The very first task must be a minimal `BoardChannel` that authenticates and rejects connections — prove it works before adding any broadcast logic.
2. **Design E2E helpers before writing specs**: Phase 4's unused `signIn` import came from writing specs without resolving the helper interface first. Define `signInAs(page, email, password)` once in a shared helper file; reference it in every spec.
3. **Check plan deviations before committing**: Phase 4's `@board.members.include?(user)` deviation from the plan went unnoticed until review. Build step must include a self-review checklist against the plan before any commit.
4. **Dual assertions in integration tests**: Phase 4 showed that asserting only the HTTP response leaves broadcast side effects untested. Integration tests for all write actions must assert both the response status AND the broadcast was enqueued.
5. **Documentation as a checklist item, not an afterthought**: AGENTS.md project structure section went stale in Phase 4. Add explicit sub-tasks: "Update AGENTS.md channels section" and "Update README.md feature list" — both must be verified complete before the commit step.
6. **Narrow scope first, expand after**: Start with card events through the full ActionCable stack (channel → broadcast → client update) before adding swimlane events. Don't attempt to real-time everything in parallel.
