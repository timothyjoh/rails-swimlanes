# Implementation Plan: Phase 4 — Board Sharing

## Overview
Add a `BoardMembership` join table, update all authorization to be membership-scoped, and build a sharing UI that lets board owners add/remove collaborators by email using Turbo Streams.

## Current State (from Research)

- **Models**: `Board` belongs_to `:user` (single owner FK); no `BoardMembership` model or table yet.
- **Authorization**: All controllers use `Current.user.boards.find(...)` — raises 404 for non-owners. This works today but excludes members who don't own the board.
- **5 auth check sites** to update: `BoardsController#index`, `BoardsController#set_board`, `SwimlanesController#set_board`, `CardsController#set_board`, `CardsController#reorder` inline check.
- **Turbo Streams**: Already established; successful actions use `.turbo_stream.erb` files, validation errors use inline `render turbo_stream:` with `status: :unprocessable_entity`.
- **User email column**: `email_address` (not `email`) — `User.find_by(email_address:)` is the lookup.
- **Integration tests**: Create records inline in `setup` — no fixture dependency for flow tests.
- **Fixtures**: Two users (`one`, `two`), two boards (`one` owned by `users(:one)`, `two` owned by `users(:two)`).

## Resolved Open Questions

1. **Fixture strategy**: Add `test/fixtures/board_memberships.yml` with owner memberships for existing boards (`one` → user `one`, `two` → user `two`). This keeps model unit tests consistent. Integration tests continue creating records inline and will also create the owner `BoardMembership` alongside boards.
2. **`user_id` on boards**: Keep `Board#user` association (creator/owner). Owner-only actions check `BoardMembership.exists?(board: @board, user: Current.user, role: :owner)`.
3. **Scope naming**: `Board.accessible_by(user)` — class-level scope on `Board` model, used in all 4 controller locations.
4. **Existing test compatibility**: Tests that create boards inline (e.g., `boards_flow_test.rb`) will also create the owner `BoardMembership`. The "other user's board" tests (`cannot view another user's board`) continue to pass — no membership for `@user` on `other_board` is created.
5. **`BoardsController#create`**: Explicit controller code creates the owner `BoardMembership` after `@board.save` — no model callback.

## Desired End State

- `board_memberships` table with `board_id`, `user_id`, `role` (enum: `owner`/`member`), unique index on `[board_id, user_id]`.
- `Board.accessible_by(user)` scope returns boards where user has any membership.
- All 5 auth check sites use membership-scoped queries.
- Board show page has a "Members" panel (owner-only) listing members with a remove link (except the owner row), plus an add-by-email form.
- Add-member and remove-member update the member list via Turbo Stream — no page reloads.
- Shared boards appear on the collaborator's boards index.
- Collaborators can read, create, edit, delete swimlanes and cards; cannot delete or rename the board.
- Owner-only controls (Edit Board, Delete Board) hidden from collaborators in views.

**Verification**: `bin/rails test` passes; `npx playwright test` passes; SimpleCov ≥ 80%.

## What We're NOT Doing

- Invitation emails or invite links
- Sign-up invitations for non-existing users
- Role granularity beyond `owner` / `member` (no read-only, no admin)
- Collaborator transferring ownership
- Notification emails when added to a board
- Real-time membership push updates (Phase 5)
- Activity log / audit trail

## Implementation Approach

Build in layers from data → model → auth → UI:

1. **Data layer first**: Migration + fixtures so all subsequent tests compile.
2. **Model layer**: `BoardMembership` model, `Board.accessible_by` scope, association wiring.
3. **Auth sweep**: Update all 5 auth check sites; update board creation to seed owner membership; update existing integration tests to create owner memberships.
4. **Sharing UI**: `MembershipsController` + routes + views for add/remove; Turbo Stream responses.
5. **View gates**: Hide owner-only controls from collaborators in views.
6. **Tests**: Unit tests for model, integration tests for each controller path, E2E for full flows.
7. **Docs**: AGENTS.md + README.md.
8. **Cosmetic fix**: README Phase 3 `✓` (Task 0).

---

## Task 0: Fix README Phase 3 Checkmark

### Overview
The Phase 3 entry in README.md is missing the `✓` completion marker. Fix this before any Phase 4 work.

### Changes Required

**File**: `README.md`
Find the Phase 3 entry and add the `✓` checkmark to match the format of completed phases.

