# Implementation Plan: Phase 2

## Overview
Deliver the core Trello-like canvas: Swimlane and Card models with full CRUD via Turbo Frames/Streams, drag-and-drop card reordering via SortableJS, and resolution of Phase 1 technical debt (explicit auth, strip validation, granular commits).

## Current State (from Research)
- `Board` model exists with `belongs_to :user`; no `has_many :swimlanes` yet
- `BoardsController#show` is empty (no swimlane data); `set_board` uses `Current.user.boards.find` — correct authorization pattern
- `ApplicationController` has implicit `before_action :require_authentication` via concern; no explicit line
- `config/importmap.rb` has no SortableJS pin; CSP policy is fully commented out (no CDN restriction)
- `<main class="container mx-auto mt-8 px-5 flex">` in layout — swimlane columns will be flex children; board show view needs `overflow-x-auto` wrapper
- Integration test pattern: `setup` + `sign_in_as`, inline data creation, assert `:not_found` for cross-user access
- E2E pattern: `signUp` helper duplicated per spec file; Phase 2 introduces shared `e2e/helpers/auth.js`

## Desired End State
After Phase 2 is complete:
- `db/schema.rb` has `swimlanes` (board_id, name, position) and `cards` (swimlane_id, name, position) tables
- `Swimlane` and `Card` models with validations, associations, and position defaults
- `Board` model has `has_many :swimlanes, dependent: :destroy` and strips name before validation
- `ApplicationController` has explicit `before_action :require_authentication`
- Nested routes: `boards/:board_id/swimlanes` and `boards/:board_id/swimlanes/:swimlane_id/cards`
- Board show page renders swimlane columns side-by-side with cards; Turbo Streams for create/delete; Turbo Frames for inline edit
- SortableJS Stimulus controller handles drag-and-drop; PATCH endpoint persists position changes
- All Minitest tests pass with ≥80% SimpleCov coverage
- E2E shared `helpers/auth.js` module used by all specs; drag-and-drop E2E test passes

**Verify**: `bin/rails test` passes; `npx playwright test` passes; `bin/rails routes` shows nested swimlane/card routes.

## What We're NOT Doing
- Card detail modal (descriptions, due dates, labels, checklists) — Phase 3
- Swimlane drag-to-reorder (column reordering) — Phase 3
- Board sharing / multi-user access — Phase 4
- Real-time ActionCable updates — Phase 5
- Board background customization — Phase 6
- Authentication system changes beyond adding the explicit `before_action` line
- Any new gems beyond SortableJS importmap pin

## Implementation Approach
Build in vertical slices, each committable independently: (1) technical debt fixes, (2) data layer, (3) nested routes + swimlane CRUD, (4) card CRUD, (5) drag-and-drop, (6) E2E tests. Each slice is testable before moving to the next. Turbo Streams handle create/delete DOM mutations (append/remove); Turbo Frames handle inline edit (replace). Position PATCH returns `head :ok` — client already reordered DOM, server just persists. SortableJS added via importmap CDN pin (CSP is disabled/commented out).

---

## Task 1: Technical Debt — Explicit Auth + Board Name Strip

### Overview
Add explicit `before_action :require_authentication` to `ApplicationController` and add `before_validation` strip to `Board` model. This is a debt cleanup with no user-visible changes.

### Changes Required

**File**: `app/controllers/application_controller.rb`
```ruby
class ApplicationController < ActionController::Base
  include Authentication
  before_action :require_authentication
  # Only allow modern browsers supporting webp images, web push, badges, import maps, CSS nesting, and CSS :has.
  allow_browser versions: :modern

  # Changes to the importmap will invalidate the etag for HTML responses
  stale_when_importmap_changes
end
```

**File**: `app/models/board.rb`
Add `before_validation` to strip name:
```ruby
class Board < ApplicationRecord
  belongs_to :user
  validates :name, presence: true
  before_validation { name&.strip! }
end
```

**File**: `test/models/board_test.rb`
Add test: whitespace-only name is invalid:
```ruby
test "is invalid with whitespace-only name" do
  board = Board.new(name: "   ", user: users(:one))
  assert_not board.valid?
  assert_includes board.errors[:name], "can't be blank"
end
```

### Success Criteria
- [ ] `ApplicationController` has explicit `before_action :require_authentication` line
- [ ] `Board` model strips name before validation; `"   "` is invalid
- [ ] `bin/rails test test/models/board_test.rb` passes
- [ ] No existing board tests broken

---

## Task 2: Swimlane and Card Models + Migrations

### Overview
Create `swimlanes` and `cards` tables with migrations; implement `Swimlane` and `Card` models with validations, associations, and position default logic. Add associations to `Board`.

### Changes Required

**File**: `db/migrate/TIMESTAMP_create_swimlanes.rb` (generate via `bin/rails g model Swimlane name:string position:integer board:references`)
```ruby
class CreateSwimlanes < ActiveRecord::Migration[8.0]
  def change
    create_table :swimlanes do |t|
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.references :board, null: false, foreign_key: true
      t.timestamps
    end
  end
end
```

**File**: `db/migrate/TIMESTAMP_create_cards.rb` (generate via `bin/rails g model Card name:string position:integer swimlane:references`)
```ruby
class CreateCards < ActiveRecord::Migration[8.0]
  def change
    create_table :cards do |t|
      t.string :name, null: false
      t.integer :position, null: false, default: 0
      t.references :swimlane, null: false, foreign_key: true
      t.timestamps
    end
  end
end
```

