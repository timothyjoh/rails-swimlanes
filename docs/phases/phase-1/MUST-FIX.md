# Must-Fix Items: Phase 1

## Summary
2 critical issues, 4 minor issues found in review.

---

## Tasks

### Task 1: Add DB-level NOT NULL constraint on `boards.name`
**Priority:** Critical
**Files:** `db/migrate/` (new migration), `db/schema.rb`
**Problem:** The `boards` table column `name` is nullable at the database level (`t.string "name"` with no `null: false`). The model enforces presence via `validates :name, presence: true`, but a record with a blank/null name can be inserted by bypassing the model (e.g., direct SQL, `update_column`, or a future bulk operation). `db/schema.rb:16` shows `t.string "name"` with no null constraint.
**Fix:**
1. Generate a new migration:
   ```bash
   bin/rails generate migration AddNotNullToBoards
   ```
2. Edit the migration to:
   ```ruby
   def change
     change_column_null :boards, :name, false, ""
   end
   ```
   The third argument `""` is a default used to backfill any existing null rows before the constraint is applied.
3. Run: `bin/rails db:migrate`
4. Verify `db/schema.rb` now shows `t.string "name", null: false`
**Verify:** `bin/rails db:migrate` exits 0 and `grep -A 5 'create_table "boards"' db/schema.rb` shows `null: false` on the `name` column.

---

### Task 2: Fix SimpleCov + Minitest parallelization incompatibility
**Priority:** Critical
**Files:** `test/test_helper.rb`
**Problem:** `test/test_helper.rb:15` uses `parallelize(workers: :number_of_processors)` which runs tests in multiple OS processes. SimpleCov tracks coverage per-process, and only the last process to finish writes the final report. This means the `minimum_coverage 80` enforcement is unreliable — it could pass or fail based on which subset of tests happened to run in the final process, not the full suite. See `test/test_helper.rb:1-5` for SimpleCov config and `:15` for parallelization.
**Fix:**
Option A (simplest — disable parallelization for coverage correctness):
```ruby
# test/test_helper.rb — change line 15 from:
parallelize(workers: :number_of_processors)
# to:
parallelize(workers: 1)
```
Option B (keep parallelization, merge SimpleCov results across processes):
Update `test/test_helper.rb` to add after `SimpleCov.start`:
```ruby
SimpleCov.start "rails" do
  add_filter "/test/"
  minimum_coverage 80
  enable_coverage :branch
end

# Enable result merging for parallel workers
if ENV["PARALLEL_WORKERS"] && ENV["PARALLEL_WORKERS"].to_i > 1
  SimpleCov.use_merging true
end
```
And update `parallelize` to use threads instead of processes:
```ruby
parallelize(workers: :number_of_processors, with: :threads)
```
Note: thread-based parallelization requires thread-safe test setup; Option A is safer for now.
**Verify:** Run `bin/rails test` and confirm `coverage/index.html` reports coverage > 80% based on the full test suite (check that `coverage/.resultset.json` shows a merged result if using Option B).

---

### Task 3: Fix `SessionsController` test to use named fixture instead of `User.take`
**Priority:** Minor
**Files:** `test/controllers/sessions_controller_test.rb:4`
**Problem:** `setup { @user = User.take }` uses `User.take` which has no ordering guarantee and could return any fixture user. With `parallelize(workers: :number_of_processors)`, different workers may load fixtures in different orders. The hardcoded password `"password"` in the test (line 12) assumes the fixture user has that password — this is true today because both fixture users use `"password"`, but the coupling is implicit and fragile.
**Fix:**
Change line 4:
```ruby
# Before:
setup { @user = User.take }
# After:
setup { @user = users(:one) }
```
**Verify:** `bin/rails test test/controllers/sessions_controller_test.rb` passes with all 4 tests green.

---

### Task 4: Add missing negative assertion to sign-up failure test
**Priority:** Minor
**Files:** `test/integration/authentication_flow_test.rb:35-40`
**Problem:** The test "sign up with mismatched passwords re-renders form" only asserts `assert_response :unprocessable_entity`. It does NOT assert that the user was NOT created. A regression where a user is saved despite validation failure would not be caught.
**Fix:**
Add an assertion after the existing one at line 39:
```ruby
test "sign up with mismatched passwords re-renders form" do
  post registration_path, params: {
    user: { email_address: "bad@example.com", password: "password123", password_confirmation: "different" }
  }
  assert_response :unprocessable_entity
  assert_not User.exists?(email_address: "bad@example.com")  # Add this line
end
```
**Verify:** `bin/rails test test/integration/authentication_flow_test.rb` passes with all 6 tests green.

---

### Task 5: Add negative scoping assertion to boards index test
**Priority:** Minor
**Files:** `test/integration/boards_flow_test.rb:9-14`
**Problem:** The "boards index lists user boards" test confirms the current user's board appears, but does NOT confirm that another user's board does NOT appear. A regression dropping the `Current.user.boards` scope (reverting to `Board.all`) would not be caught by the current test.
**Fix:**
Extend the existing test at line 9:
```ruby
test "boards index lists user boards" do
  Board.create!(name: "Sprint 1", user: @user)
  other_user = User.create!(email_address: "other@example.com", password: "password123")
  Board.create!(name: "Other User Board", user: other_user)
  get boards_path
  assert_response :success
  assert_match "Sprint 1", response.body
  assert_no_match "Other User Board", response.body  # Add this line
end
```
**Verify:** `bin/rails test test/integration/boards_flow_test.rb` passes with all tests green.

---

### Task 6: Fix E2E login test to assert final URL, not just heading text
**Priority:** Minor
**Files:** `e2e/auth.spec.js:46`
**Problem:** After logging back in, the E2E test asserts `await expect(page.locator('h1')).toContainText('My Boards')` (line 46). This passes even if the page is at a different URL that happens to contain an h1 with "My Boards". The test should also assert the URL to confirm the redirect target.
**Fix:**
Add a URL assertion after the existing heading check at line 46:
```javascript
// After:
await expect(page.locator('h1')).toContainText('My Boards');
// Add:
await expect(page).toHaveURL('/boards');
```
**Verify:** `npx playwright test e2e/auth.spec.js` passes with all 5 tests green.
