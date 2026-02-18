# Must-Fix Items: Phase 5

## Summary

3 issues found: 1 critical (missing E2E spec compliance), 1 minor (API deviation), 1 minor (unguarded destroy broadcasts).

---

## Tasks

### Task 1: Add missing E2E test — card move between swimlanes

**Priority:** Critical
**Files:** `e2e/realtime.spec.js`
**Problem:** The SPEC requires an E2E test: "Owner moves a card to a different swimlane; collaborator sees the card in the new lane without reload." The PLAN (Task 6, scenario 3) explicitly lists this. The test is absent — only 4 of 5 required E2E scenarios are implemented.

**Status:** ✅ Fixed
**What was done:** Added a fifth test "owner moves card between swimlanes; collaborator sees move" to `e2e/realtime.spec.js`. The test signs up owner and collaborator, creates two swimlanes (Lane A, Lane B) and a card "Move Me" in Lane A, then collaborator navigates to the board. Owner moves the card via `ownerPage.request.patch(...)` to Lane B (CSRF token not needed — `allow_forgery_protection = false` in test env). The collaborator's page asserts card not visible in `#cards_swimlane_<laneAId>` and visible in `#cards_swimlane_<laneBId>`. All 5 realtime tests now pass.

---

### Task 2: Use `verify_stream_name` instead of accessing the verifier directly

**Priority:** Minor
**Files:** `app/channels/board_channel.rb:3`
**Problem:** The implementation calls `Turbo.signed_stream_verifier.verified(params[:signed_stream_name])` directly. The plan specified `verify_stream_name(params[:signed_stream_name])`, the private method inherited from `Turbo::StreamsChannel`.

**Status:** ❌ Could not fix
**Reason:** `verify_stream_name` does not exist in turbo-rails 2.0.23 (the installed version). Confirmed by checking `Turbo::StreamsChannel.private_instance_methods.grep(/verify/)` — returns empty. The method was proposed in the PLAN based on documentation that does not match the actual gem version. The current implementation using `Turbo.signed_stream_verifier.verified(...)` is correct and all 4 channel tests pass. This is the only working approach available.

---

### Task 3: Guard destroy broadcasts behind a successful destroy check

**Priority:** Minor
**Files:** `app/controllers/cards_controller.rb:68-74`, `app/controllers/swimlanes_controller.rb:67-73`
**Problem:** Both `destroy` actions broadcast removal unconditionally, even if `destroy` returns `false`.

**Status:** ✅ Fixed
**What was done:** Wrapped the broadcast and response in `if @card.destroy` / `if @swimlane.destroy` blocks in both controllers. The failure branch for cards renders a turbo_stream replace of the card partial (status 422). The failure branch for swimlanes renders `head :unprocessable_entity`. All 129 Minitest tests continue to pass.
