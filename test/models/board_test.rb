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

  test "belongs to user" do
    board = Board.create!(name: "Sprint 1", user: @user)
    assert_equal @user, board.user
  end

  test "is invalid with whitespace-only name" do
    board = Board.new(name: "   ", user: @user)
    assert_not board.valid?
    assert_includes board.errors[:name], "can't be blank"
  end

  test "accessible_by returns boards where user has membership" do
    board = Board.create!(name: "Shared Board", user: @user)
    other_user = User.create!(email_address: "other@example.com", password: "password123")
    other_board = Board.create!(name: "Other Board", user: other_user)

    BoardMembership.create!(board: board, user: @user, role: :owner)
    BoardMembership.create!(board: other_board, user: other_user, role: :owner)
    BoardMembership.create!(board: other_board, user: @user, role: :member)

    accessible = Board.accessible_by(@user)
    assert_includes accessible, board
    assert_includes accessible, other_board
  end

  test "accessible_by excludes boards without membership" do
    board = Board.create!(name: "My Board", user: @user)
    other_user = User.create!(email_address: "other2@example.com", password: "password123")
    other_board = Board.create!(name: "Private Board", user: other_user)

    BoardMembership.create!(board: board, user: @user, role: :owner)

    accessible = Board.accessible_by(@user)
    assert_includes accessible, board
    assert_not_includes accessible, other_board
  end
end
