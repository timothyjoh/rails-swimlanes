# Phase Review: Phase 1

## Overall Verdict
NEEDS-FIX — see MUST-FIX.md

---

## Code Quality Review

### Summary
The implementation is solid overall. The Rails 8 app is correctly scaffolded, authentication is wired up properly via the built-in generator with a manual RegistrationsController added, and Board CRUD is complete with user-scoped authorization. The schema, models, controllers, views, and routing are all coherent and follow Rails conventions well. Two issues stand out: (1) `ApplicationController` is missing `before_action :require_authentication`, meaning the auth gate is silently provided only by the `Authentication` concern's default — this needs explicit verification; (2) the `SessionsController#create` test relies on fixture data with a hardcoded password `"password"` while the user fixture uses `BCrypt::Password.create("password")` — this works, but the test is fragile because `User.take` could return either fixture user with no predictable ordering.

### Findings

1. **Missing `before_action :require_authentication`** — `app/controllers/application_controller.rb:1-8`
   The PLAN (Task 4) explicitly required adding `before_action :require_authentication` to `ApplicationController`. The implemented `ApplicationController` only does `include Authentication` and lacks the explicit `before_action`. Rails 8's `Authentication` concern *does* call `before_action :require_authentication` automatically when included — but relying on this implicit behavior without the explicit line is fragile documentation-wise and violates the PLAN's stated intent. The SPEC requirement ("All board actions require authentication; unauthenticated requests redirect to login") is met in practice, but the explicit declaration is missing.

2. **`SessionsController` test uses `User.take` — non-deterministic fixture selection** — `test/controllers/sessions_controller_test.rb:4`
   `setup { @user = User.take }` returns whichever user the DB happens to return first. The test then asserts `cookies[:session_id]` after a successful login using hardcoded password `"password"`. This works because both fixtures use `"password"` — but it's fragile and will break if fixture data changes. Prefer `users(:one)` to select a specific fixture explicitly.

3. **`SessionsController#create` integration test expects `root_path` but SPEC says `boards_path`** — `test/controllers/sessions_controller_test.rb:14` and `test/integration/authentication_flow_test.rb:15`
   After login, `SessionsController` redirects to `after_authentication_url` which resolves to `root_path` (which IS `boards#index`). The integration test at `authentication_flow_test.rb:15` asserts `assert_redirected_to root_path` — technically correct since `root_path == boards_path` here, but the assertion obscures intent. PLAN expected `assert_redirected_to boards_path`. Minor, but the `sessions_controller_test.rb` assertion is clearer justification.

4. **`boards` migration missing `null: false` on `name` column** — `db/schema.rb:16`
   The schema shows `t.string "name"` (nullable) while the model validates `presence: true`. The database-level constraint is missing; a record with a blank name could be inserted by bypassing the model. The migration for boards should have used `t.string "name", null: false` to enforce this at the DB layer.

5. **`BoardsController` includes a `show` action and view not in PLAN scope** — `app/controllers/boards_controller.rb:8`, `app/views/boards/show.html.erb`
   The PLAN specified only index/new/create/edit/update/destroy for Phase 1. A `show` action and view were added. The show view is sparse (board name + edit link). This is harmless but untested and outside scope.

6. **`bin/setup --skip-server` note in AGENTS.md** — `AGENTS.md:22`
   The install command in AGENTS.md shows `bin/setup --skip-server` which is a local addition to the default Rails `bin/setup`. The AGENTS.md instruction is correct and the `bin/setup` file does handle this flag (`ARGV.include?("--skip-server")`), but the flag name is non-standard and undocumented in the script header comment.

### Spec Compliance Checklist

- [x] Rails 8 app scaffolded with SQLite
- [x] Tailwind CSS integrated via `tailwindcss-rails`
- [x] Hotwire/Turbo/Stimulus included (Rails 8 defaults)
- [x] Rails 8 built-in authentication (`rails generate authentication`)
- [x] Sign up, log in, log out flows implemented
- [x] Board model with CRUD (create, list, show, edit, delete)
- [x] Boards index as authenticated landing page (`root "boards#index"`)
- [x] AGENTS.md, README.md created, CLAUDE.md updated (prepended)
- [x] Minitest setup with SimpleCov configured
- [x] Playwright E2E tests present for auth and board flows
- [x] Board belongs to the user who created it
- [x] Only the board owner can view/edit/delete (scoped via `Current.user.boards.find`)
- [x] Board name validation (presence: true)
- [x] Tailwind used for styling
- [x] Turbo Drive enabled (default)
- [x] `bin/setup` installs dependencies and prepares the database
- [ ] `before_action :require_authentication` explicitly declared in ApplicationController (implicit via concern only)
- [ ] `boards` table missing DB-level `null: false` on `name` column

---

## Adversarial Test Review

