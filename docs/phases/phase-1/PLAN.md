# Implementation Plan: Phase 1

## Overview
Scaffold a new Rails 8 application ("Swimlanes") with built-in authentication and full Board CRUD (create, list, edit, delete), resulting in a working app where authenticated users can manage their own boards.

## Current State (from Research)
- No Rails application exists — project directory contains only pipeline tooling and docs
- Ruby 3.4.3 is installed at `/usr/local/opt/ruby/bin/ruby` but is NOT on `PATH` by default (system Ruby 2.6.10 takes precedence)
- Rails is **not installed** in the Ruby 3.4 gem environment — must be installed before `rails new`
- Node.js 22.18.0 and npm 10.9.3 are available for Tailwind build and Playwright
- No existing patterns to follow — conventions will be established by this phase

## Desired End State
After this phase:
- `bin/setup && bin/rails server` starts the app cleanly on Rails 8 with no errors
- Users can sign up, log in, create/rename/delete boards, and log out
- `bin/rails test` passes all unit + integration tests with ≥80% SimpleCov coverage
- `npx playwright test` passes all E2E tests for auth and board flows
- `AGENTS.md`, `README.md` exist at project root; `CLAUDE.md` is updated (not replaced)

**Verification**: `ls app/ Gemfile bin/rails test/ e2e/` all exist; `bin/rails test` and `npx playwright test` both exit 0.

## What We're NOT Doing
- Swimlane (column) model or UI — Phase 2
- Card model or UI — Phase 2
- Drag-and-drop — Phase 2
- Board sharing between users — Phase 4
- ActionCable / real-time updates — Phase 5
- Password reset / email flows — explicitly excluded from Phase 1
- Image uploads of any kind
- Docker or containerization
- Any CSS framework other than Tailwind
- Webpack, esbuild, or vite (Tailwind via `tailwindcss-rails` standalone binary only)

## Implementation Approach
Build in sequential vertical slices: environment → app scaffold → auth → boards → tests → docs. Each slice is independently verifiable. We use `PATH="/usr/local/opt/ruby/bin:$PATH"` as a prefix on every Ruby/Rails command to ensure Ruby 3.4.3 is used. Playwright tests are installed via a root-level `package.json` so `npx playwright test` works without global installs.

---

## Task 1: Install Rails into Ruby 3.4 Environment

### Overview
Rails is not yet installed. Install Rails 8 into the Homebrew Ruby 3.4.3 gem environment before any `rails new` command can run.

### Changes Required
**Command** (run in project root):
```bash
PATH="/usr/local/opt/ruby/bin:$PATH" gem install rails --version '~> 8.0'
```

No file changes — this installs gems into `/usr/local/opt/ruby/lib/ruby/gems/3.4.0/`.

### Success Criteria
- [ ] `PATH="/usr/local/opt/ruby/bin:$PATH" rails --version` outputs `Rails 8.x.x`
- [ ] No errors during gem install

---

## Task 2: Generate Rails 8 Application

### Overview
Use `rails new` to scaffold the application with SQLite, Tailwind CSS, Hotwire (default), and importmap. The app is generated **inside** the project root directory.

### Changes Required
**Command** (run from parent directory, targeting project root):
```bash
PATH="/usr/local/opt/ruby/bin:$PATH" rails new /Users/timothyjohnson/wrk/rails-swimlanes \
  --database=sqlite3 \
  --css=tailwind \
  --skip-docker \
  --skip-action-mailer \
  --skip-action-mailbox \
  --skip-action-text \
  --skip-active-storage \
  --force
```

> **Note on `--force`**: The directory exists with CLAUDE.md, BRIEF.md, etc. `--force` overwrites only generated files. Verify CLAUDE.md and BRIEF.md survive (they are not Rails-generated files and will not be touched).

**Flags rationale**:
- `--database=sqlite3` — local SQLite, no external service
- `--css=tailwind` — installs `tailwindcss-rails` gem with standalone binary
- `--skip-docker` — no Docker per spec requirement
- `--skip-action-mailer/mailbox/text/active-storage` — out of scope for Phase 1; keeps the app lean