### Success Criteria
- [ ] README.md Phase 3 entry has `✓`

---

## Task 1: Migration — Create `board_memberships` Table

### Overview
Create the join table with `board_id`, `user_id`, `role` (enum), and a unique index.

### Changes Required

**File**: `db/migrate/TIMESTAMP_create_board_memberships.rb`
```ruby
class CreateBoardMemberships < ActiveRecord::Migration[8.0]
  def change
    create_table :board_memberships do |t|
      t.references :board, null: false, foreign_key: true
      t.references :user, null: false, foreign_key: true
      t.integer :role, null: false, default: 0

      t.timestamps
    end

    add_index :board_memberships, [:board_id, :user_id], unique: true
  end
end
```

Run: `bin/rails db:migrate`

### Success Criteria
- [ ] Migration runs cleanly: `bin/rails db:migrate`
- [ ] `db/schema.rb` contains `board_memberships` table with `board_id`, `user_id`, `role`, unique index

---

## Task 2: `BoardMembership` Model

### Overview
Create the model with enum, validations, and associations.

### Changes Required

**File**: `app/models/board_membership.rb`
```ruby
class BoardMembership < ApplicationRecord
  belongs_to :board
  belongs_to :user

  enum :role, { owner: 0, member: 1 }

  validates :board, presence: true
  validates :user, presence: true
  validates :role, presence: true
  validates :user_id, uniqueness: { scope: :board_id, message: "is already a member of this board" }
end
```

**File**: `app/models/board.rb` — add associations and scope:
```ruby
has_many :board_memberships, dependent: :destroy
has_many :members, through: :board_memberships, source: :user

def self.accessible_by(user)
  joins(:board_memberships).where(board_memberships: { user_id: user.id })
end
```

**File**: `app/models/user.rb` — add association:
```ruby
has_many :board_memberships, dependent: :destroy
has_many :shared_boards, through: :board_memberships, source: :board
```

**File**: `test/fixtures/board_memberships.yml` (NEW):
```yaml
one:
  board: one
  user: one
  role: 0

two:
  board: two
  user: two
  role: 0
```

**File**: `test/models/board_membership_test.rb` (NEW):
```ruby
require "test_helper"

class BoardMembershipTest < ActiveSupport::TestCase
  setup do
    @board = boards(:one)
    @user = users(:one)
    @other_user = users(:two)
  end

  test "valid membership" do
    membership = BoardMembership.new(board: @board, user: @other_user, role: :member)
    assert membership.valid?
  end

  test "requires board" do
    membership = BoardMembership.new(user: @other_user, role: :member)
    assert_not membership.valid?
    assert_includes membership.errors[:board], "must exist"
  end

  test "requires user" do
    membership = BoardMembership.new(board: @board, role: :member)
    assert_not membership.valid?
    assert_includes membership.errors[:user], "must exist"
  end

  test "requires role" do
    membership = BoardMembership.new(board: @board, user: @other_user)
    membership.role = nil
    assert_not membership.valid?
  end

  test "prevents duplicate membership" do
    # @board already has an owner membership for @user via fixtures
    duplicate = BoardMembership.new(board: @board, user: @user, role: :member)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "is already a member of this board"
  end

  test "role enum owner?" do
    m = board_memberships(:one)
    assert m.owner?
    assert_not m.member?
  end
end
```

**File**: `test/models/board_test.rb` — add accessible_by scope test:
```ruby
test "accessible_by returns boards where user is a member" do
  user = users(:one)
  assert_includes Board.accessible_by(user), boards(:one)
  assert_not_includes Board.accessible_by(user), boards(:two)
end
```

### Success Criteria
- [ ] `bin/rails test test/models/board_membership_test.rb` passes
- [ ] `bin/rails test test/models/board_test.rb` passes (accessible_by test)
- [ ] Model validations work as documented

---

## Task 3: Authorization Sweep — Update All Controllers

### Overview
Replace all 5 `Current.user.boards.find(...)` and `Current.user.boards.joins(...)` occurrences with membership-scoped equivalents. Also update `BoardsController#create` to seed the owner membership. Update all integration tests that create boards to also create owner memberships.

### Changes Required

**File**: `app/controllers/boards_controller.rb`