**File**: `app/models/swimlane.rb`
```ruby
class Swimlane < ApplicationRecord
  belongs_to :board
  has_many :cards, dependent: :destroy

  validates :name, presence: true
  before_validation { name&.strip! }

  before_create :set_position

  private

  def set_position
    self.position = (board.swimlanes.maximum(:position) || -1) + 1
  end
end
```

**File**: `app/models/card.rb`
```ruby
class Card < ApplicationRecord
  belongs_to :swimlane

  validates :name, presence: true
  before_validation { name&.strip! }

  before_create :set_position

  private

  def set_position
    self.position = (swimlane.cards.maximum(:position) || -1) + 1
  end
end
```

**File**: `app/models/board.rb`
Add association:
```ruby
has_many :swimlanes, dependent: :destroy
```

**File**: `test/models/swimlane_test.rb` (new)
```ruby
require "test_helper"

class SwimlaneTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "lane@test.com", password: "password123", password_confirmation: "password123")
    @board = @user.boards.create!(name: "Test Board")
  end

  test "is valid with name and board" do
    swimlane = Swimlane.new(name: "To Do", board: @board)
    assert swimlane.valid?
  end

  test "is invalid without name" do
    swimlane = Swimlane.new(name: nil, board: @board)
    assert_not swimlane.valid?
    assert_includes swimlane.errors[:name], "can't be blank"
  end

  test "is invalid with whitespace-only name" do
    swimlane = Swimlane.new(name: "   ", board: @board)
    assert_not swimlane.valid?
    assert_includes swimlane.errors[:name], "can't be blank"
  end

  test "is invalid without board" do
    swimlane = Swimlane.new(name: "To Do")
    assert_not swimlane.valid?
  end

  test "auto-assigns position on create" do
    first = @board.swimlanes.create!(name: "First")
    second = @board.swimlanes.create!(name: "Second")
    assert_equal 0, first.position
    assert_equal 1, second.position
  end

  test "belongs to board" do
    swimlane = @board.swimlanes.create!(name: "Lane")
    assert_equal @board, swimlane.board
  end

  test "destroying swimlane destroys its cards" do
    swimlane = @board.swimlanes.create!(name: "Lane")
    swimlane.cards.create!(name: "Card 1")
    swimlane.cards.create!(name: "Card 2")
    assert_difference "Card.count", -2 do
      swimlane.destroy
    end
  end
end
```

**File**: `test/models/card_test.rb` (new)
```ruby
require "test_helper"

class CardTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "card@test.com", password: "password123", password_confirmation: "password123")
    @board = @user.boards.create!(name: "Board")
    @swimlane = @board.swimlanes.create!(name: "Lane")
  end

  test "is valid with name and swimlane" do
    card = Card.new(name: "Task", swimlane: @swimlane)
    assert card.valid?
  end

  test "is invalid without name" do
    card = Card.new(name: nil, swimlane: @swimlane)
    assert_not card.valid?
    assert_includes card.errors[:name], "can't be blank"
  end

  test "is invalid with whitespace-only name" do
    card = Card.new(name: "   ", swimlane: @swimlane)
    assert_not card.valid?
    assert_includes card.errors[:name], "can't be blank"
  end

  test "is invalid without swimlane" do
    card = Card.new(name: "Task")
    assert_not card.valid?
  end

  test "auto-assigns position on create" do
    first = @swimlane.cards.create!(name: "First")
    second = @swimlane.cards.create!(name: "Second")
    assert_equal 0, first.position
    assert_equal 1, second.position
  end

  test "belongs to swimlane" do
    card = @swimlane.cards.create!(name: "Task")
    assert_equal @swimlane, card.swimlane
  end
end
```

### Success Criteria
- [ ] `bin/rails db:migrate` runs without error
- [ ] `db/schema.rb` contains `swimlanes` and `cards` tables with correct columns and foreign keys
- [ ] `bin/rails test test/models/swimlane_test.rb test/models/card_test.rb` passes
- [ ] Cascade destroy verified: deleting a board destroys its swimlanes and cards

---

## Task 3: Nested Routes + SwimlanesController

### Overview
Add nested routes for swimlanes and cards. Implement `SwimlanesController` with full CRUD scoped to the board owner. Promote `boards#show` to load swimlanes with cards.

### Changes Required

**File**: `config/routes.rb`
```ruby
Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :registration, only: [:new, :create]

  resources :boards do
    resources :swimlanes, only: [:create, :update, :destroy] do
      resources :cards, only: [:create, :update, :destroy]
    end
  end
  root "boards#index"

  get "up" => "rails/health#show", as: :rails_health_check
end
```

Note: `index`, `new`, `edit`, `show` routes for swimlanes and cards are omitted — all UI is inline within the board canvas.

**File**: `app/controllers/boards_controller.rb`
Update `show` action:
```ruby
def show
  @swimlanes = @board.swimlanes.order(:position).includes(:cards)
end
```