**Expected generated structure**:
```
app/
  assets/, channels/, controllers/, helpers/, javascript/, jobs/, mailers/, models/, views/
bin/
  rails, rake, setup, ...
config/
  routes.rb, database.yml, application.rb, ...
db/
  schema.rb (after migrate), seeds.rb
Gemfile
test/
  application_system_test_case.rb, test_helper.rb, ...
```

### Success Criteria
- [ ] `app/`, `Gemfile`, `bin/rails`, `config/routes.rb` all exist
- [ ] `PATH="/usr/local/opt/ruby/bin:$PATH" bin/rails --version` outputs Rails 8.x.x
- [ ] `CLAUDE.md` and `BRIEF.md` are intact (not overwritten)

---

## Task 3: Install Dependencies and Prepare Database

### Overview
Run `bin/setup` (Rails-generated) to install gems, prepare the database, and verify the environment is ready.

### Changes Required
**Command**:
```bash
PATH="/usr/local/opt/ruby/bin:$PATH" bin/setup
```

**Verify `bin/setup`** does these steps (default Rails 8 script does):
1. `bundle install`
2. `bin/rails db:prepare` (creates + migrates)
3. Clears logs and tmp

If the generated `bin/setup` does NOT call `bundle install` explicitly with the right Ruby, we may need to prepend PATH inside the script. Check the generated file and add `ENV['PATH'] = "/usr/local/opt/ruby/bin:#{ENV['PATH']}"` at the top if needed. But first try it as-is since Bundler 2.6.8 ships with Ruby 3.4.

### Success Criteria
- [ ] `bundle install` completes without errors
- [ ] `db/development.sqlite3` is created
- [ ] `PATH="/usr/local/opt/ruby/bin:$PATH" bin/rails runner 'puts Rails.version'` outputs `8.x.x`

---

## Task 4: Generate and Configure Authentication

### Overview
Use `rails generate authentication` to produce the full built-in auth system: User model, Session model, SessionsController, PasswordsController, and related views. Add sign-up (registration) which the generator does NOT create — it must be added manually.

### Changes Required

**Command**:
```bash
PATH="/usr/local/opt/ruby/bin:$PATH" bin/rails generate authentication
```

**Generated files**:
- `app/models/user.rb` — has `has_secure_password`, `has_many :sessions`
- `app/models/session.rb`
- `app/controllers/sessions_controller.rb`
- `app/controllers/passwords_controller.rb`
- `app/views/sessions/new.html.erb`
- `app/views/passwords/`
- `db/migrate/TIMESTAMP_create_users.rb`
- `db/migrate/TIMESTAMP_create_sessions.rb`

**Run migration**:
```bash
PATH="/usr/local/opt/ruby/bin:$PATH" bin/rails db:migrate
```

**Add sign-up (registration) — manual additions**:

**File**: `app/controllers/registrations_controller.rb` (create new)
```ruby
class RegistrationsController < ApplicationController
  allow_unauthenticated_access

  def new
    @user = User.new
  end

  def create
    @user = User.new(registration_params)
    if @user.save
      start_new_session_for @user
      redirect_to boards_path, notice: "Account created!"
    else
      render :new, status: :unprocessable_entity
    end
  end

  private

  def registration_params
    params.require(:user).permit(:email_address, :password, :password_confirmation)
  end
end
```