```ruby
def index
  @boards = Board.accessible_by(Current.user).order(created_at: :desc)
end

def create
  @board = Current.user.boards.new(board_params)
  if @board.save
    @board.board_memberships.create!(user: Current.user, role: :owner)
    redirect_to boards_path, notice: "Board created."
  else
    render :new, status: :unprocessable_entity
  end
end

# set_board — two-step: member access for show; owner-only for update/destroy
def set_board
  @board = Board.accessible_by(Current.user).find(params[:id])
end

# Add owner check helper used in update and destroy:
def require_owner!
  raise ActiveRecord::RecordNotFound unless BoardMembership.exists?(board: @board, user: Current.user, role: :owner)
end
```

Add `before_action :require_owner!, only: [:edit, :update, :destroy]` after `before_action :set_board`.

**File**: `app/controllers/swimlanes_controller.rb` — update `set_board`:
```ruby
def set_board
  @board = Board.accessible_by(Current.user).find(params[:board_id])
end
```

**File**: `app/controllers/cards_controller.rb` — update both `set_board` and `reorder`:
```ruby
def set_board
  @board = Board.accessible_by(Current.user).find(params[:board_id])
end

# In reorder — replace Current.user.boards.joins(...) with membership scope:
unless Board.accessible_by(Current.user).joins(swimlanes: :cards).where(cards: { id: card.id }).exists?
  raise ActiveRecord::RecordNotFound
end
```

**File**: `test/integration/boards_flow_test.rb` — update `setup` to create owner membership when creating boards:

Every `Board.create!(... user: @user)` call in the test must be followed by:
```ruby
board.board_memberships.create!(user: @user, role: :owner)
```
Or use a helper method `create_board_for(user, name:)` that does both.

Key tests to update:
- `setup` — no board created there, OK.
- `"boards index lists user boards"` — `Board.create!(name: "Sprint 1", user: @user)` → add membership; `Board.create!(name: "Other User Board", user: other_user)` → add other_user owner membership.
- `"create a board"` — POST creates board; controller now creates membership too; test assertion `Board.exists?(name: "Sprint 1", user: @user)` still passes.
- `"edit board name"` — `Board.create!(name: "Old Name", user: @user)` → add owner membership.
- All other tests that create boards owned by `@user` → add owner membership.
- Tests using `other_board` without sharing — no membership for `@user` → 404 tests still pass.

**File**: `test/integration/swimlanes_flow_test.rb` — same pattern: add owner memberships when creating boards in setup/tests.

**File**: `test/integration/cards_flow_test.rb` — same pattern.

**File**: `test/integration/labels_flow_test.rb` — same pattern (if boards are created inline).

### Controller Checklist (ALL must be updated)
- [x] `BoardsController#index` — `Board.accessible_by`
- [x] `BoardsController#set_board` — `Board.accessible_by`
- [x] `BoardsController#create` — add owner membership after save
- [x] `BoardsController` — `require_owner!` before edit/update/destroy
- [x] `SwimlanesController#set_board` — `Board.accessible_by`
- [x] `CardsController#set_board` — `Board.accessible_by`
- [x] `CardsController#reorder` inline check — `Board.accessible_by`

### Success Criteria
- [ ] `bin/rails test test/integration/boards_flow_test.rb` passes (all tests)
- [ ] Non-member GET board → 404 (existing tests still pass)
- [ ] A collaborator (member) accessing `set_board` in SwimlanesController → 200 (new test in Task 6)
- [ ] A collaborator attempting `update`/`destroy` on the board itself → 404 (new test in Task 6)

---

## Task 4: `MembershipsController` + Routes

### Overview
Add `boards/:board_id/memberships` resource with `create` (add member by email) and `destroy` (remove member). Owner-only.

### Changes Required

**File**: `config/routes.rb` — add inside `resources :boards`:
```ruby
resources :boards do
  resources :memberships, only: [:create, :destroy]
  # ... existing nested resources
end
```

