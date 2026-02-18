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

  test "downcases and strips email_address" do
    user = User.new(email_address: " DOWNCASED@EXAMPLE.COM ")
    assert_equal "downcased@example.com", user.email_address
  end

  test "has many boards" do
    user = User.create!(email_address: "boards@example.com", password: "password123")
    board = Board.create!(name: "My Board", user: user)
    assert_includes user.boards, board
  end
end
