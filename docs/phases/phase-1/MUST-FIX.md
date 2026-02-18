# Must-Fix Items: Phase 1

## Summary
2 critical issues, 4 minor issues found in review.

---

## Tasks

### Task 1: Add DB-level NOT NULL constraint on `boards.name`
**Priority:** Critical
**Status:** ✅ Fixed
**What was done:** Generated migration `20260218170541_add_not_null_to_boards.rb` with `change_column_null :boards, :name, false, ""`. Ran `bin/rails db:migrate`. Verified `db/schema.rb` now shows `t.string "name", null: false`.

---

### Task 2: Fix SimpleCov + Minitest parallelization incompatibility
**Priority:** Critical
**Status:** ✅ Fixed
**What was done:** Changed `parallelize(workers: :number_of_processors)` to `parallelize(workers: 1)` in `test/test_helper.rb` (Option A). Full suite runs at 82.31% coverage, above the 80% minimum.

---

### Task 3: Fix `SessionsController` test to use named fixture instead of `User.take`
**Priority:** Minor
**Status:** ✅ Fixed
**What was done:** Changed `setup { @user = User.take }` to `setup { @user = users(:one) }` in `test/controllers/sessions_controller_test.rb`. Also updated `sign_in_as(User.take)` in the `destroy` test to `sign_in_as(users(:one))`. All 4 tests in the file pass.

---

### Task 4: Add missing negative assertion to sign-up failure test
**Priority:** Minor
**Status:** ✅ Fixed
**What was done:** Added `assert_not User.exists?(email_address: "bad@example.com")` after `assert_response :unprocessable_entity` in `test/integration/authentication_flow_test.rb`. All 6 tests pass.

---

### Task 5: Add negative scoping assertion to boards index test
**Priority:** Minor
**Status:** ✅ Fixed
**What was done:** Extended the "boards index lists user boards" test in `test/integration/boards_flow_test.rb` to create a second user and their board, then added `assert_no_match "Other User Board", response.body`. All board flow tests pass.

---

### Task 6: Fix E2E login test to assert final URL, not just heading text
**Priority:** Minor
**Status:** ✅ Fixed
**What was done:** Added `await expect(page).toHaveURL('/boards');` after the heading assertion in `e2e/auth.spec.js:46`. The test now asserts both the heading and the URL after login.