**File**: `app/controllers/memberships_controller.rb` (NEW):
```ruby
class MembershipsController < ApplicationController
  before_action :set_board
  before_action :require_owner!

  def create
    email = params.dig(:membership, :email_address).to_s.strip.downcase
    user = User.find_by(email_address: email)

    if user.nil?
      render turbo_stream: turbo_stream.replace(
        "membership_form",
        partial: "memberships/form",
        locals: { board: @board, error: "No user found with that email address." }
      ), status: :unprocessable_entity
      return
    end

    if BoardMembership.exists?(board: @board, user: user)
      render turbo_stream: turbo_stream.replace(
        "membership_form",
        partial: "memberships/form",
        locals: { board: @board, error: "That user is already a member of this board." }
      ), status: :unprocessable_entity
      return
    end

    @membership = @board.board_memberships.create!(user: user, role: :member)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to board_path(@board) }
    end
  end

  def destroy
    @membership = @board.board_memberships.find(params[:id])

    if @membership.owner?
      redirect_to board_path(@board), alert: "Cannot remove the board owner."
      return
    end

    @membership.destroy

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(dom_id(@membership)) }
      format.html { redirect_to board_path(@board) }
    end
  end

  private

  def set_board
    @board = Board.accessible_by(Current.user).find(params[:board_id])
  end

  def require_owner!
    raise ActiveRecord::RecordNotFound unless BoardMembership.exists?(board: @board, user: Current.user, role: :owner)
  end
end
```

Note: `MembershipsController` needs `include ActionView::RecordIdentifier` for `dom_id`.

### Success Criteria
- [ ] `bin/rails routes | grep membership` shows create and destroy routes
- [ ] Controller file compiles (no syntax errors): `bin/rails runner "MembershipsController"`

---

## Task 5: Members Panel Views + Turbo Streams

### Overview
Add the Members panel to `boards/show.html.erb` (owner-only), member list partial, add-member form partial, and Turbo Stream view for `create`.

### Changes Required

**File**: `app/views/boards/show.html.erb` — add Members panel after the swimlanes section, visible only to owner:
```erb
<% if BoardMembership.exists?(board: @board, user: Current.user, role: :owner) %>
  <div class="px-4 pb-4 mt-4 border-t pt-4">
    <h2 class="text-lg font-semibold mb-2">Members</h2>
    <%= turbo_frame_tag "members_panel" do %>
      <div id="memberships">
        <%= render partial: "memberships/membership",
            collection: @board.board_memberships.includes(:user).order(:role, :created_at),
            as: :membership,
            locals: { board: @board } %>
      </div>
      <%= render "memberships/form", board: @board, error: nil %>
    <% end %>
  </div>
<% end %>
```

**File**: `app/views/memberships/_membership.html.erb` (NEW):
```erb
<div id="<%= dom_id(membership) %>" class="flex justify-between items-center py-1">
  <span><%= membership.user.email_address %> (<%= membership.role %>)</span>
  <% unless membership.owner? %>
    <%= button_to "Remove",
        board_membership_path(board, membership),
        method: :delete,
        data: { turbo_confirm: "Remove this member?" },
        class: "text-sm text-red-600 hover:underline bg-transparent border-none cursor-pointer p-0" %>
  <% end %>
</div>
```

**File**: `app/views/memberships/_form.html.erb` (NEW):
```erb
<div id="membership_form" class="mt-3">
  <% if error %>
    <p class="text-red-600 text-sm mb-2"><%= error %></p>
  <% end %>
  <%= form_with url: board_memberships_path(board), method: :post do |f| %>
    <div class="flex gap-2">
      <%= f.email_field :email_address,
          name: "membership[email_address]",
          placeholder: "Add member by email",
          class: "border rounded px-2 py-1 text-sm flex-1" %>
      <%= f.submit "Add", class: "bg-blue-600 text-white px-3 py-1 rounded text-sm hover:bg-blue-700" %>
    </div>
  <% end %>
</div>
```

**File**: `app/views/memberships/create.turbo_stream.erb` (NEW):
```erb
<%= turbo_stream.append "memberships", partial: "memberships/membership", locals: { membership: @membership, board: @board } %>
<%= turbo_stream.replace "membership_form", partial: "memberships/form", locals: { board: @board, error: nil } %>
```

### Success Criteria
- [ ] Board show page renders without errors for the owner
- [ ] Members panel shows current members
- [ ] Add-member form is present
- [ ] Non-owner (collaborator) does NOT see the Members panel

---

## Task 6: View Gates — Hide Owner-Only Controls

### Overview
Update views so collaborators cannot see "Edit Board", "Delete Board" controls.

### Changes Required

**File**: `app/views/boards/show.html.erb` — wrap "Edit Board" link:
```erb
<% if BoardMembership.exists?(board: @board, user: Current.user, role: :owner) %>
  <%= link_to "Edit Board", edit_board_path(@board), class: "text-sm text-blue-600 hover:underline" %>
<% end %>
```

