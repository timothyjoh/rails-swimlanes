require "test_helper"

class SwimlanesFlowTest < ActionDispatch::IntegrationTest
  include ActionCable::TestHelper

  setup do
    @user = User.create!(email_address: "swim@test.com", password: "password123", password_confirmation: "password123")
    @board = create_owned_board(@user, name: "My Board")
    sign_in_as @user
  end

  test "creates a swimlane" do
    assert_difference "Swimlane.count" do
      post board_swimlanes_path(@board), params: { swimlane: { name: "To Do" } }
    end
    assert_redirected_to board_path(@board)
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
    assert_redirected_to board_path(@board)
    assert_equal "New Name", swimlane.reload.name
  end

  test "destroys a swimlane and its cards" do
    swimlane = @board.swimlanes.create!(name: "Lane")
    swimlane.cards.create!(name: "Card A")
    assert_difference ["Swimlane.count", "Card.count"], -1 do
      delete board_swimlane_path(@board, swimlane)
    end
    assert_redirected_to board_path(@board)
  end

  test "cannot create swimlane on another user's board" do
    other_user = User.create!(email_address: "other@test.com", password: "pass1234", password_confirmation: "pass1234")
    other_board = create_owned_board(other_user, name: "Other")
    post board_swimlanes_path(other_board), params: { swimlane: { name: "Lane" } }
    assert_response :not_found
  end

  test "cannot update swimlane on another user's board" do
    other_user = User.create!(email_address: "other2@test.com", password: "pass1234", password_confirmation: "pass1234")
    other_board = create_owned_board(other_user, name: "Other")
    other_swimlane = other_board.swimlanes.create!(name: "Their Lane")
    patch board_swimlane_path(other_board, other_swimlane), params: { swimlane: { name: "Hijacked" } }
    assert_response :not_found
  end

  test "cannot destroy swimlane on another user's board" do
    other_user = User.create!(email_address: "other3@test.com", password: "pass1234", password_confirmation: "pass1234")
    other_board = create_owned_board(other_user, name: "Other")
    other_swimlane = other_board.swimlanes.create!(name: "Their Lane")
    delete board_swimlane_path(other_board, other_swimlane)
    assert_response :not_found
  end

  test "creates a swimlane via turbo stream" do
    assert_difference "Swimlane.count" do
      post board_swimlanes_path(@board),
           params: { swimlane: { name: "To Do" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
  end

  test "gets swimlane header" do
    swimlane = @board.swimlanes.create!(name: "Lane")
    get header_board_swimlane_path(@board, swimlane)
    assert_response :success
  end

  test "unauthenticated request redirects to login" do
    sign_out
    post board_swimlanes_path(@board), params: { swimlane: { name: "Lane" } }
    assert_redirected_to new_session_path
  end

  # --- Phase 5: broadcasts ---

  test "swimlane create broadcasts to board stream" do
    assert_broadcasts @board.to_gid_param, 1 do
      post board_swimlanes_path(@board),
           params: { swimlane: { name: "Broadcast Lane" } },
           headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
  end

  test "swimlane update broadcasts to board stream" do
    swimlane = @board.swimlanes.create!(name: "Old Name")
    assert_broadcasts @board.to_gid_param, 1 do
      patch board_swimlane_path(@board, swimlane),
            params: { swimlane: { name: "New Name" } },
            headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
  end

  test "swimlane destroy broadcasts to board stream" do
    swimlane = @board.swimlanes.create!(name: "Doomed Lane")
    assert_broadcasts @board.to_gid_param, 1 do
      delete board_swimlane_path(@board, swimlane),
             headers: { "Accept" => "text/vnd.turbo-stream.html" }
    end
    assert_response :success
  end
end