**File**: `app/views/registrations/new.html.erb` (create new)
```erb
<div class="max-w-md mx-auto mt-8">
  <h1 class="text-2xl font-bold mb-4">Sign Up</h1>
  <%= form_with model: @user, url: registration_path do |f| %>
    <% if @user.errors.any? %>
      <div class="bg-red-50 text-red-700 p-3 rounded mb-4">
        <%= @user.errors.full_messages.to_sentence %>
      </div>
    <% end %>
    <div class="mb-4">
      <%= f.label :email_address, class: "block text-sm font-medium mb-1" %>
      <%= f.email_field :email_address, class: "w-full border rounded px-3 py-2" %>
    </div>
    <div class="mb-4">
      <%= f.label :password, class: "block text-sm font-medium mb-1" %>
      <%= f.password_field :password, class: "w-full border rounded px-3 py-2" %>
    </div>
    <div class="mb-4">
      <%= f.label :password_confirmation, class: "block text-sm font-medium mb-1" %>
      <%= f.password_field :password_confirmation, class: "w-full border rounded px-3 py-2" %>
    </div>
    <%= f.submit "Create Account", class: "w-full bg-blue-600 text-white py-2 rounded hover:bg-blue-700" %>
  <% end %>
  <p class="mt-4 text-sm">Already have an account? <%= link_to "Log in", new_session_path %></p>
</div>
```

**File**: `config/routes.rb` — add registration routes and set root:
```ruby
Rails.application.routes.draw do
  resource :session
  resources :passwords, param: :token
  resource :registration, only: [:new, :create]

  resources :boards
  root "boards#index"

  # health check (keep if generated)
  get "up" => "rails/health#show", as: :rails_health_check
end
```

**File**: `app/views/sessions/new.html.erb` — update to add sign-up link:
Add `<p>Don't have an account? <%= link_to "Sign up", new_registration_path %></p>` below the form.

**File**: `app/controllers/application_controller.rb` — add authentication requirement:
```ruby
class ApplicationController < ActionController::Base
  include Authentication  # generated by rails generate authentication
  before_action :require_authentication
  # ...
end
```
> Note: `rails generate authentication` may already add this. Verify and adjust — do not duplicate.

### Success Criteria
- [ ] `db/schema.rb` contains `users` and `sessions` tables
- [ ] `bin/rails routes` shows `session`, `registration`, `boards` routes
- [ ] Visiting `/session/new` in the browser shows a login form
- [ ] Visiting `/registration/new` shows a sign-up form
- [ ] Visiting `/boards` when unauthenticated redirects to `/session/new`

---

## Task 5: Board Model and CRUD

### Overview
Generate the Board model with user ownership and implement full CRUD with authorization.

### Changes Required

**Command** — generate Board model:
```bash
PATH="/usr/local/opt/ruby/bin:$PATH" bin/rails generate model Board name:string user:references
PATH="/usr/local/opt/ruby/bin:$PATH" bin/rails db:migrate
```

**Command** — generate BoardsController (scaffold or manual):
Use scaffold for speed, then trim the generated controller:
```bash
PATH="/usr/local/opt/ruby/bin:$PATH" bin/rails generate scaffold_controller Board name:string
```
Or write manually (preferred — avoids scaffold bloat):

**File**: `app/controllers/boards_controller.rb`
```ruby
class BoardsController < ApplicationController
  before_action :set_board, only: [:show, :edit, :update, :destroy]

  def index
    @boards = Current.user.boards.order(created_at: :desc)
  end

  def new
    @board = Current.user.boards.new
  end

  def create
    @board = Current.user.boards.new(board_params)
    if @board.save
      redirect_to boards_path, notice: "Board created."
    else
      render :new, status: :unprocessable_entity
    end
  end

  def edit; end

  def update
    if @board.update(board_params)
      redirect_to boards_path, notice: "Board updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @board.destroy
    redirect_to boards_path, notice: "Board deleted."
  end

  private

  def set_board
    @board = Current.user.boards.find(params[:id])
    # find scoped to current user — raises ActiveRecord::RecordNotFound if not owned
  end

  def board_params
    params.require(:board).permit(:name)
  end
end
```

**File**: `app/models/board.rb`
```ruby
class Board < ApplicationRecord
  belongs_to :user
  validates :name, presence: true
end
```

**File**: `app/models/user.rb` — add association (the generator may not include this):
```ruby
has_many :boards, dependent: :destroy
```

**Views** — create `app/views/boards/`:

