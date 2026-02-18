require "test_helper"

class BoardsFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "u@example.com", password: "password123")
    sign_in_as @user
  end

  test "boards index lists user boards" do
    Board.create!(name: "Sprint 1", user: @user)
    get boards_path
    assert_response :success
    assert_match "Sprint 1", response.body
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

  test "update board with blank name shows error" do
    board = Board.create!(name: "Valid Name", user: @user)
    patch board_path(board), params: { board: { name: "" } }
    assert_response :unprocessable_entity
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

  test "cannot update another user's board" do
    other_user = User.create!(email_address: "other@example.com", password: "password123")
    other_board = Board.create!(name: "Private", user: other_user)
    patch board_path(other_board), params: { board: { name: "Hacked" } }
    assert_response :not_found
  end

  test "cannot delete another user's board" do
    other_user = User.create!(email_address: "other@example.com", password: "password123")
    other_board = Board.create!(name: "Private", user: other_user)
    delete board_path(other_board)
    assert_response :not_found
    assert Board.exists?(other_board.id)
  end
end
