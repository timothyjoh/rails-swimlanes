require "test_helper"

class BoardsFlowTest < ActionDispatch::IntegrationTest
  setup do
    @user = User.create!(email_address: "u@example.com", password: "password123")
    sign_in_as @user
  end

  test "boards index lists user boards" do
    create_owned_board(@user, name: "Sprint 1")
    other_user = User.create!(email_address: "other@example.com", password: "password123")
    create_owned_board(other_user, name: "Other User Board")
    get boards_path
    assert_response :success
    assert_match "Sprint 1", response.body
    assert_no_match "Other User Board", response.body
  end

  test "create a board" do
    post boards_path, params: { board: { name: "Sprint 1" } }
    assert_redirected_to boards_path
    assert Board.exists?(name: "Sprint 1", user: @user)
    board = Board.find_by(name: "Sprint 1")
    assert BoardMembership.exists?(board: board, user: @user, role: :owner)
  end

  test "create board with blank name shows error" do
    post boards_path, params: { board: { name: "" } }
    assert_response :unprocessable_entity
  end

  test "edit board name" do
    board = create_owned_board(@user, name: "Old Name")
    patch board_path(board), params: { board: { name: "New Name" } }
    assert_redirected_to boards_path
    assert_equal "New Name", board.reload.name
  end

  test "update board with blank name shows error" do
    board = create_owned_board(@user, name: "Valid Name")
    patch board_path(board), params: { board: { name: "" } }
    assert_response :unprocessable_entity
  end

  test "delete board" do
    board = create_owned_board(@user, name: "To Delete")
    delete board_path(board)
    assert_redirected_to boards_path
    assert_not Board.exists?(board.id)
  end

  test "shows board with swimlanes" do
    board = create_owned_board(@user, name: "My Board")
    swimlane = board.swimlanes.create!(name: "To Do")
    get board_path(board)
    assert_response :success
    assert_match swimlane.name, response.body
  end

  test "cannot view another user's board" do
    other_user = User.create!(email_address: "other2@example.com", password: "password123")
    other_board = create_owned_board(other_user, name: "Private Show")
    get board_path(other_board)
    assert_response :not_found
  end

  test "cannot access another user's board" do
    other_user = User.create!(email_address: "other@example.com", password: "password123")
    other_board = create_owned_board(other_user, name: "Private")
    get edit_board_path(other_board)
    assert_response :not_found
  end

  test "cannot update another user's board" do
    other_user = User.create!(email_address: "other@example.com", password: "password123")
    other_board = create_owned_board(other_user, name: "Private")
    patch board_path(other_board), params: { board: { name: "Hacked" } }
    assert_response :not_found
  end

  test "cannot delete another user's board" do
    other_user = User.create!(email_address: "other@example.com", password: "password123")
    other_board = create_owned_board(other_user, name: "Private")
    delete board_path(other_board)
    assert_response :not_found
    assert Board.exists?(other_board.id)
  end
end
