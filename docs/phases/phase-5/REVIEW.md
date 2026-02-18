# Phase Review: Phase 5

## Overall Verdict

**NEEDS-FIX** — 1 spec compliance gap (missing E2E test), 1 minor API deviation, 1 test style gap. See MUST-FIX.md.

---

## Code Quality Review

### Summary

Strong implementation. The core ActionCable plumbing is correct — `BoardChannel` authenticates at both the connection and channel layer, broadcasts fire from controllers after each successful write, and the `turbo_stream_from` subscription tag is in place. All 129 Minitest tests pass, coverage is 87.8% (above the 80% floor). The main concern is a minor API deviation in `BoardChannel` and an unhandled destroy-failure edge in both controllers.

### Findings

1. **API Deviation — `verify_stream_name` bypassed**: The plan specified calling `verify_stream_name(params[:signed_stream_name])`, the inherited `Turbo::StreamsChannel` method, to verify the HMAC signature. The implementation calls `Turbo.signed_stream_verifier.verified(params[:signed_stream_name])` directly — the underlying method — bypassing the channel's own abstraction. Functionally equivalent today, but if Turbo changes its internal verifier API, `BoardChannel` would break silently while the rest of the channel's `subscribed` logic would not. — `app/channels/board_channel.rb:3`

2. **Unguarded destroy before broadcast — CardsController**: `@card.destroy` is called without checking its return value before broadcasting. If `destroy` returns `false` (e.g., a before-destroy callback halts the chain), the broadcast still fires, telling all subscribers the card is gone — but the card still exists in the database. — `app/controllers/cards_controller.rb:69-70`

3. **Unguarded destroy before broadcast — SwimlanesController**: Same pattern: `@swimlane.destroy` result is not checked before `broadcast_remove_to`. — `app/controllers/swimlanes_controller.rb:68-69`

4. **Broadcast fires on every destroy regardless of outcome**: Both issues above are low risk in the current app (no destroy callbacks are in place), but they create a latent bug that would be hard to diagnose if model callbacks are added in a later phase.

### Spec Compliance Checklist

- [x] `BoardChannel` exists, inherits from `Turbo::StreamsChannel`, overrides `subscribed`
- [x] Channel-level auth uses `BoardMembership.exists?` (not `@board.members.include?`)
- [x] Non-member subscriptions are rejected
- [x] Unauthenticated connections rejected at channel level (nil user → false from `BoardMembership.exists?`)
- [x] `turbo_stream_from @board, channel: BoardChannel` on board show page
- [x] Card create broadcast (append to swimlane cards container)
- [x] Card update broadcast (replace card face)
- [x] Card destroy broadcast (remove card element)
- [x] Card move broadcast (remove from source lane + append to destination lane)
- [x] Swimlane create broadcast (append to swimlanes container)
- [x] Swimlane update broadcast (replace swimlane header)
- [x] Swimlane destroy broadcast (remove swimlane element)
- [x] Requesting user also receives broadcast (idempotent HTML replace — acknowledged safe in SPEC)
- [x] `signInAs` alias added to `e2e/helpers/auth.js`
- [x] AGENTS.md updated with ActionCable auth section and Phase 5 channels entry
- [x] README.md Phase 5 marked complete with real-time collaboration description
- [ ] E2E: owner moves card between swimlanes; collaborator sees move without reload — **NOT IMPLEMENTED** (SPEC §Acceptance Criteria, PLAN §Task 6)

---

## Adversarial Test Review

### Summary

**Adequate** for unit and integration layers; **weak** for E2E coverage. The channel unit tests are solid, covering the four required auth scenarios. Integration broadcast tests are well-structured with dual assertions (HTTP response + broadcast count). The E2E suite covers 4 of 5 required scenarios — card move is absent.

### Findings

1. **Missing E2E test — card move between swimlanes**: The SPEC explicitly lists "Owner moves a card to a different swimlane; collaborator sees the card in the new lane without reload" as an E2E acceptance criterion. The PLAN (Task 6) lists it as one of 5 required scenarios. Only 4 tests exist in `e2e/realtime.spec.js`. — `e2e/realtime.spec.js` (missing test)

2. **Non-semantic rejection assertions in channel tests**: The plan recommended `assert_reject_subscription` (the idiomatic ActionCable channel test helper). The implementation uses `assert subscription.rejected?` (raw subscription object inspection). Both pass, but `assert_reject_subscription` provides a more readable failure message if the assertion ever fails. — `test/channels/board_channel_test.rb:22, 28, 33`

3. **No negative broadcast test — failed save does not broadcast**: Integration tests assert that a *successful* create/update/destroy enqueues a broadcast. There is no test asserting that a *failed* save (e.g., blank card name) does NOT enqueue a broadcast. This gap is acceptable today (validation prevents the broadcast path entirely), but worth noting. — `test/integration/cards_flow_test.rb`

4. **No E2E test — non-member cannot subscribe**: SPEC acceptance criterion: "A user who is not a board member cannot subscribe to that board's ActionCable stream (connection rejected at subscription)." The Minitest channel test covers this, but no E2E test verifies the rejection at the browser/network level. — `e2e/realtime.spec.js` (missing test; lower priority than card move)

5. **E2E card delete selector fragility**: The delete test locates the card's delete button with `card.locator('button').click()`. If a card gains more than one button, this will click the first — not necessarily delete. — `e2e/realtime.spec.js:87`

6. **`assert_broadcasts` count for swimlane create could include 2**: The swimlane create integration test asserts exactly 1 broadcast. Correct for current implementation, but the `broadcast_append_to` for swimlane create appends the full `_swimlane` partial. If in a future phase a second broadcast is added to the create action, this test will catch the regression. Current count is accurate.

### Test Coverage

- **Line coverage**: 87.8% (288/328 lines) — above 80% floor ✓
- **Channel unit**: 4/4 scenarios covered (member accept, non-member reject, nil user reject, invalid stream name reject) ✓
- **Integration broadcast**: 7/7 write actions have `assert_broadcasts` dual assertions (card: create/update/destroy/reorder; swimlane: create/update/destroy) ✓
- **E2E real-time**: 4/5 SPEC-required scenarios (missing: card move between swimlanes) ✗

### Missing Test Cases

- Card move between swimlanes — collaborator sees card leave source lane and appear in destination lane (required by SPEC and PLAN)
- Failed card save does not enqueue a broadcast (gap, not critical)
- Non-member E2E WebSocket rejection verification (gap, lower priority)
