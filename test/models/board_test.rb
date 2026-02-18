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
    board = Board.new(name: "   ", user: users(:one))
    assert_not board.valid?
    assert_includes board.errors[:name], "can't be blank"
  end
end
