require "test_helper"

class CardsReorderTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "reorder@test.com", password: "password123", password_confirmation: "password123")
    @board = create_owned_board(@user, name: "Board")
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
    assert_equal 0, @card1.reload.position
  end

  test "cannot reorder card from another user's board" do
    other_user = User.create!(email_address: "evil@test.com", password: "pass1234", password_confirmation: "pass1234")
    other_board = create_owned_board(other_user, name: "Evil")
    other_lane = other_board.swimlanes.create!(name: "Lane")
    other_card = other_lane.cards.create!(name: "Card")
    patch reorder_board_swimlane_cards_path(@board, @lane1),
      params: { card_id: other_card.id, position: 0 },
      as: :json
    assert_response :not_found
  end

  test "clamps out-of-bounds position to last" do
    patch reorder_board_swimlane_cards_path(@board, @lane1),
      params: { card_id: @card1.id, position: 999 },
      as: :json
    assert_response :ok
    # card should be at position 1 (last in a 2-card lane)
    assert_equal 1, @card1.reload.position
  end

  test "unauthenticated reorder redirects to login" do
    sign_out
    patch reorder_board_swimlane_cards_path(@board, @lane1),
      params: { card_id: @card1.id, position: 0 },
      as: :json
    assert_redirected_to new_session_path
  end
end