`app/views/boards/index.html.erb`:
```erb
<div class="max-w-4xl mx-auto mt-8 px-4">
  <div class="flex justify-between items-center mb-6">
    <h1 class="text-2xl font-bold">My Boards</h1>
    <%= link_to "New Board", new_board_path, class: "bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700" %>
  </div>

  <% if @boards.empty? %>
    <p class="text-gray-500">No boards yet. Create one!</p>
  <% else %>
    <div class="grid grid-cols-1 sm:grid-cols-2 lg:grid-cols-3 gap-4">
      <% @boards.each do |board| %>
        <div class="bg-white border rounded-lg p-4 shadow-sm">
          <h2 class="text-lg font-semibold mb-2"><%= board.name %></h2>
          <div class="flex gap-2 mt-3">
            <%= link_to "Edit", edit_board_path(board), class: "text-sm text-blue-600 hover:underline" %>
            <%= button_to "Delete", board_path(board), method: :delete,
                data: { turbo_confirm: "Delete this board?" },
                class: "text-sm text-red-600 hover:underline bg-transparent border-none cursor-pointer p-0" %>
          </div>
        </div>
      <% end %>
    </div>
  <% end %>

  <div class="mt-8">
    <%= button_to "Log Out", session_path, method: :delete, class: "text-sm text-gray-600 hover:underline bg-transparent border-none cursor-pointer" %>
  </div>
</div>
```

`app/views/boards/new.html.erb`:
```erb
<div class="max-w-md mx-auto mt-8 px-4">
  <h1 class="text-2xl font-bold mb-4">New Board</h1>
  <%= render "form", board: @board %>
  <%= link_to "Back", boards_path, class: "text-sm text-gray-600 hover:underline mt-4 inline-block" %>
</div>
```

`app/views/boards/edit.html.erb`:
```erb
<div class="max-w-md mx-auto mt-8 px-4">
  <h1 class="text-2xl font-bold mb-4">Edit Board</h1>
  <%= render "form", board: @board %>
  <%= link_to "Back", boards_path, class: "text-sm text-gray-600 hover:underline mt-4 inline-block" %>
</div>
```

`app/views/boards/_form.html.erb`:
```erb
<%= form_with model: board do |f| %>
  <% if board.errors.any? %>
    <div class="bg-red-50 text-red-700 p-3 rounded mb-4">
      <%= board.errors.full_messages.to_sentence %>
    </div>
  <% end %>
  <div class="mb-4">
    <%= f.label :name, class: "block text-sm font-medium mb-1" %>
    <%= f.text_field :name, class: "w-full border rounded px-3 py-2", autofocus: true %>
  </div>
  <%= f.submit class: "bg-blue-600 text-white px-4 py-2 rounded hover:bg-blue-700" %>
<% end %>
```

**Application layout** — `app/views/layouts/application.html.erb`: verify the default Tailwind layout is in place. It should already include `<%= stylesheet_link_tag :app %>` for the Tailwind output. No changes expected unless it's missing.

### Success Criteria
- [ ] `db/schema.rb` contains `boards` table with `name` and `user_id` columns
- [ ] `bin/rails routes | grep board` shows all 7 RESTful board routes
- [ ] A logged-in user can create, list, edit, and delete boards via the browser
- [ ] A board created by User A is NOT accessible to User B (returns 404)
- [ ] Creating a board with no name shows a validation error

---

## Task 6: Add Flash Messages and Navigation Polish

### Overview
Wire up Turbo-compatible flash messages in the application layout so success/error notices appear after redirects and form submissions.

### Changes Required

**File**: `app/views/layouts/application.html.erb` — add flash rendering after `<body>`:
```erb
<body>
  <% if notice.present? %>
    <div class="bg-green-100 text-green-800 px-4 py-3 text-sm" data-controller="flash">
      <%= notice %>
    </div>
  <% end %>
  <% if alert.present? %>
    <div class="bg-red-100 text-red-800 px-4 py-3 text-sm">
      <%= alert %>
    </div>
  <% end %>
  <%= yield %>
</body>
```

### Success Criteria
- [ ] "Board created." flash appears after creating a board
- [ ] "Board deleted." flash appears after deleting a board
- [ ] Login errors show as alert messages

