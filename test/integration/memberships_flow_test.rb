require "test_helper"

class MembershipsFlowTest < ActionDispatch::IntegrationTest
  include ActionView::RecordIdentifier

  TURBO_HEADERS = { "Accept" => "text/vnd.turbo-stream.html" }.freeze

  setup do
    @owner = User.create!(email_address: "owner@example.com", password: "password123")
    @board = Board.create!(name: "Shared Board", user: @owner)
    @board.board_memberships.create!(user: @owner, role: :owner)
    sign_in_as @owner
  end

  # ── Owner adds/removes members ──────────────────────────────

  test "owner adds member by valid email" do
    member = User.create!(email_address: "member@example.com", password: "password123")
    post board_memberships_path(@board),
         params: { email_address: member.email_address },
         headers: TURBO_HEADERS
    assert_response :success
    assert @board.reload.members.include?(member)
    assert_match member.email_address, response.body
  end

  test "owner sees turbo stream error for unknown email" do
    post board_memberships_path(@board),
         params: { email_address: "nobody@example.com" },
         headers: TURBO_HEADERS
    assert_response :unprocessable_entity
    assert_match "No user found with that email address", response.body
  end

  test "owner sees error for already-member email" do
    member = User.create!(email_address: "dup@example.com", password: "password123")
    @board.board_memberships.create!(user: member, role: :member)
    post board_memberships_path(@board),
         params: { email_address: member.email_address },
         headers: TURBO_HEADERS
    assert_response :unprocessable_entity
    assert_match "already a member", response.body
  end

  test "owner removes a member" do
    member = User.create!(email_address: "remove@example.com", password: "password123")
    membership = @board.board_memberships.create!(user: member, role: :member)
    delete board_membership_path(@board, membership), headers: TURBO_HEADERS
    assert_response :success
    assert_not BoardMembership.exists?(membership.id)
    assert_match dom_id(membership), response.body
  end

  test "owner cannot remove themselves (owner row)" do
    owner_membership = @board.board_memberships.find_by!(user: @owner)
    delete board_membership_path(@board, owner_membership)
    assert_response :redirect
    assert BoardMembership.exists?(owner_membership.id)
  end

  # ── Collaborator (member role) permissions ──────────────────

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

  test "collaborator can update a card" do
    swimlane = @board.swimlanes.create!(name: "Todo")
    card = swimlane.cards.create!(name: "Old Name")
    member = User.create!(email_address: "collab_patch@example.com", password: "password123")
    @board.board_memberships.create!(user: member, role: :member)
    sign_out
    sign_in_as member
    patch board_swimlane_card_path(@board, swimlane, card),
          params: { card: { name: "Updated" } },
          headers: TURBO_HEADERS
    assert_response :success
    assert_equal "Updated", card.reload.name
  end

  test "collaborator can delete a card" do
    swimlane = @board.swimlanes.create!(name: "Done")
    card = swimlane.cards.create!(name: "Bye")
    member = User.create!(email_address: "collab_del@example.com", password: "password123")
    @board.board_memberships.create!(user: member, role: :member)
    sign_out
    sign_in_as member
    delete board_swimlane_card_path(@board, swimlane, card),
           headers: TURBO_HEADERS
    assert_response :success
    assert_not Card.exists?(card.id)
  end

  test "collaborator can create a swimlane" do
    member = User.create!(email_address: "collab_sw@example.com", password: "password123")
    @board.board_memberships.create!(user: member, role: :member)
    sign_out
    sign_in_as member
    post board_swimlanes_path(@board),
         params: { swimlane: { name: "In Progress" } },
         headers: TURBO_HEADERS
    assert_response :success
    assert Swimlane.exists?(name: "In Progress")
  end

  test "collaborator can delete a swimlane" do
    swimlane = @board.swimlanes.create!(name: "Scratch")
    member = User.create!(email_address: "collab_sw2@example.com", password: "password123")
    @board.board_memberships.create!(user: member, role: :member)
    sign_out
    sign_in_as member
    delete board_swimlane_path(@board, swimlane),
           headers: TURBO_HEADERS
    assert_response :success
    assert_not Swimlane.exists?(swimlane.id)
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

  test "collaborator cannot add members to board" do
    member = User.create!(email_address: "collab5@example.com", password: "password123")
    @board.board_memberships.create!(user: member, role: :member)
    sign_out
    sign_in_as member
    post board_memberships_path(@board),
         params: { email_address: "anyone@example.com" }
    assert_response :not_found
  end

  # ── Non-member access denied ────────────────────────────────

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

  test "non-member cannot add members to board" do
    stranger = User.create!(email_address: "s3@example.com", password: "password123")
    sign_out
    sign_in_as stranger
    post board_memberships_path(@board),
         params: { email_address: "anyone@example.com" }
    assert_response :not_found
  end

  # ── Shared board visibility ─────────────────────────────────

  test "shared board appears on collaborator boards index" do
    member = User.create!(email_address: "idx@example.com", password: "password123")
    @board.board_memberships.create!(user: member, role: :member)
    sign_out
    sign_in_as member
    get boards_path
    assert_response :success
    assert_match @board.name, response.body
  end
end
