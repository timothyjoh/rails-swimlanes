# Reflections: Phase 1

## Looking Back

### What Went Well
- **Full vertical slice delivered**: Auth + Board CRUD + tests + docs landed in a single pass. The app boots, users can sign up, create boards, edit them, delete them, and log out — every acceptance criterion from the SPEC is met.
- **Test quality was genuinely good**: No mocking abuse, real ActiveRecord objects, integration tests covering happy and error paths. The board flow tests went beyond spec by testing cross-user update/delete attempts.
- **Review + fix cycle caught real problems before Phase 2**: The two critical MUST-FIX items (SimpleCov parallelization and missing DB `null: false` constraint) were identified by review and resolved cleanly. Had these been left until Phase 2, the coverage tool would have produced misleading numbers and the DB constraint gap would have grown.
- **PLAN was specific enough to be executable**: Tasks had explicit file paths, code content, and success criteria. The build step could follow the PLAN without ambiguity.
- **Documentation created and intact**: AGENTS.md, README.md, and updated CLAUDE.md all landed correctly. The CLAUDE.md prepend-not-replace instruction was followed.

### What Didn't Work
- **Single large commit obscures task boundaries**: `git log --oneline -15` shows only `Initial commit: Rails 8 Swimlanes app scaffold`. All 9 tasks were bundled into one commit. If any task had introduced a regression, bisecting would be impossible. This is a process gap — the pipeline should commit after each task or at logical checkpoints.
- **`before_action :require_authentication` not explicitly declared**: The PLAN required this explicit line in `ApplicationController`. The implementation relied on the implicit behavior from the `Authentication` concern. Functionally identical, but it violates the "explicit over implicit" Rails convention and the stated plan. This indicates the build agent didn't verify against the plan checklist before marking the task complete.
- **`SessionsController#create` test asserts `root_path` not `boards_path`**: A minor divergence from the PLAN's stated test intent. The assertion is technically correct (they resolve identically), but it obscures the intent of the test. Small example of the build drifting from the plan's phrasing without documenting why.
- **`show` action added outside spec scope**: A `BoardsController#show` action and view were added without being in scope for Phase 1. No test was written for it, leaving an untested and unauthorized endpoint live.

### Spec vs Reality
- **Delivered as spec'd**: Rails 8 scaffold + SQLite, Tailwind, Hotwire, built-in auth, sign up/in/out flows, Board CRUD with user scoping, boards index as root, AGENTS.md / README.md / CLAUDE.md, Minitest + SimpleCov, Playwright E2E tests.
- **Deviated from spec**: `ApplicationController` missing explicit `before_action :require_authentication` (implicit via concern only); `SessionsController` test asserts `root_path` instead of `boards_path`; `show` action added without spec'ing it.
- **Deferred**: Nothing from Phase 1 scope was explicitly deferred. All acceptance criteria were met after the MUST-FIX pass.

### Review Findings Impact
- **DB `null: false` on `boards.name`**: Migration generated and ran; `db/schema.rb` now enforces the constraint. Critical gap closed.
- **SimpleCov + parallelization incompatibility**: Switched to `parallelize(workers: 1)`. Coverage now reports 82.31%, above the 80% floor. Critical gap closed.
- **`User.take` non-determinism**: Fixed to `users(:one)`. Minor but real fragility removed.
- **Missing negative assertion in sign-up failure test**: Added `assert_not User.exists?`. Small but meaningful correctness improvement.
- **Boards index missing negative scope assertion**: Added second-user board to fixture and `assert_no_match`. This is the most important minor fix — it means the index scope test now actually catches a regression.
- **E2E login test URL assertion**: Added `toHaveURL('/boards')` alongside the heading check.

---

## Looking Forward

### Recommendations for Next Phase
- **Commit granularly**: Each logical task (model + migration, controller, views, tests) should be its own commit. The single-commit approach makes the pipeline harder to audit and debug.
- **Verify plan checklist before declaring task complete**: The build agent missed the explicit `before_action` line and the out-of-scope `show` action. The fix phase should require comparing delivered code against the PLAN's success criteria, not just "does the app work."
- **The `show` action must be spec'd or removed in Phase 2**: Currently there is a live `GET /boards/:id` route with no authorization test and a sparse view. Phase 2 can legitimately promote this to a full board detail page (where swimlanes will live), but it needs to be explicitly in scope and tested.
- **E2E test database isolation**: Playwright uses `RAILS_ENV=test` via the webServer config. Phase 2 will add more complex interactions (drag-and-drop, swimlanes). Consider whether the E2E tests need a seed script or API-level setup helpers to reduce reliance on sign-up-every-test patterns.
- **Whitespace-only board names**: `presence: true` passes for `"   "`. Add `strip_attributes` or a custom validator if this matters. The review flagged it; it was not fixed. Phase 2 will add Swimlane names with the same risk.

### What Should Next Phase Build?
Based on BRIEF.md, Phase 2 is **Swimlanes and Cards with drag-and-drop**.

Specific scope and priorities:
1. **Swimlane (column) model**: `name`, `position`, `belongs_to :board`. Board `has_many :swimlanes`.
2. **Card model**: `name`, `position`, `belongs_to :swimlane`. Swimlane `has_many :cards`.
3. **Board show page** (this is the Phase 2 canvas): Promote the existing sparse `show` action into the full board view that renders swimlanes and cards side-by-side.
4. **Swimlane CRUD**: Create, rename, delete lanes within a board.
5. **Card CRUD**: Create, rename, delete cards within a lane.
6. **Drag-and-drop**: SortableJS (or similar) for reordering cards within a lane and moving cards between lanes. Keep it simple — position column updated via a `PATCH /cards/:id` endpoint.
7. **Minitest + Playwright** coverage for all new flows.

The `show` action divergence from Phase 1 is actually a gift: the scaffold is already in place. Phase 2 just needs to fill it in properly.

### Technical Debt Noted
- **No explicit `before_action :require_authentication` in ApplicationController**: `app/controllers/application_controller.rb:1` — implicit behavior is fragile documentation. Should be made explicit at the start of Phase 2 or treated as a fast fix.
- **`show` action untested and out of scope**: `app/controllers/boards_controller.rb` and `app/views/boards/show.html.erb` — exists, boots, has no auth test. Phase 2 must own it.
- **Whitespace board names pass validation**: `app/models/board.rb:3` — `validates :name, presence: true` allows `"   "`. Low priority but a known gap.
- **`bin/setup --skip-server` flag undocumented in script header**: `bin/setup` — non-standard flag that works but is undocumented inside the file itself.

### Process Improvements
- **Commit per task, not per phase**: The pipeline build step should commit after each task. This gives the review and fix phases better visibility into what changed and why.
- **Build agent should self-check against PLAN success criteria**: Before marking a task done, verify each `[ ]` in the PLAN's success criteria checklist. The missing `before_action` line and the out-of-scope `show` action would have been caught.
- **Review should output a coverage diff, not just a percentage**: "82.31% coverage" is fine, but Phase 2 should report which files are under-covered so the fix phase can target gaps rather than guessing.