**File**: `app/controllers/swimlanes_controller.rb` (new)
```ruby
class SwimlanesController < ApplicationController
  before_action :set_board
  before_action :set_swimlane, only: [:update, :destroy]

  def create
    @swimlane = @board.swimlanes.build(swimlane_params)
    if @swimlane.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @board }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("new_swimlane_form", partial: "swimlanes/form", locals: { board: @board, swimlane: @swimlane }) }
        format.html { redirect_to @board }
      end
    end
  end

  def update
    if @swimlane.update(swimlane_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @board }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace(dom_id(@swimlane, :edit_form), partial: "swimlanes/edit_form", locals: { board: @board, swimlane: @swimlane }) }
        format.html { redirect_to @board }
      end
    end
  end

  def destroy
    @swimlane.destroy
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(dom_id(@swimlane)) }
      format.html { redirect_to @board }
    end
  end

  private

  def set_board
    @board = Current.user.boards.find(params[:board_id])
  end

  def set_swimlane
    @swimlane = @board.swimlanes.find(params[:id])
  end

  def swimlane_params
    params.require(:swimlane).permit(:name)
  end
end
```

**File**: `test/integration/swimlanes_flow_test.rb` (new)
```ruby
require "test_helper"

class SwimlanesFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "swim@test.com", password: "password123", password_confirmation: "password123")
    @board = @user.boards.create!(name: "My Board")
    sign_in_as @user
  end

  test "creates a swimlane" do
    assert_difference "Swimlane.count" do
      post board_swimlanes_path(@board), params: { swimlane: { name: "To Do" } }
    end
    assert_response :success
  end

  test "rejects blank swimlane name" do
    assert_no_difference "Swimlane.count" do
      post board_swimlanes_path(@board), params: { swimlane: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "rejects whitespace-only swimlane name" do
    assert_no_difference "Swimlane.count" do
      post board_swimlanes_path(@board), params: { swimlane: { name: "   " } }
    end
    assert_response :unprocessable_entity
  end

  test "updates a swimlane name" do
    swimlane = @board.swimlanes.create!(name: "Old Name")
    patch board_swimlane_path(@board, swimlane), params: { swimlane: { name: "New Name" } }
    assert_response :success
    assert_equal "New Name", swimlane.reload.name
  end

  test "destroys a swimlane and its cards" do
    swimlane = @board.swimlanes.create!(name: "Lane")
    swimlane.cards.create!(name: "Card A")
    assert_difference ["Swimlane.count", "Card.count"], -1 do
      delete board_swimlane_path(@board, swimlane)
    end
    assert_response :success
  end

  test "cannot create swimlane on another user's board" do
    other_board = User.create!(email_address: "other@test.com", password: "pass1234", password_confirmation: "pass1234").boards.create!(name: "Other")
    post board_swimlanes_path(other_board), params: { swimlane: { name: "Lane" } }
    assert_response :not_found
  end

  test "unauthenticated request redirects to login" do
    sign_out
    post board_swimlanes_path(@board), params: { swimlane: { name: "Lane" } }
    assert_redirected_to new_session_path
  end
end
```

### Success Criteria
- [ ] `bin/rails routes | grep swimlane` shows nested routes under `boards`
- [ ] `bin/rails routes | grep card` shows doubly-nested routes under `boards/swimlanes`
- [ ] `boards#show` assigns `@swimlanes` with cards eager-loaded
- [ ] `bin/rails test test/integration/swimlanes_flow_test.rb` passes
- [ ] Cross-user swimlane create returns 404
- [ ] Unauthenticated request redirects to login

---

## Task 4: Board Canvas View + Swimlane Partials

### Overview
Build the board show view as a horizontal swimlane canvas. Each lane shows its cards and an "Add card" form. An "Add lane" form sits at the end. Inline edit forms use Turbo Frames.

### Changes Required

**File**: `app/views/boards/show.html.erb`
```erb
<div class="flex flex-col h-full">
  <div class="flex justify-between items-center mb-4 px-4 pt-4">
    <h1 class="text-2xl font-bold"><%= @board.name %></h1>
    <div class="flex gap-2">
      <%= link_to "Edit Board", edit_board_path(@board), class: "text-sm text-blue-600 hover:underline" %>
      <%= link_to "Back to Boards", boards_path, class: "text-sm text-gray-600 hover:underline" %>
    </div>
  </div>

  <div class="flex gap-4 overflow-x-auto px-4 pb-4 items-start" id="swimlanes">
    <%= render @swimlanes %>

    <div class="flex-shrink-0 w-64">
      <%= turbo_frame_tag "new_swimlane_form" do %>
        <%= render "swimlanes/new_form", board: @board, swimlane: Swimlane.new %>
      <% end %>
    </div>
  </div>
</div>
```

**File**: `app/views/swimlanes/_swimlane.html.erb` (new)
```erb
<%= turbo_frame_tag dom_id(swimlane), class: "flex-shrink-0 w-64 bg-gray-100 rounded-lg p-3 flex flex-col gap-2" do %>
  <div class="flex justify-between items-center">
    <%= turbo_frame_tag dom_id(swimlane, :header) do %>
      <span class="font-semibold text-sm"><%= swimlane.name %></span>
      <div class="flex gap-1">
        <%= link_to "Rename", "#", data: { turbo_frame: dom_id(swimlane, :header) }, class: "text-xs text-blue-500 hover:underline" %>
        <%= button_to "Delete", board_swimlane_path(swimlane.board, swimlane), method: :delete,
            data: { turbo_confirm: "Delete \"#{swimlane.name}\" and all its cards?" },
            class: "text-xs text-red-500 hover:underline bg-transparent border-0 cursor-pointer p-0" %>
      </div>
    <% end %>
  </div>

  <div id="<%= dom_id(swimlane, :cards) %>"
       class="flex flex-col gap-2 min-h-4"
       data-controller="sortable"
       data-sortable-url-value="<%= board_swimlane_cards_path(swimlane.board, swimlane) %>"
       data-sortable-swimlane-id-value="<%= swimlane.id %>">
    <%= render swimlane.cards.order(:position) %>
  </div>

  <%= turbo_frame_tag dom_id(swimlane, :new_card_form) do %>
    <%= render "cards/new_form", board: swimlane.board, swimlane: swimlane, card: Card.new %>
  <% end %>
<% end %>
```