---

## Task 7: Configure SimpleCov and Write Unit + Integration Tests

### Overview
Add SimpleCov to `Gemfile`, configure it in `test/test_helper.rb`, and write comprehensive tests for models and auth/board flows.

### Changes Required

**File**: `Gemfile` — add to `:test` group:
```ruby
group :test do
  gem "capybara"
  gem "selenium-webdriver"
  gem "simplecov", require: false
end
```

**File**: `test/test_helper.rb` — add SimpleCov at the very top (before Rails require):
```ruby
require "simplecov"
SimpleCov.start "rails" do
  add_filter "/test/"
  minimum_coverage 80
end

ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"
# ...rest of file
```

**File**: `test/models/user_test.rb`
```ruby
require "test_helper"

class UserTest < ActiveSupport::TestCase
  test "valid with email and password" do
    user = User.new(email_address: "test@example.com", password: "password123")
    assert user.valid?
  end

  test "invalid without email" do
    user = User.new(password: "password123")
    assert_not user.valid?
  end

  test "invalid with duplicate email" do
    User.create!(email_address: "dup@example.com", password: "password123")
    user = User.new(email_address: "dup@example.com", password: "password123")
    assert_not user.valid?
  end
end
```

**File**: `test/models/board_test.rb`
```ruby
require "test_helper"

class BoardTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "u@example.com", password: "password123")
  end

  test "valid with name and user" do
    board = Board.new(name: "My Board", user: @user)
    assert board.valid?
  end

  test "invalid without name" do
    board = Board.new(user: @user)
    assert_not board.valid?
    assert_includes board.errors[:name], "can't be blank"
  end

  test "invalid without user" do
    board = Board.new(name: "My Board")
    assert_not board.valid?
  end
end
```

**File**: `test/integration/authentication_flow_test.rb`
```ruby
require "test_helper"

class AuthenticationFlowTest < ActionDispatch::IntegrationTest
  test "sign up creates account and redirects to boards" do
    post registration_path, params: {
      user: { email_address: "new@example.com", password: "password123", password_confirmation: "password123" }
    }
    assert_redirected_to boards_path
  end

  test "sign in with valid credentials redirects to boards" do
    user = User.create!(email_address: "u@example.com", password: "password123")
    post session_path, params: { email_address: "u@example.com", password: "password123" }
    assert_redirected_to boards_path
  end

  test "sign in with invalid credentials re-renders login" do
    post session_path, params: { email_address: "u@example.com", password: "wrong" }
    assert_response :unprocessable_entity
  end

  test "unauthenticated request to boards redirects to login" do
    get boards_path
    assert_redirected_to new_session_path
  end

  test "log out clears session and redirects to login" do
    user = User.create!(email_address: "u@example.com", password: "password123")
    post session_path, params: { email_address: "u@example.com", password: "password123" }
    delete session_path
    assert_redirected_to new_session_path
  end
end
```

**File**: `test/integration/boards_flow_test.rb`
```ruby
require "test_helper"

class BoardsFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "u@example.com", password: "password123")
    post session_path, params: { email_address: "u@example.com", password: "password123" }
  end

  test "create a board" do
    post boards_path, params: { board: { name: "Sprint 1" } }
    assert_redirected_to boards_path
    assert Board.exists?(name: "Sprint 1", user: @user)
  end

  test "create board with blank name shows error" do
    post boards_path, params: { board: { name: "" } }
    assert_response :unprocessable_entity
  end

  test "edit board name" do
    board = Board.create!(name: "Old Name", user: @user)
    patch board_path(board), params: { board: { name: "New Name" } }
    assert_redirected_to boards_path
    assert_equal "New Name", board.reload.name
  end

  test "delete board" do
    board = Board.create!(name: "To Delete", user: @user)
    delete board_path(board)
    assert_redirected_to boards_path
    assert_not Board.exists?(board.id)
  end

  test "cannot access another user's board" do
    other_user = User.create!(email_address: "other@example.com", password: "password123")
    other_board = Board.create!(name: "Private", user: other_user)
    get edit_board_path(other_board)
    assert_response :not_found
  end
end
```

