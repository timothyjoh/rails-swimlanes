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
    assert_redirected_to board_path(@board)
  end

  test "creates a card via turbo stream" do
    assert_difference "Card.count" do
      post board_swimlane_cards_path(@board, @swimlane),
           params: { card: { name: "My Task" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
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
    assert_redirected_to board_path(@board)
    assert_equal "New", card.reload.name
  end

  test "destroys a card" do
    card = @swimlane.cards.create!(name: "Task")
    assert_difference "Card.count", -1 do
      delete board_swimlane_card_path(@board, @swimlane, card),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
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

  test "cannot update card on another user's board" do
    other_user = User.create!(email_address: "evil@test.com", password: "pass1234", password_confirmation: "pass1234")
    other_board = other_user.boards.create!(name: "Evil")
    other_lane = other_board.swimlanes.create!(name: "Lane")
    other_card = other_lane.cards.create!(name: "Card")
    patch board_swimlane_card_path(other_board, other_lane, other_card), params: { card: { name: "Hijacked" } }
    assert_response :not_found
  end

  test "cannot destroy card on another user's board" do
    other_user = User.create!(email_address: "evil2@test.com", password: "pass1234", password_confirmation: "pass1234")
    other_board = other_user.boards.create!(name: "Evil")
    other_lane = other_board.swimlanes.create!(name: "Lane")
    other_card = other_lane.cards.create!(name: "Card")
    delete board_swimlane_card_path(other_board, other_lane, other_card)
    assert_response :not_found
  end
end