**File**: `app/views/swimlanes/_new_form.html.erb` (new)
```erb
<%= form_with url: board_swimlanes_path(board), model: swimlane, data: { turbo_frame: "new_swimlane_form" } do |f| %>
  <% if swimlane.errors.any? %>
    <p class="text-red-500 text-xs mb-1"><%= swimlane.errors.full_messages.to_sentence %></p>
  <% end %>
  <div class="flex gap-1">
    <%= f.text_field :name, placeholder: "Lane name...", class: "flex-1 text-sm border rounded px-2 py-1" %>
    <%= f.submit "Add", class: "text-sm bg-blue-500 text-white px-2 py-1 rounded hover:bg-blue-600 cursor-pointer" %>
  </div>
<% end %>
```

**File**: `app/views/swimlanes/_edit_form.html.erb` (new)
```erb
<%= form_with url: board_swimlane_path(board, swimlane), model: swimlane, method: :patch,
    data: { turbo_frame: dom_id(swimlane, :header) } do |f| %>
  <% if swimlane.errors.any? %>
    <p class="text-red-500 text-xs mb-1"><%= swimlane.errors.full_messages.to_sentence %></p>
  <% end %>
  <div class="flex gap-1">
    <%= f.text_field :name, class: "flex-1 text-sm border rounded px-2 py-1" %>
    <%= f.submit "Save", class: "text-sm bg-blue-500 text-white px-2 py-1 rounded hover:bg-blue-600 cursor-pointer" %>
  </div>
<% end %>
```

**File**: `app/views/swimlanes/create.turbo_stream.erb` (new)
```erb
<%= turbo_stream.append "swimlanes", partial: "swimlanes/swimlane", locals: { swimlane: @swimlane } %>
<%= turbo_stream.replace "new_swimlane_form", partial: "swimlanes/new_form", locals: { board: @board, swimlane: Swimlane.new } %>
```

**File**: `app/views/swimlanes/update.turbo_stream.erb` (new)
```erb
<%= turbo_stream.replace dom_id(@swimlane, :header), partial: "swimlanes/header", locals: { swimlane: @swimlane } %>
```

**File**: `app/views/swimlanes/_header.html.erb` (new)
```erb
<%= turbo_frame_tag dom_id(swimlane, :header) do %>
  <span class="font-semibold text-sm"><%= swimlane.name %></span>
  <div class="flex gap-1">
    <%= link_to "Rename", "#", data: { turbo_frame: dom_id(swimlane, :header) }, class: "text-xs text-blue-500 hover:underline" %>
    <%= button_to "Delete", board_swimlane_path(swimlane.board, swimlane), method: :delete,
        data: { turbo_confirm: "Delete \"#{swimlane.name}\" and all its cards?" },
        class: "text-xs text-red-500 hover:underline bg-transparent border-0 cursor-pointer p-0" %>
  </div>
<% end %>
```

Note on inline Rename: The Rename link targets `dom_id(swimlane, :header)` Turbo Frame. The link needs to point to an endpoint that returns the edit form. Add a GET route for `swimlanes#edit` in routes, returning the edit form partial. Alternatively, render the edit form initially hidden and toggle it — but the Turbo Frame approach is cleaner and aligns with the existing pattern. Add `edit` to swimlane routes.

**Updated routes**:
```ruby
resources :swimlanes, only: [:create, :edit, :update, :destroy] do
```

**File**: `app/controllers/swimlanes_controller.rb` — add `edit` action:
```ruby
def edit
  render partial: "swimlanes/edit_form", locals: { board: @board, swimlane: @swimlane }
end
```
Add `edit` to `set_swimlane` before_action.

### Success Criteria
- [ ] Navigating to `/boards/:id` shows board name + swimlane columns side-by-side
- [ ] "Add Lane" form at the end; submitting appends lane without full page reload (Turbo Stream)
- [ ] Clicking "Rename" on a lane shows an inline edit form in that lane's header (Turbo Frame)
- [ ] Saving rename updates lane header (Turbo Stream replace)
- [ ] Clicking "Delete" on a lane removes it + its cards immediately (Turbo Stream remove)
- [ ] Empty/whitespace lane name shows validation error inline

---

## Task 5: CardsController + Card Partials

### Overview
Implement `CardsController` with full CRUD scoped through board ownership chain. Add card views with inline edit via Turbo Frames and create/delete via Turbo Streams.

### Changes Required