**Run**:
```bash
PATH="/usr/local/opt/ruby/bin:$PATH" bin/rails test
```

### Success Criteria
- [ ] `bin/rails test` exits 0 with all tests passing
- [ ] SimpleCov generates `coverage/index.html`
- [ ] Coverage is ≥80%
- [ ] No test uses mocking where a real ActiveRecord object works

---

## Task 8: Playwright End-to-End Tests

### Overview
Set up Playwright in a root-level `package.json` with `@playwright/test` as a devDependency, configure it to target `http://localhost:3000`, and write E2E tests for all auth and board flows.

### Changes Required

**Command** — initialize package.json and install Playwright:
```bash
cd /Users/timothyjohnson/wrk/rails-swimlanes
npm init -y
npm install --save-dev @playwright/test
npx playwright install chromium
```

**File**: `playwright.config.js` (create at project root)
```javascript
import { defineConfig } from '@playwright/test';

export default defineConfig({
  testDir: './e2e',
  use: {
    baseURL: 'http://localhost:3000',
    headless: true,
  },
  webServer: {
    command: 'PATH="/usr/local/opt/ruby/bin:$PATH" bin/rails server -e test',
    url: 'http://localhost:3000',
    reuseExistingServer: false,
    timeout: 30000,
  },
});
```

> **Note**: The `webServer` option starts the Rails server automatically before tests run and shuts it down after. Tests use the `test` environment with a separate database so they don't pollute development data.

**File**: `e2e/auth.spec.js` (create)
```javascript
import { test, expect } from '@playwright/test';

const email = `test_${Date.now()}@example.com`;
const password = 'password123';

test.describe('Authentication', () => {
  test('sign up creates account and shows boards', async ({ page }) => {
    await page.goto('/registration/new');
    await page.fill('[name="user[email_address]"]', email);
    await page.fill('[name="user[password]"]', password);
    await page.fill('[name="user[password_confirmation]"]', password);
    await page.click('[type="submit"]');
    await expect(page).toHaveURL('/boards');
    await expect(page.locator('h1')).toContainText('My Boards');
  });

  test('log in with valid credentials', async ({ page }) => {
    // Use a seed or create via API; for E2E simplicity sign up first
    await page.goto('/registration/new');
    await page.fill('[name="user[email_address]"]', `login_${Date.now()}@example.com`);
    await page.fill('[name="user[password]"]', password);
    await page.fill('[name="user[password_confirmation]"]', password);
    await page.click('[type="submit"]');
    // Now log out and log back in
    await page.click('button:has-text("Log Out")');
    await expect(page).toHaveURL(/session\/new/);
  });

  test('log out redirects to login', async ({ page }) => {
    await page.goto('/registration/new');
    await page.fill('[name="user[email_address]"]', `logout_${Date.now()}@example.com`);
    await page.fill('[name="user[password]"]', password);
    await page.fill('[name="user[password_confirmation]"]', password);
    await page.click('[type="submit"]');
    await page.click('button:has-text("Log Out")');
    await expect(page).toHaveURL(/session\/new/);
  });

  test('unauthenticated user is redirected from boards', async ({ page }) => {
    await page.goto('/boards');
    await expect(page).toHaveURL(/session\/new/);
  });
});
```