**File**: `app/views/boards/index.html.erb` — wrap "Edit" and "Delete" controls:
```erb
<% if BoardMembership.exists?(board: board, user: Current.user, role: :owner) %>
  <%= link_to "Edit", edit_board_path(board), class: "text-sm text-blue-600 hover:underline" %>
  <%= button_to "Delete", board_path(board), method: :delete,
      data: { turbo_confirm: "Delete this board?" },
      class: "text-sm text-red-600 hover:underline bg-transparent border-none cursor-pointer p-0" %>
<% end %>
```

Note: To avoid N+1 queries on the boards index, preload memberships for the current user. In `BoardsController#index`:
```ruby
@boards = Board.accessible_by(Current.user)
               .order(created_at: :desc)
               .includes(:board_memberships)
```
Then use an instance variable or helper to check role — or accept the query per board on index (low board count in practice; optimize later if needed).

Alternative to reduce per-board queries: precompute a set of owned board IDs:
```ruby
@owned_board_ids = BoardMembership.where(user: Current.user, role: :owner).pluck(:board_id).to_set
```
Then in view: `<% if @owned_board_ids.include?(board.id) %>`.

**Decision**: Use `@owned_board_ids` set — one extra query, no N+1.

### Success Criteria
- [ ] Owner sees Edit/Delete on boards index; collaborator does not
- [ ] Owner sees "Edit Board" on board show; collaborator does not
- [ ] Collaborator sees the Members panel? No — only owner.

---

## Task 7: Integration Tests for Membership + Auth Boundaries

### Overview
Write comprehensive integration tests covering the new membership flows and auth boundaries.

### Changes Required

**File**: `test/integration/memberships_flow_test.rb` (NEW):