**File**: `app/controllers/cards_controller.rb` (new)
```ruby
class CardsController < ApplicationController
  before_action :set_board
  before_action :set_swimlane
  before_action :set_card, only: [:edit, :update, :destroy]

  def create
    @card = @swimlane.cards.build(card_params)
    if @card.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @board }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace(dom_id(@swimlane, :new_card_form), partial: "cards/new_form", locals: { board: @board, swimlane: @swimlane, card: @card }), status: :unprocessable_entity }
        format.html { redirect_to @board }
      end
    end
  end

  def edit
    render partial: "cards/edit_form", locals: { board: @board, swimlane: @swimlane, card: @card }
  end

  def update
    if @card.update(card_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @board }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace(dom_id(@card, :edit_form), partial: "cards/edit_form", locals: { board: @board, swimlane: @swimlane, card: @card }), status: :unprocessable_entity }
        format.html { redirect_to @board }
      end
    end
  end

  def destroy
    @card.destroy
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(dom_id(@card)) }
      format.html { redirect_to @board }
    end
  end

  # PATCH endpoint for drag-and-drop position update
  # Routed via: patch 'reorder' on collection, or custom route
  # See Task 6 for the position action

  private

  def set_board
    @board = Current.user.boards.find(params[:board_id])
  end

  def set_swimlane
    @swimlane = @board.swimlanes.find(params[:swimlane_id])
  end

  def set_card
    @card = @swimlane.cards.find(params[:id])
  end

  def card_params
    params.require(:card).permit(:name)
  end
end
```

**File**: `app/views/cards/_card.html.erb` (new)
```erb
<div id="<%= dom_id(card) %>"
     class="bg-white rounded shadow-sm p-2 text-sm cursor-grab"
     data-card-id="<%= card.id %>"
     data-swimlane-id="<%= card.swimlane_id %>">
  <%= turbo_frame_tag dom_id(card, :name) do %>
    <div class="flex justify-between items-center">
      <span><%= card.name %></span>
      <div class="flex gap-1 opacity-0 group-hover:opacity-100">
        <%= link_to "✎", edit_board_swimlane_card_path(card.swimlane.board, card.swimlane, card),
            class: "text-xs text-blue-400 hover:text-blue-600",
            data: { turbo_frame: dom_id(card, :name) } %>
        <%= button_to "✕", board_swimlane_card_path(card.swimlane.board, card.swimlane, card),
            method: :delete,
            class: "text-xs text-red-400 hover:text-red-600 bg-transparent border-0 cursor-pointer p-0",
            data: { turbo_confirm: "Delete this card?" } %>
      </div>
    </div>
  <% end %>
</div>
```

**File**: `app/views/cards/_new_form.html.erb` (new)
```erb
<%= turbo_frame_tag dom_id(swimlane, :new_card_form) do %>
  <%= form_with url: board_swimlane_cards_path(board, swimlane), model: card do |f| %>
    <% if card.errors.any? %>
      <p class="text-red-500 text-xs mb-1"><%= card.errors.full_messages.to_sentence %></p>
    <% end %>
    <div class="flex gap-1">
      <%= f.text_field :name, placeholder: "Card name...", class: "flex-1 text-xs border rounded px-2 py-1" %>
      <%= f.submit "Add", class: "text-xs bg-green-500 text-white px-2 py-1 rounded hover:bg-green-600 cursor-pointer" %>
    </div>
  <% end %>
<% end %>
```

**File**: `app/views/cards/_edit_form.html.erb` (new)
```erb
<%= turbo_frame_tag dom_id(card, :name) do %>
  <%= form_with url: board_swimlane_card_path(board, swimlane, card), model: card, method: :patch do |f| %>
    <% if card.errors.any? %>
      <p class="text-red-500 text-xs mb-1"><%= card.errors.full_messages.to_sentence %></p>
    <% end %>
    <div class="flex gap-1">
      <%= f.text_field :name, class: "flex-1 text-xs border rounded px-2 py-1" %>
      <%= f.submit "Save", class: "text-xs bg-blue-500 text-white px-2 py-1 rounded hover:bg-blue-600 cursor-pointer" %>
    </div>
  <% end %>
<% end %>
```

**File**: `app/views/cards/create.turbo_stream.erb` (new)
```erb
<%= turbo_stream.append dom_id(@swimlane, :cards), partial: "cards/card", locals: { card: @card } %>
<%= turbo_stream.replace dom_id(@swimlane, :new_card_form), partial: "cards/new_form", locals: { board: @board, swimlane: @swimlane, card: Card.new } %>
```

**File**: `app/views/cards/update.turbo_stream.erb` (new)
```erb
<%= turbo_stream.replace dom_id(@card, :name), partial: "cards/card_name", locals: { card: @card } %>
```

Add `cards/edit` route — update routes to include `edit`:
```ruby
resources :cards, only: [:create, :edit, :update, :destroy]
```

**File**: `test/integration/cards_flow_test.rb` (new)
```ruby
require "test_helper"

class CardsFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "cards@test.com", password: "password123", password_confirmation: "password123")
    @board = @user.boards.create!(name: "Board")
    @swimlane = @board.swimlanes.create!(name: "Lane")
    sign_in_as @user
  end

  test "creates a card" do
    assert_difference "Card.count" do
      post board_swimlane_cards_path(@board, @swimlane), params: { card: { name: "My Task" } }
    end
    assert_response :success
  end

  test "rejects blank card name" do
    assert_no_difference "Card.count" do
      post board_swimlane_cards_path(@board, @swimlane), params: { card: { name: "" } }
    end
    assert_response :unprocessable_entity
  end

  test "rejects whitespace-only card name" do
    assert_no_difference "Card.count" do
      post board_swimlane_cards_path(@board, @swimlane), params: { card: { name: "   " } }
    end
    assert_response :unprocessable_entity
  end

  test "updates a card name" do
    card = @swimlane.cards.create!(name: "Old")
    patch board_swimlane_card_path(@board, @swimlane, card), params: { card: { name: "New" } }
    assert_response :success
    assert_equal "New", card.reload.name
  end

  test "destroys a card" do
    card = @swimlane.cards.create!(name: "Task")
    assert_difference "Card.count", -1 do
      delete board_swimlane_card_path(@board, @swimlane, card)
    end
    assert_response :success
  end

  test "cannot create card on another user's board" do
    other_user = User.create!(email_address: "z@test.com", password: "pass1234", password_confirmation: "pass1234")
    other_board = other_user.boards.create!(name: "Other")
    other_lane = other_board.swimlanes.create!(name: "Lane")
    post board_swimlane_cards_path(other_board, other_lane), params: { card: { name: "Hack" } }
    assert_response :not_found
  end
end
```