**File**: `e2e/boards.spec.js` (create)
```javascript
import { test, expect } from '@playwright/test';

const password = 'password123';

async function signUp(page) {
  const email = `boards_${Date.now()}@example.com`;
  await page.goto('/registration/new');
  await page.fill('[name="user[email_address]"]', email);
  await page.fill('[name="user[password]"]', password);
  await page.fill('[name="user[password_confirmation]"]', password);
  await page.click('[type="submit"]');
  await expect(page).toHaveURL('/boards');
}

test.describe('Board Management', () => {
  test('create a board', async ({ page }) => {
    await signUp(page);
    await page.click('text=New Board');
    await page.fill('[name="board[name]"]', 'My First Board');
    await page.click('[type="submit"]');
    await expect(page).toHaveURL('/boards');
    await expect(page.locator('text=My First Board')).toBeVisible();
  });

  test('edit a board name', async ({ page }) => {
    await signUp(page);
    await page.click('text=New Board');
    await page.fill('[name="board[name]"]', 'Original Name');
    await page.click('[type="submit"]');
    await page.click('text=Edit');
    await page.fill('[name="board[name]"]', 'Updated Name');
    await page.click('[type="submit"]');
    await expect(page.locator('text=Updated Name')).toBeVisible();
    await expect(page.locator('text=Original Name')).not.toBeVisible();
  });

  test('delete a board', async ({ page }) => {
    await signUp(page);
    await page.click('text=New Board');
    await page.fill('[name="board[name]"]', 'To Be Deleted');
    await page.click('[type="submit"]');
    page.on('dialog', d => d.accept());
    await page.click('button:has-text("Delete")');
    await expect(page.locator('text=To Be Deleted')).not.toBeVisible();
  });
});
```

**Update `bin/setup`** to add `npm install`:
Check the generated `bin/setup` file. Add `system("npm install")` or equivalent after the existing steps so Playwright devDependencies are installed on fresh checkout.

### Success Criteria
- [ ] `package.json` and `playwright.config.js` exist at project root
- [ ] `e2e/` directory with `auth.spec.js` and `boards.spec.js` exists
- [ ] `npx playwright test` exits 0 with all tests passing
- [ ] Tests use the Rails test environment (separate DB from development)

---

## Task 9: Create Documentation Files

### Overview
Create `AGENTS.md` and `README.md`, and update `CLAUDE.md` (prepend content, do NOT replace).

### Changes Required

**File**: `AGENTS.md` (create at project root)
```markdown
# AGENTS.md

## Project: Swimlanes
A Trello-like board management app built with Rails 8, Hotwire, Tailwind CSS, and SQLite.

## Prerequisites
- Ruby 3.4+ (Homebrew: `/usr/local/opt/ruby/bin/ruby`)
- Node.js 18+ and npm
- No Docker required

## Install

```bash
export PATH="/usr/local/opt/ruby/bin:$PATH"
bin/setup        # installs gems, prepares database, runs npm install
```

## Run

```bash
export PATH="/usr/local/opt/ruby/bin:$PATH"
bin/rails server
```

Visit: http://localhost:3000

## Test

```bash
# Unit + integration tests with SimpleCov coverage
export PATH="/usr/local/opt/ruby/bin:$PATH"
bin/rails test

# Coverage report
open coverage/index.html

# End-to-end tests (starts its own Rails server)
npx playwright test
```

## Project Structure

```
app/
  controllers/     # ApplicationController, BoardsController, RegistrationsController, etc.
  models/          # User, Board, Session
  views/           # boards/, sessions/, registrations/, layouts/
config/
  routes.rb        # All routes
db/
  schema.rb        # Current DB schema
test/
  models/          # Unit tests
  integration/     # Integration tests
e2e/               # Playwright end-to-end tests
docs/phases/       # Phase specs, research, plans, reflections
```

## Phase Roadmap
- Phase 1 (current): Setup, auth, board CRUD
- Phase 2: Swimlanes (columns) and cards
- Phase 3: Card details
- Phase 4: Board sharing
- Phase 5: Real-time updates (ActionCable)
- Phase 6: Board backgrounds
```

**File**: `README.md` (create at project root)
```markdown
# Swimlanes

A Trello-like board management application built with Rails 8, Hotwire (Turbo + Stimulus), Tailwind CSS, and SQLite.

## Getting Started

### Prerequisites
- Ruby 3.4+ via Homebrew (`/usr/local/opt/ruby/bin/ruby`)
- Node.js 18+ and npm

### Install

```bash
export PATH="/usr/local/opt/ruby/bin:$PATH"
git clone <repo>
cd rails-swimlanes
bin/setup
```

### Run

```bash
export PATH="/usr/local/opt/ruby/bin:$PATH"
bin/rails server
```

Open http://localhost:3000, sign up, and start creating boards.

## Testing

```bash
# Unit and integration tests
export PATH="/usr/local/opt/ruby/bin:$PATH"
bin/rails test