```ruby
require "test_helper"

class MembershipsFlowTest < ActionDispatch::IntegrationTest
  TURBO_HEADERS = { "Accept" => "text/vnd.turbo-stream.html" }.freeze

  setup do
    @owner = User.create!(email_address: "owner@example.com", password: "password123")
    @board = Board.create!(name: "Shared Board", user: @owner)
    @board.board_memberships.create!(user: @owner, role: :owner)
    sign_in_as @owner
  end

  # --- Add member ---

  test "owner adds member by valid email" do
    member = User.create!(email_address: "member@example.com", password: "password123")
    post board_memberships_path(@board),
         params: { membership: { email_address: member.email_address } },
         headers: TURBO_HEADERS
    assert_response :success
    assert @board.reload.members.include?(member)
    assert_match member.email_address, response.body
  end

  test "owner sees turbo stream error for unknown email" do
    post board_memberships_path(@board),
         params: { membership: { email_address: "nobody@example.com" } },
         headers: TURBO_HEADERS
    assert_response :unprocessable_entity
    assert_match "No user found with that email address", response.body
  end

  test "owner sees error for already-member email" do
    member = User.create!(email_address: "dup@example.com", password: "password123")
    @board.board_memberships.create!(user: member, role: :member)
    post board_memberships_path(@board),
         params: { membership: { email_address: member.email_address } },
         headers: TURBO_HEADERS
    assert_response :unprocessable_entity
    assert_match "already a member", response.body
  end

  # --- Remove member ---

  test "owner removes a member" do
    member = User.create!(email_address: "remove@example.com", password: "password123")
    membership = @board.board_memberships.create!(user: member, role: :member)
    delete board_membership_path(@board, membership), headers: TURBO_HEADERS
    assert_response :success
    assert_not BoardMembership.exists?(membership.id)
    assert_match dom_id(membership), response.body  # turbo_stream.remove target
  end

  test "owner cannot remove themselves (owner row)" do
    owner_membership = @board.board_memberships.find_by!(user: @owner)
    delete board_membership_path(@board, owner_membership)
    assert_response :redirect
    assert BoardMembership.exists?(owner_membership.id)
  end

  # --- Collaborator access ---

  test "collaborator can view board" do
    member = User.create!(email_address: "collab@example.com", password: "password123")
    @board.board_memberships.create!(user: member, role: :member)
    sign_out
    sign_in_as member
    get board_path(@board)
    assert_response :success
  end

  test "collaborator can create a card" do
    swimlane = @board.swimlanes.create!(name: "Todo")
    member = User.create!(email_address: "collab2@example.com", password: "password123")
    @board.board_memberships.create!(user: member, role: :member)
    sign_out
    sign_in_as member
    post board_swimlane_cards_path(@board, swimlane),
         params: { card: { name: "New Card" } },
         headers: TURBO_HEADERS
    assert_response :success
    assert Card.exists?(name: "New Card")
  end

  test "collaborator cannot delete board" do
    member = User.create!(email_address: "collab3@example.com", password: "password123")
    @board.board_memberships.create!(user: member, role: :member)
    sign_out
    sign_in_as member
    delete board_path(@board)
    assert_response :not_found
    assert Board.exists?(@board.id)
  end

  test "collaborator cannot rename board" do
    member = User.create!(email_address: "collab4@example.com", password: "password123")
    @board.board_memberships.create!(user: member, role: :member)
    sign_out
    sign_in_as member
    patch board_path(@board), params: { board: { name: "Hijacked" } }
    assert_response :not_found
    assert_equal "Shared Board", @board.reload.name
  end

  # --- Non-member access ---

  test "non-member cannot view board (404)" do
    stranger = User.create!(email_address: "stranger@example.com", password: "password123")
    sign_out
    sign_in_as stranger
    get board_path(@board)
    assert_response :not_found
  end

  test "non-member cannot access swimlane on board (404)" do
    swimlane = @board.swimlanes.create!(name: "Lane")
    stranger = User.create!(email_address: "s2@example.com", password: "password123")
    sign_out
    sign_in_as stranger
    post board_swimlane_cards_path(@board, swimlane),
         params: { card: { name: "Hack" } }
    assert_response :not_found
  end

  # --- Membership on boards index ---

  test "shared board appears on collaborator boards index" do
    member = User.create!(email_address: "idx@example.com", password: "password123")
    @board.board_memberships.create!(user: member, role: :member)
    sign_out
    sign_in_as member
    get boards_path
    assert_response :success
    assert_match @board.name, response.body
  end

  # --- Non-member cannot add members ---

  test "non-member cannot add members to board" do
    stranger = User.create!(email_address: "s3@example.com", password: "password123")
    sign_out
    sign_in_as stranger
    post board_memberships_path(@board),
         params: { membership: { email_address: "anyone@example.com" } }
    assert_response :not_found
  end

  test "collaborator (member role) cannot add members to board" do
    member = User.create!(email_address: "collab5@example.com", password: "password123")
    @board.board_memberships.create!(user: member, role: :member)
    sign_out
    sign_in_as member
    post board_memberships_path(@board),
         params: { membership: { email_address: "anyone@example.com" } }
    assert_response :not_found
  end
end
```

Also update `test/integration/boards_flow_test.rb` — add owner memberships to all board creations:

```ruby
# Helper at bottom of class:
def create_owned_board(user, name:)
  board = Board.create!(name: name, user: user)
  board.board_memberships.create!(user: user, role: :owner)
  board
end
```

Replace all inline `Board.create!(name: ..., user: @user)` with `create_owned_board(@user, name: ...)`.

For `other_user` boards: `Board.create!(name: ..., user: other_user)` should also create owner membership for `other_user` (not `@user`), so the 404 tests continue to pass:
```ruby
other_board = Board.create!(name: "Private", user: other_user)
other_board.board_memberships.create!(user: other_user, role: :owner)
```

Apply same `create_owned_board` pattern to `swimlanes_flow_test.rb` and `cards_flow_test.rb`.

### Success Criteria
- [ ] `bin/rails test test/integration/memberships_flow_test.rb` passes (all tests)
- [ ] `bin/rails test test/integration/boards_flow_test.rb` passes (all tests unchanged)
- [ ] `bin/rails test test/integration/` passes (full integration suite)
- [ ] All Turbo Stream responses contain updated HTML (`assert_match` on `response.body`)

---

## Task 8: E2E Tests (Playwright)

### Overview
Add Playwright E2E specs for the full sharing flow: owner adds collaborator → collaborator sees board → owner removes collaborator → collaborator no longer sees board → non-member gets 404.

### Changes Required

