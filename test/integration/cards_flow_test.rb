require "test_helper"

class CardsFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "cards@test.com", password: "password123", password_confirmation: "password123")
    @board = create_owned_board(@user, name: "Board")
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
    other_board = create_owned_board(other_user, name: "Other")
    other_lane = other_board.swimlanes.create!(name: "Lane")
    post board_swimlane_cards_path(other_board, other_lane), params: { card: { name: "Hack" } }
    assert_response :not_found
  end

  test "cannot update card on another user's board" do
    other_user = User.create!(email_address: "evil@test.com", password: "pass1234", password_confirmation: "pass1234")
    other_board = create_owned_board(other_user, name: "Evil")
    other_lane = other_board.swimlanes.create!(name: "Lane")
    other_card = other_lane.cards.create!(name: "Card")
    patch board_swimlane_card_path(other_board, other_lane, other_card), params: { card: { name: "Hijacked" } }
    assert_response :not_found
  end

  test "cannot destroy card on another user's board" do
    other_user = User.create!(email_address: "evil2@test.com", password: "pass1234", password_confirmation: "pass1234")
    other_board = create_owned_board(other_user, name: "Evil")
    other_lane = other_board.swimlanes.create!(name: "Lane")
    other_card = other_lane.cards.create!(name: "Card")
    delete board_swimlane_card_path(other_board, other_lane, other_card)
    assert_response :not_found
  end

  # --- Phase 3: card detail ---

  test "show card detail — authenticated user gets 200" do
    card = @swimlane.cards.create!(name: "Detail Card")
    get board_swimlane_card_path(@board, @swimlane, card)
    assert_response :success
  end

  test "show card detail — wrong user gets 404" do
    other_user = User.create!(email_address: "other_show@test.com", password: "pass1234", password_confirmation: "pass1234")
    other_board = create_owned_board(other_user, name: "Other Board")
    other_lane = other_board.swimlanes.create!(name: "Lane")
    other_card = other_lane.cards.create!(name: "Secret")
    get board_swimlane_card_path(other_board, other_lane, other_card)
    assert_response :not_found
  end

  test "update card description via turbo stream" do
    card = @swimlane.cards.create!(name: "Desc Card")
    patch board_swimlane_card_path(@board, @swimlane, card),
          params: { card: { description: "Updated description" } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_equal "Updated description", card.reload.description
  end

  test "update card due date" do
    card = @swimlane.cards.create!(name: "Due Card")
    future_date = 5.days.from_now.to_date
    patch board_swimlane_card_path(@board, @swimlane, card),
          params: { card: { due_date: future_date.to_s } }
    assert_redirected_to board_path(@board)
    assert_equal future_date, card.reload.due_date
  end

  test "update card with past due date shows overdue indicator" do
    card = @swimlane.cards.create!(name: "Overdue Card")
    past_date = 2.days.ago.to_date
    patch board_swimlane_card_path(@board, @swimlane, card),
          params: { card: { due_date: past_date.to_s } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert card.reload.overdue?
    assert_match "overdue", response.body
  end

  test "add label to card" do
    card = @swimlane.cards.create!(name: "Labeled Card")
    label = labels(:red)
    patch board_swimlane_card_path(@board, @swimlane, card),
          params: { card: { label_ids: [label.id] } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_includes card.reload.labels, label
  end

  test "remove all labels from card" do
    card = @swimlane.cards.create!(name: "Unlabeled Card")
    label = labels(:red)
    card.labels << label
    patch board_swimlane_card_path(@board, @swimlane, card),
          params: { card: { label_ids: [""] } },
          headers: { "Accept" => "text/vnd.turbo-stream.html" }
    assert_response :success
    assert_empty card.reload.labels
  end
end