# End-to-end tests
npx playwright test
```

## Tech Stack
- **Rails 8** with built-in authentication
- **SQLite** for local development
- **Tailwind CSS** via `tailwindcss-rails`
- **Hotwire** (Turbo + Stimulus) for dynamic interactions
- **Minitest** + **SimpleCov** for unit/integration testing
- **Playwright** for end-to-end testing
```

**File**: `CLAUDE.md` — PREPEND only, do NOT touch existing content:
Add at the very top of the file:
```markdown
## ⚠️ FIRST: Read AGENTS.md

If `AGENTS.md` exists, read it NOW before doing anything else. It has project conventions, install steps, test commands, and architecture decisions.

---

```

> Use a targeted Edit (not Write) to prepend this block. The existing cc-pipeline content must remain intact below.

### Success Criteria
- [ ] `AGENTS.md` exists at project root with install, run, and test commands
- [ ] `README.md` exists at project root
- [ ] `CLAUDE.md` starts with the AGENTS.md instruction block AND retains all original content below it
- [ ] `cat CLAUDE.md | head -5` shows the AGENTS.md instruction

---

## Testing Strategy

### Unit Tests
- `test/models/user_test.rb` — presence validations, uniqueness of email
- `test/models/board_test.rb` — name presence, user association required

### Integration Tests
- `test/integration/authentication_flow_test.rb` — sign up, sign in, sign in failure, unauthenticated redirect, log out
- `test/integration/boards_flow_test.rb` — create, create-with-blank-name, edit, delete, cross-user access denial

**Mocking**: No mocking — all tests use real ActiveRecord objects and integration test request flows. The only setup is `before(:each)` user creation.

### E2E Tests (Playwright)
- `e2e/auth.spec.js` — sign up → boards, log out → login redirect, unauthenticated redirect
- `e2e/boards.spec.js` — create board, edit board name, delete board (with confirm dialog)

### Coverage
SimpleCov configured with `minimum_coverage 80`. If coverage drops below 80%, `bin/rails test` exits non-zero.

---

## Risk Assessment

- **Ruby PATH**: Build step MUST prefix `PATH="/usr/local/opt/ruby/bin:$PATH"` on every Rails command. If forgotten, Ruby 2.6 silently takes over and `rails new` fails. **Mitigation**: Document in AGENTS.md; consider adding `export PATH=...` to `bin/setup` header.
- **`--force` on `rails new`**: The `--force` flag will overwrite any Rails-generated file that already exists. `CLAUDE.md` and `BRIEF.md` are safe (not Rails-generated). **Mitigation**: Check `git status` or `ls` after `rails new` to confirm non-generated files are intact.
- **`rails generate authentication` sign-up gap**: The built-in generator does NOT produce a RegistrationsController. This is the most common source of confusion. **Mitigation**: Task 4 explicitly calls it out and provides the full implementation.
- **Playwright `webServer` + test DB**: The Playwright `webServer` config must use `RAILS_ENV=test` so tests run against the test database (which gets wiped between test runs). **Mitigation**: Playwright config command includes `-e test`.
- **Turbo `data-turbo-confirm`**: The delete button uses `data: { turbo_confirm: "..." }` for a browser confirm dialog. Playwright handles dialogs via `page.on('dialog', d => d.accept())`. If Turbo intercepts before the native dialog fires, the test may need adjustment. **Mitigation**: Accept dialog handler is registered before clicking delete in the E2E test.
- **SimpleCov `minimum_coverage 80`**: If test coverage starts below 80% (e.g., views/helpers not counted), the build will fail. **Mitigation**: Use `SimpleCov.start "rails"` profile which filters standard Rails boilerplate; adjust minimum if needed after first run.