**File**: `e2e/helpers/auth.js` — add `signIn` helper (for existing user) and `addMember` helper:
```js
// Sign in to an existing account (no registration)
export async function signIn(page, email, password = "password123") {
  await page.goto("/session/new");
  await page.getByLabel(/email/i).fill(email);
  await page.getByLabel(/password/i).fill(password);
  await page.getByRole("button", { name: /sign in/i }).click();
  await page.waitForURL("/");
}
```

**File**: `e2e/board_sharing.spec.js` (NEW):
```js
import { test, expect } from "@playwright/test";
import { signUp, signIn, uniqueEmail, createBoard } from "./helpers/auth.js";

test.describe("Board Sharing", () => {
  test("owner adds collaborator; collaborator sees board and can create card", async ({ browser }) => {
    // Two separate browser contexts = two independent sessions
    const ownerContext = await browser.newContext();
    const collabContext = await browser.newContext();
    const ownerPage = await ownerContext.newPage();
    const collabPage = await collabContext.newPage();

    const ownerEmail = uniqueEmail();
    const collabEmail = uniqueEmail();

    // Register both users
    await signUp(ownerPage, ownerEmail);
    await signUp(collabPage, collabEmail);

    // Owner creates a board
    const boardName = "Shared Project";
    await createBoard(ownerPage, boardName);
    await ownerPage.getByRole("link", { name: boardName }).click();

    // Owner adds collaborator
    await ownerPage.getByPlaceholder("Add member by email").fill(collabEmail);
    await ownerPage.getByRole("button", { name: "Add" }).click();
    await expect(ownerPage.locator("#memberships")).toContainText(collabEmail);

    // Collaborator navigates to boards index (reload)
    await collabPage.goto("/");
    await expect(collabPage.getByRole("link", { name: boardName })).toBeVisible();

    // Collaborator opens board and creates a card
    await collabPage.getByRole("link", { name: boardName }).click();
    // Add a swimlane first (collaborator can)
    await collabPage.getByPlaceholder(/swimlane name/i).fill("Lane 1");
    await collabPage.getByRole("button", { name: /add swimlane/i }).click();
    // Add card
    await collabPage.getByPlaceholder(/card name/i).first().fill("Test Card");
    await collabPage.getByRole("button", { name: /add card/i }).first().click();
    await expect(collabPage.getByText("Test Card")).toBeVisible();

    // Collaborator does NOT see Edit/Delete board controls
    await expect(collabPage.getByRole("link", { name: "Edit Board" })).not.toBeVisible();

    await ownerContext.close();
    await collabContext.close();
  });

  test("owner removes collaborator; collaborator no longer sees board", async ({ browser }) => {
    const ownerContext = await browser.newContext();
    const collabContext = await browser.newContext();
    const ownerPage = await ownerContext.newPage();
    const collabPage = await collabContext.newPage();

    const ownerEmail = uniqueEmail();
    const collabEmail = uniqueEmail();

    await signUp(ownerPage, ownerEmail);
    await signUp(collabPage, collabEmail);

    const boardName = "Temp Board";
    await createBoard(ownerPage, boardName);
    await ownerPage.getByRole("link", { name: boardName }).click();

    // Add collaborator
    await ownerPage.getByPlaceholder("Add member by email").fill(collabEmail);
    await ownerPage.getByRole("button", { name: "Add" }).click();
    await expect(ownerPage.locator("#memberships")).toContainText(collabEmail);

    // Remove collaborator
    await ownerPage.getByRole("button", { name: "Remove" }).first().click();
    await ownerPage.waitForTimeout(500); // confirm dialog
    await expect(ownerPage.locator("#memberships")).not.toContainText(collabEmail);

    // Collaborator reloads boards index
    await collabPage.goto("/");
    await expect(collabPage.getByRole("link", { name: boardName })).not.toBeVisible();

    await ownerContext.close();
    await collabContext.close();
  });

  test("non-member gets 404 accessing board directly", async ({ browser }) => {
    const ownerContext = await browser.newContext();
    const strangerContext = await browser.newContext();
    const ownerPage = await ownerContext.newPage();
    const strangerPage = await strangerContext.newPage();

    const ownerEmail = uniqueEmail();
    const strangerEmail = uniqueEmail();

    await signUp(ownerPage, ownerEmail);
    await signUp(strangerPage, strangerEmail);

    await createBoard(ownerPage, "Secret Board");
    // Navigate to boards index to get board URL
    await ownerPage.goto("/");
    const boardLink = ownerPage.getByRole("link", { name: "Secret Board" });
    const boardUrl = await boardLink.getAttribute("href");

    // Stranger navigates directly
    await strangerPage.goto(boardUrl);
    // Should show 404 or redirect — not the board content
    await expect(strangerPage.getByText("Secret Board")).not.toBeVisible();

    await ownerContext.close();
    await strangerContext.close();
  });
});
```