### Summary
Test quality is **strong** overall. No mocking abuse — all tests use real ActiveRecord objects and real HTTP dispatch via ActionDispatch integration tests. Coverage of happy paths and error paths is good. The boards flow tests go beyond the PLAN's requirements by also covering cross-user update/delete attempts (not just read). A few issues are worth flagging: one fixture-dependent test with `User.take`, a stale integration test assertion that checks `root_path` instead of `boards_path`, and the `SessionsController` test relying on BCrypt fixture data with a fixed password string that could become a maintenance hazard.

### Findings

1. **`User.take` fixture ordering non-determinism** — `test/controllers/sessions_controller_test.rb:4`
   `User.take` has no defined ordering guarantee. In SQLite with a small fixture set it's stable, but this is an implicit assumption. When `parallelize(workers: :number_of_processors)` is active (see `test_helper.rb:15`), test ordering across workers can vary. Fix: `users(:one)` is the correct Rails fixture accessor.

2. **`sign_in_with_invalid_credentials` test expects redirect, not 422** — `test/integration/authentication_flow_test.rb:19-21`
   The test asserts `assert_redirected_to new_session_path` which matches the actual controller behavior (SessionsController redirects on failure with an alert). However, the PLAN's `Task 7` explicitly stated this test should be `assert_response :unprocessable_entity`. The actual SessionsController implementation redirects (not 422), so the test is _correct_ for the current code — but this means the code diverged from the plan spec. The test comment-description still says "redirects to login with alert" which is accurate, but the PLAN test used `:unprocessable_entity`. No functional bug, but alignment issue between plan and implementation.

3. **`sign up with mismatched passwords` test coverage gap in integration tests** — `test/integration/authentication_flow_test.rb:35-40`
   The test sends a `post` to `registration_path` with mismatched passwords and asserts `assert_response :unprocessable_entity`. This is correct. However, there is no assertion that the user was NOT created — `assert_not User.exists?(email_address: "bad@example.com")` is missing. A regression could save the user without triggering the password confirmation validation and the test would still pass if the response status happened to be 422 for a different reason.

4. **`SessionsController` controller test uses hardcoded password string `"password"`** — `test/controllers/sessions_controller_test.rb:12`
   This relies on the fixture `users.yml` generating BCrypt digests from `"password"`. If the fixture password is ever changed, this test silently starts testing invalid-credential behavior. The test name says "create with valid credentials" but there's no setup asserting which user is used. Low risk given fixture stability, but worth noting.

5. **`parallelize(workers: :number_of_processors)` + SimpleCov incompatibility risk** — `test/test_helper.rb:15`
   SimpleCov does not work correctly with Minitest parallelization using multiple processes (`:number_of_processors`). Each worker process runs SimpleCov independently and only the last process's report survives, leading to under-reported coverage. This can cause the `minimum_coverage 80` threshold to trigger false failures or show misleadingly low coverage. SimpleCov requires either running with 1 worker or using `SimpleCov.use_merging true` with `SimpleCov::ResultMerger` across processes.

6. **No test for `boards index` showing only the current user's boards** — `test/integration/boards_flow_test.rb`
   The existing `boards index lists user boards` test (`line 9`) only verifies the current user's boards appear. It does not assert that boards from OTHER users do NOT appear. A regression where boards are not scoped could display all boards to all users and this test would still pass.

7. **E2E `log in with valid credentials` test skips actual login form verification** — `e2e/auth.spec.js:35-47`
   After signing up and logging out, the test fills the login form by name selectors `[name="email_address"]` and `[name="password"]`. If Turbo causes a redirect to a different URL before the test reaches the fill, the test could fail with a confusing selector error rather than a clear assertion failure. The test also uses `toContainText('My Boards')` instead of `toHaveURL('/boards')` as the final assertion — this passes even if the redirect lands on a non-boards page that happens to contain that text. Add `await expect(page).toHaveURL('/boards')` as well.

8. **Delete board E2E dialog handling race condition** — `e2e/boards.spec.js:57`
   `page.on('dialog', d => d.accept())` is registered AFTER the board is verified visible but BEFORE the delete click. With Turbo, the `data-turbo-confirm` confirm dialog is a native browser dialog. If the dialog fires before the event listener is fully registered, it would be dismissed/ignored. The handler should be registered before the `click` or, safer, use `page.once('dialog', ...)` to ensure it fires once. The current ordering (`page.on` then `click`) is technically fine but the `page.on` registration before the async operation introduces a potential race in slower CI environments.

### Test Coverage
- SimpleCov generates `coverage/index.html` after `bin/rails test`
- Configured minimum: 80%
- **Risk**: parallelization may cause under-reporting (see Finding 5)

### Missing Test Cases
- Board index does NOT show other users' boards (negative scoping assertion)
- Sign-up with duplicate email shows validation error (only uniqueness of model tested, not the HTTP flow)
- `show` action on board owned by another user (the show action exists but has no authorization test)
- Board name with only whitespace (e.g., `"   "`) — `presence: true` passes for whitespace unless `strip` is called