### Success Criteria
- [ ] Cards render within their swimlane column, ordered by position
- [ ] "Add card" form at bottom of each lane; submitting appends card via Turbo Stream
- [ ] Clicking edit icon shows inline edit form (Turbo Frame); saving updates card name
- [ ] Delete removes card immediately via Turbo Stream
- [ ] Whitespace-only card name shows validation error
- [ ] `bin/rails test test/integration/cards_flow_test.rb` passes
- [ ] Cross-user card create returns 404

---

## Task 6: SortableJS Drag-and-Drop + Position PATCH Endpoint

### Overview
Add SortableJS via importmap, implement a Stimulus controller that initializes Sortable on card lists, and add a `position` action to `CardsController` that persists the new card order (including cross-lane moves).

### Changes Required

**Step 1 — Pin SortableJS**:
```bash
./bin/importmap pin sortablejs
```
This adds a line to `config/importmap.rb` like:
```
pin "sortablejs", to: "https://cdn.jsdelivr.net/npm/sortablejs@1.15.6/Sortable.min.js"
```

**File**: `app/javascript/controllers/sortable_controller.js` (new)
```javascript
import { Controller } from "@hotwired/stimulus"
import Sortable from "sortablejs"

export default class extends Controller {
  static values = {
    url: String,
    swimlaneId: Number
  }

  connect() {
    this.sortable = Sortable.create(this.element, {
      group: "cards",          // shared group enables cross-lane dragging
      animation: 150,
      ghostClass: "opacity-50",
      onEnd: this.onEnd.bind(this)
    })
  }

  disconnect() {
    this.sortable?.destroy()
  }

  onEnd(event) {
    const cardId = event.item.dataset.cardId
    const newSwimlaneId = event.to.dataset.sortableSwimlaneIdValue
    const position = event.newIndex

    const url = event.to.dataset.sortableUrlValue

    fetch(url + "/reorder", {
      method: "PATCH",
      headers: {
        "Content-Type": "application/json",
        "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
      },
      body: JSON.stringify({ card_id: cardId, position: position, swimlane_id: newSwimlaneId })
    })
  }
}
```

**File**: `config/routes.rb` — add reorder route:
```ruby
resources :cards, only: [:create, :edit, :update, :destroy] do
  collection do
    patch :reorder
  end
end
```

Wait — `reorder` needs to identify a specific card. Use a member route instead:
```ruby
resources :cards, only: [:create, :edit, :update, :destroy] do
  member do
    patch :reorder
  end
end
```

This gives `reorder_board_swimlane_card_path(board, swimlane, card)`.

However, since cards can move between swimlanes, the `swimlane_id` in the URL may be the *original* swimlane. The controller must accept `swimlane_id` from the request body and update `card.swimlane_id` accordingly.

**Alternative approach** — use a dedicated position update endpoint on the new swimlane's cards collection:
```
PATCH /boards/:board_id/swimlanes/:swimlane_id/cards/reorder
```
Body: `{ card_id: X, position: Y }` — where `:swimlane_id` is the *destination* swimlane.

Use collection route:
```ruby
resources :cards, only: [:create, :edit, :update, :destroy] do
  collection do
    patch :reorder
  end
end
```

**Decision**: Use `PATCH /boards/:board_id/swimlanes/:swimlane_id/cards/reorder` with destination swimlane in URL and `card_id` + `position` in body. This is clean and self-documenting.

**Update Stimulus controller** — send to destination swimlane URL:
```javascript
onEnd(event) {
  const cardId = event.item.dataset.cardId
  const position = event.newIndex
  const reorderUrl = event.to.dataset.sortableUrlValue.replace('/cards', '/cards/reorder')

  fetch(reorderUrl, {
    method: "PATCH",
    headers: {
      "Content-Type": "application/json",
      "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]').content
    },
    body: JSON.stringify({ card_id: cardId, position: position })
  })
}
```

Update swimlane partial: `data-sortable-url-value` points to `board_swimlane_cards_path`.

**File**: `app/controllers/cards_controller.rb` — add `reorder` action:
```ruby
def reorder
  card = Card.find(params[:card_id])
  # Verify card belongs to current user's board chain
  unless Current.user.boards.joins(swimlanes: :cards).where(cards: { id: card.id }).exists?
    raise ActiveRecord::RecordNotFound
  end

  card.update!(
    swimlane_id: @swimlane.id,
    position: params[:position].to_i
  )

  # Resequence positions in destination swimlane (excluding the moved card)
  @swimlane.cards.where.not(id: card.id).order(:position).each_with_index do |c, idx|
    new_pos = idx < params[:position].to_i ? idx : idx + 1
    c.update_columns(position: new_pos)
  end

  head :ok
end
```

Note: `reorder` is a collection action so `set_swimlane` runs but `set_card` does not. The `before_action` chain should be updated accordingly.