### Success Criteria
- [ ] `npx playwright test e2e/board_sharing.spec.js` passes (or all tests pass)
- [ ] E2E flows exercise real HTTP stack end-to-end

---

## Task 9: Documentation Updates

### Overview
Update AGENTS.md and README.md as required by the SPEC.

### Changes Required

**File**: `AGENTS.md` — add to data model section:
```
- board_memberships: board_id (FK → boards), user_id (FK → users), role (integer enum: 0=owner, 1=member), unique index on [board_id, user_id]
```

Update authorization section:
```
Authorization: all board/swimlane/card access is scoped via Board.accessible_by(Current.user), which joins board_memberships. Edit/delete board are owner-only (BoardMembership role=owner check). Members can create/edit/delete swimlanes and cards.

Routes: boards/:id/memberships (POST create, DELETE destroy) — owner only
```

**File**: `README.md` — mark Phase 4 complete; add sharing description:
```
- [x] Phase 4: Board sharing — owners can share boards with other registered users by email; collaborators can create/edit/delete swimlanes and cards; owner-only controls (rename/delete board) are hidden from collaborators
```

### Success Criteria
- [ ] AGENTS.md contains BoardMembership model documentation
- [ ] README.md Phase 4 entry has `✓` or `[x]` checkmark

---

## Testing Strategy

### Unit Tests

- **`BoardMembership` model** (`test/models/board_membership_test.rb`): validates presence of board/user/role; uniqueness constraint; `owner?`/`member?` enum predicates.
- **`Board` model** (`test/models/board_test.rb`): `accessible_by` scope returns member boards, excludes non-member boards.
- **Real DB**: No mocking. Use fixture data for model tests; inline record creation for integration tests.

### Integration Tests

- **`memberships_flow_test.rb`**: Full add-member flow (valid email → Turbo Stream; invalid email → error stream); remove-member (success; owner-protected); collaborator access (board/swimlanes/cards → 200; delete/rename board → 404); non-member access (→ 404); boards index shows shared boards; non-owner cannot call membership endpoints.
- **Regression**: All existing `boards_flow_test.rb`, `swimlanes_flow_test.rb`, `cards_flow_test.rb` tests updated to create owner memberships; all continue to pass.
- **Turbo Stream assertions**: `assert_match` on `response.body` — not just `model.reload`.

### E2E Tests (Playwright)

- Owner adds collaborator → member sees board → creates card ✓
- Owner removes collaborator → member no longer sees board ✓
- Non-member navigates to board URL → not shown board ✓

### Coverage

- `bin/rails test` with SimpleCov — must remain ≥ 80%.
- New `BoardMembership` model, `MembershipsController`, and updated controller paths are all exercised.

---

## Risk Assessment

- **Breaking existing tests**: All 5 auth check sites change; existing boards in tests lack memberships. *Mitigation*: Update every inline `Board.create!` in integration tests to also create the owner membership. Run full test suite after Task 3.
- **N+1 on boards index**: Each board card checking ownership for show/hide controls. *Mitigation*: Precompute `@owned_board_ids` in `BoardsController#index` (one extra query).
- **`require_owner!` double-query**: `set_board` already loads board via membership join; `require_owner!` is a second query. *Mitigation*: Acceptable for Phase 4; cache `@membership` if needed in Phase 5.
- **E2E test flakiness on Turbo Stream timing**: Playwright's `waitForTimeout` is brittle. *Mitigation*: Use `expect(locator).toContainText()` which auto-waits; avoid explicit timeouts where possible.
- **Fixture loading order**: `board_memberships.yml` references `boards` and `users` fixtures. *Mitigation*: Rails fixture loading handles FK ordering via `belongs_to` declarations — no manual ordering needed.
- **Missing `sign_out` helper in E2E**: Research shows `signUp`/`signIn` exist but `signOut` may not. *Mitigation*: Use separate browser contexts per user instead of sign-in/sign-out sequences in the same context.
