# Reflections: Phase 5

## Looking Back

### What Went Well

- **Core ActionCable plumbing was correct on the first pass**: `BoardChannel` authenticated at both connection and channel layers, all 7 broadcast calls (4 card + 3 swimlane) landed in controllers as planned, and the `turbo_stream_from` subscription tag worked. The two-layer auth design (Connection rejects unauthenticated, BoardChannel rejects non-members) was clean and verifiable.
- **Dual assertions held up in integration tests**: Every write action test asserts both HTTP response status AND broadcast count via `assert_broadcasts`. This pattern caught nothing unexpected in Phase 5, but it's the right habit and will matter when regressions happen.
- **Coverage stayed strong**: 87.8% line coverage (288/328 lines), comfortably above the 80% floor.
- **Multi-context Playwright pattern reused cleanly**: The `browser.newContext()` pattern from `board_sharing.spec.js` transferred directly to `realtime.spec.js` with no friction.
- **Channel unit tests were comprehensive**: All 4 auth scenarios covered (member accept, non-member reject, nil user reject, invalid stream name reject).
- **`signInAs` alias was non-breaking**: Adding `export const signInAs = signIn` at the end of `auth.js` was exactly the right scope — no existing specs needed to change.

### What Didn't Work

- **Plan referenced a non-existent API (`verify_stream_name`)**: The PLAN specified calling `verify_stream_name(params[:signed_stream_name])`, described as an inherited `Turbo::StreamsChannel` method. This method does not exist in turbo-rails 2.0.23. The implementation correctly used `Turbo.signed_stream_verifier.verified(...)` instead, but only because the build step discovered the discrepancy by running the tests — not because the plan was researched against the actual gem version. The RESEARCH step should have verified the turbo-rails API surface before the PLAN committed to specific method names.
- **E2E card move test was missed**: The SPEC and PLAN both explicitly listed "owner moves card between swimlanes; collaborator sees move" as a required E2E scenario. It was not implemented in the initial build, flagged in REVIEW, and fixed in MUST-FIX. This is the same class of omission as Phase 4's unused import — a spec checklist item that wasn't tracked to completion during the build step.
- **Unguarded destroy broadcasts**: Both `CardsController#destroy` and `SwimlanesController#destroy` broadcast removal unconditionally, regardless of whether `destroy` returned `false`. Fixed in MUST-FIX by wrapping the broadcast in `if @card.destroy` / `if @swimlane.destroy` blocks. The risk was low (no current destroy callbacks) but the pattern was fragile.

### Spec vs Reality

- **Delivered as spec'd**: `BoardChannel` with two-layer auth; `turbo_stream_from @board, channel: BoardChannel`; card create/update/destroy/move broadcasts; swimlane create/update/destroy broadcasts; `signInAs` alias; AGENTS.md and README.md updated; all 129 Minitest tests pass; SimpleCov ≥ 80%; E2E card create, delete, swimlane create, swimlane delete real-time scenarios.
- **Deviated from spec**: `verify_stream_name` plan call replaced by `Turbo.signed_stream_verifier.verified(...)` — functionally equivalent, documented in MUST-FIX as not fixable given the installed gem version. Channel tests use `assert subscription.rejected?` instead of `assert_reject_subscription` — passes but less idiomatic.
- **Deferred**: Non-member E2E WebSocket rejection verification (channel test covers this; E2E network-level verification remains a gap, noted in REVIEW as lower priority). Negative broadcast test for failed saves.

### Review Findings Impact

- **Missing E2E card move test**: Fixed in MUST-FIX. Fifth scenario added to `e2e/realtime.spec.js` using the API-direct `ownerPage.request.patch(...)` approach (CSRF forgery protection disabled in test env).
- **Unguarded destroy broadcasts**: Fixed in MUST-FIX. Both controllers now guard broadcasts behind a truthy `destroy` result.
- **`verify_stream_name` API deviation**: Could not be fixed — method does not exist in the installed turbo-rails version. Documented in MUST-FIX as an unfixable plan inaccuracy; current implementation is correct.
- **Non-semantic `assert subscription.rejected?`**: Noted but not changed. Low-value fix with no behavioral impact.

---

## Looking Forward

### Recommendations for Next Phase

- **Research gem API surfaces before writing the plan**: Phase 5's plan cited a `verify_stream_name` method that doesn't exist in turbo-rails 2.0.23. Before specifying a method call in a plan, the RESEARCH step should confirm it exists with `grep` or `bundle exec rails runner 'puts ClassName.instance_methods.grep(/pattern/)'`. One check catches this class of error entirely.
- **Build-step E2E checklist**: Two phases in a row (4 and 5) had a spec compliance gap in E2E tests that only surfaced at REVIEW. The build step should include a literal line-by-line pass through the SPEC's Acceptance Criteria section, checking each criterion off before declaring the build complete.
- **Phase 6 has no ActionCable surface**: Board backgrounds are pure CRUD (color/gradient selection stored on the Board model, rendered in CSS). No broadcast complexity. Phase 6 should be straightforward compared to Phase 5.

### What Should Next Phase Build?

**Phase 6: Board Background Customization (colors and gradients)**

The only remaining BRIEF.md feature is:
> Board Backgrounds — Customizable board backgrounds with colors and gradients (no image uploads)

Scope for Phase 6:
- Add a `background` column to `boards` (string, nullable) storing a CSS value: a hex color or gradient expression (e.g. `"#1e3a5f"`, `"linear-gradient(135deg, #1e3a5f, #4a9eff)"`)
- UI: a background picker on the board show page or board edit form — a palette of preset color/gradient options, selectable without a full page reload (Turbo Stream or Stimulus)
- Apply the stored background as an inline style or CSS class on the board container element
- No image uploads — limit choices to a curated preset list
- Tests: integration test for `update` action (background saved), Minitest assertion that the board renders with the correct background value, one Playwright E2E verifying the board background updates visually
- Documentation: AGENTS.md and README.md updated; Phase 6 marked complete

This is the final phase of the MVP. Once Phase 6 ships, all 8 BRIEF.md features are complete.

### Technical Debt Noted

- **`Turbo.signed_stream_verifier.verified(...)` is a private/undocumented API**: `app/channels/board_channel.rb:3`. This works today but bypasses the public channel abstraction. If turbo-rails ever changes its internal verifier structure, this will break. Worth revisiting when turbo-rails is upgraded.
- **E2E card move uses API-direct `request.patch`**: `e2e/realtime.spec.js` (card move test). This bypasses the UI and tests the broadcast mechanism, not the full user workflow. A future improvement would be a real drag-and-drop simulation, but SortableJS makes that hard with Playwright. Acceptable for now.
- **Non-semantic rejection assertions**: `test/channels/board_channel_test.rb:22, 28, 33` — `assert subscription.rejected?` instead of `assert_reject_subscription`. Low priority.

### Process Improvements

- **RESEARCH step must grep the actual gem source** before the PLAN cites specific method names. One `grep` command against `$(bundle show turbo-rails)` prevents phantom API references.
- **Build step should treat the SPEC Acceptance Criteria as a literal checklist**: Print it, check each item off with evidence (test name or output), don't proceed to commit until every box is ticked.
- **MUST-FIX is working well**: The review → must-fix → fix loop caught and resolved 2 of 3 issues. The pattern is healthy; keep it.