**Simpler resequencing approach**: After moving the card, reassign all cards in the destination swimlane contiguous positions:
```ruby
def reorder
  card = Card.find(params[:card_id])
  unless Current.user.boards.joins(swimlanes: :cards).where(cards: { id: card.id }).exists?
    raise ActiveRecord::RecordNotFound
  end

  target_position = params[:position].to_i

  # Move card to destination swimlane
  card.update!(swimlane_id: @swimlane.id)

  # Rebuild positions in destination swimlane
  cards = @swimlane.cards.order(:position).to_a
  cards.delete(card)
  cards.insert(target_position, card)
  cards.each_with_index { |c, i| c.update_columns(position: i) }

  head :ok
end
```

**File**: `test/integration/cards_reorder_test.rb` (new)
```ruby
require "test_helper"

class CardsReorderTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "reorder@test.com", password: "password123", password_confirmation: "password123")
    @board = @user.boards.create!(name: "Board")
    @lane1 = @board.swimlanes.create!(name: "Lane 1")
    @lane2 = @board.swimlanes.create!(name: "Lane 2")
    @card1 = @lane1.cards.create!(name: "First")
    @card2 = @lane1.cards.create!(name: "Second")
    sign_in_as @user
  end

  test "reorders cards within the same lane" do
    patch reorder_board_swimlane_cards_path(@board, @lane1),
      params: { card_id: @card2.id, position: 0 },
      as: :json
    assert_response :ok
    assert_equal 0, @card2.reload.position
    assert_equal 1, @card1.reload.position
  end

  test "moves card to another lane" do
    patch reorder_board_swimlane_cards_path(@board, @lane2),
      params: { card_id: @card1.id, position: 0 },
      as: :json
    assert_response :ok
    assert_equal @lane2.id, @card1.reload.swimlane_id
  end

  test "cannot reorder card from another user's board" do
    other_user = User.create!(email_address: "evil@test.com", password: "pass1234", password_confirmation: "pass1234")
    other_board = other_user.boards.create!(name: "Evil")
    other_lane = other_board.swimlanes.create!(name: "Lane")
    other_card = other_lane.cards.create!(name: "Card")
    patch reorder_board_swimlane_cards_path(@board, @lane1),
      params: { card_id: other_card.id, position: 0 },
      as: :json
    assert_response :not_found
  end
end
```

### Success Criteria
- [ ] `config/importmap.rb` has a SortableJS pin
- [ ] `sortable_controller.js` exists and is auto-loaded
- [ ] Dragging a card within a lane reorders it; reloading the page shows the new order
- [ ] Dragging a card to another lane moves it; reloading shows it in the new lane
- [ ] `bin/rails test test/integration/cards_reorder_test.rb` passes
- [ ] Cross-user card reorder returns 404

---

## Task 7: E2E Tests (Playwright)

### Overview
Refactor E2E tests to use a shared `helpers/auth.js` module. Add a new `e2e/board_canvas.spec.js` that tests the full board canvas: create swimlane, create card, rename card, delete card, delete swimlane, drag card within a lane, drag card between lanes (verify persistence after reload).

### Changes Required

**File**: `e2e/helpers/auth.js` (new)
```javascript
const PASSWORD = 'password123';

export function uniqueEmail(prefix = 'test') {
  return `${prefix}_${Date.now()}_${Math.random().toString(36).slice(2)}@example.com`;
}

export async function signUp(page, email) {
  await page.goto('/registration/new');
  await page.fill('[name="user[email_address]"]', email);
  await page.fill('[name="user[password]"]', PASSWORD);
  await page.fill('[name="user[password_confirmation]"]', PASSWORD);
  await page.click('[type="submit"]');
  await page.waitForURL('/boards');
}

export async function createBoard(page, name) {
  await page.click('text=New Board');
  await page.fill('[name="board[name]"]', name);
  await page.click('[type="submit"]');
  await page.waitForURL('/boards');
  await page.click(`text=${name}`);
}
```

**File**: `e2e/auth.spec.js` — update to import from `helpers/auth.js`
**File**: `e2e/boards.spec.js` — update to import from `helpers/auth.js`

**File**: `e2e/board_canvas.spec.js` (new)
```javascript
import { test, expect } from '@playwright/test';
import { signUp, uniqueEmail, createBoard } from './helpers/auth.js';

test.describe('Board Canvas', () => {
  let email;

  test.beforeEach(async ({ page }) => {
    email = uniqueEmail('canvas');
    await signUp(page, email);
    await createBoard(page, 'My Canvas Board');
  });

  test('create and delete a swimlane', async ({ page }) => {
    await page.fill('[placeholder="Lane name..."]', 'To Do');
    await page.click('button:has-text("Add")');
    await expect(page.locator('text=To Do')).toBeVisible();

    page.on('dialog', d => d.accept());
    await page.click('button:has-text("Delete"):near(:text("To Do"))');
    await expect(page.locator('text=To Do')).not.toBeVisible();
  });

  test('create a card in a lane', async ({ page }) => {
    await page.fill('[placeholder="Lane name..."]', 'In Progress');
    await page.click('button:has-text("Add")');

    await page.fill('[placeholder="Card name..."]', 'Write tests');
    await page.click('button:has-text("Add"):near(:text("Card name"))');
    await expect(page.locator('text=Write tests')).toBeVisible();
  });

  test('drag card within a lane persists after reload', async ({ page }) => {
    // Setup: create lane + 2 cards
    await page.fill('[placeholder="Lane name..."]', 'Sprint');
    await page.click('button:has-text("Add")');
    await page.fill('[placeholder="Card name..."]', 'Card A');
    await page.click('button:has-text("Add"):near(:text("Card name"))');
    await page.fill('[placeholder="Card name..."]', 'Card B');
    await page.click('button:has-text("Add"):near(:text("Card name"))');

    // Drag Card A below Card B
    const cardA = page.locator('[data-card-id]').filter({ hasText: 'Card A' });
    const cardB = page.locator('[data-card-id]').filter({ hasText: 'Card B' });
    await cardA.dragTo(cardB);

    await page.reload();

    const cards = page.locator('[data-card-id]');
    await expect(cards.nth(0)).toContainText('Card B');
    await expect(cards.nth(1)).toContainText('Card A');
  });

  test('drag card between lanes persists after reload', async ({ page }) => {
    // Create two lanes
    await page.fill('[placeholder="Lane name..."]', 'To Do');
    await page.click('button:has-text("Add")');
    await page.fill('[placeholder="Lane name..."]', 'Done');
    await page.click('button:has-text("Add")');

    // Add card to To Do
    const todoCards = page.locator('[data-controller="sortable"]').first();
    await page.fill(todoCards.locator('[placeholder="Card name..."]'), 'My Task');
    await todoCards.locator('button:has-text("Add")').click();

    // Drag to Done
    const card = page.locator('[data-card-id]').filter({ hasText: 'My Task' });
    const doneColumn = page.locator('[data-controller="sortable"]').last();
    await card.dragTo(doneColumn);

    await page.reload();
    await expect(doneColumn.locator('text=My Task')).toBeVisible();
  });
});
```

**Update `playwright.config.js`** if needed to support ES module imports (check if `type: "module"` is in `package.json`).

### Success Criteria
- [ ] `e2e/helpers/auth.js` exists and exports `signUp`, `uniqueEmail`, `createBoard`
- [ ] `e2e/auth.spec.js` and `e2e/boards.spec.js` import from shared helper (no duplicate `signUp`)
- [ ] `npx playwright test e2e/board_canvas.spec.js` passes all tests
- [ ] Drag-and-drop tests verify persistence after `page.reload()`

---

## Task 8: Documentation Updates

### Overview
Update AGENTS.md and README.md per SPEC requirements.

### Changes Required

**File**: `AGENTS.md` — add section on Phase 2 additions:
- SortableJS: added via `./bin/importmap pin sortablejs`; Stimulus controller in `app/javascript/controllers/sortable_controller.js`
- Nested route structure: `/boards/:board_id/swimlanes/:swimlane_id/cards`
- Position update pattern: `PATCH /boards/:board_id/swimlanes/:swimlane_id/cards/reorder` with JSON body `{card_id, position}`
- Authorization chain: `Current.user.boards.find → .swimlanes.find → .cards.find`

**File**: `README.md` — update feature list to include Swimlanes and Cards

### Success Criteria
- [ ] AGENTS.md documents SortableJS setup, nested routes, position update pattern
- [ ] README.md feature list includes Swimlanes and Cards

---

## Testing Strategy

### Unit Tests
- `test/models/swimlane_test.rb`: validations (blank name, whitespace name, missing board), position auto-increment, cascade destroy
- `test/models/card_test.rb`: validations (blank name, whitespace name, missing swimlane), position auto-increment
- `test/models/board_test.rb`: add whitespace-only name test

### Integration/E2E Tests
- `test/integration/swimlanes_flow_test.rb`: CRUD + cross-user 404 + unauthenticated redirect
- `test/integration/cards_flow_test.rb`: CRUD + cross-user 404 + whitespace name rejection
- `test/integration/cards_reorder_test.rb`: within-lane reorder, cross-lane move, cross-user 404
- `e2e/board_canvas.spec.js`: full canvas flows including drag persistence

**Mocking**: None required. All tests use real ActiveRecord objects and the test database. No external services.

**Coverage target**: Maintain ≥80% SimpleCov. New controllers (`swimlanes_controller.rb`, `cards_controller.rb`) must each have corresponding integration tests covering both happy and error paths.

---

## Risk Assessment

- **SortableJS CDN availability in test environment**: Playwright starts a real Rails server; CDN scripts load in the browser. If CDN is blocked in CI, vendoring SortableJS to `vendor/javascript/` is the fallback. Check CDN access early; if blocked, run `curl -O` to vendor it.
- **Cross-lane drag `data-sortable-url-value` pointing to original vs destination lane**: The Stimulus controller must read `event.to.dataset.sortableUrlValue` (destination container's URL), not `event.from`. Verify this in the drag E2E test before declaring done.
- **`reorder` collection route path helper name**: Rails generates `reorder_board_swimlane_cards_path` for a collection route named `:reorder`. Verify with `bin/rails routes | grep reorder` before using in tests.
- **Turbo Frame rename flow**: The "Rename" link in the swimlane header targets a Turbo Frame and must GET the edit form. The `edit` action must render just the partial (not a full layout response). Ensure `render partial:` is used, not a full template render.
- **`before_action` chain for `reorder`**: `set_card` should NOT run for `reorder` (it's a collection action with no `:id` in URL). Ensure `before_action :set_card, only: [:edit, :update, :destroy]` excludes `reorder`.
- **SimpleCov coverage floor**: Adding two new controllers without sufficient test coverage risks dropping below 80%. The integration tests specified above cover all actions; confirm after running `bin/rails test`.
