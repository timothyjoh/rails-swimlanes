require "test_helper"

class BoardMembershipTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "member@example.com", password: "password123")
    @board = Board.create!(name: "Test Board", user: @user)
  end

  test "valid with board, user, and role" do
    membership = BoardMembership.new(board: @board, user: @user, role: :owner)
    assert membership.valid?
  end

  test "invalid without board" do
    membership = BoardMembership.new(user: @user, role: :owner)
    assert_not membership.valid?
  end

  test "invalid without user" do
    membership = BoardMembership.new(board: @board, role: :owner)
    assert_not membership.valid?
  end

  test "defaults role to owner" do
    membership = BoardMembership.create!(board: @board, user: @user)
    assert_equal "owner", membership.role
  end

  test "enforces unique user per board" do
    BoardMembership.create!(board: @board, user: @user, role: :owner)
    duplicate = BoardMembership.new(board: @board, user: @user, role: :member)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:user_id], "is already a member of this board"
  end

  test "allows same user on different boards" do
    other_board = Board.create!(name: "Other Board", user: @user)
    BoardMembership.create!(board: @board, user: @user, role: :owner)
    membership = BoardMembership.new(board: other_board, user: @user, role: :owner)
    assert membership.valid?
  end

  test "owner? and member? enum predicates" do
    membership = BoardMembership.new(role: :owner)
    assert membership.owner?
    assert_not membership.member?

    membership.role = :member
    assert membership.member?
    assert_not membership.owner?
  end

  test "dependent destroy removes memberships when board is deleted" do
    BoardMembership.create!(board: @board, user: @user, role: :owner)
    assert_difference "BoardMembership.count", -1 do
      @board.destroy
    end
  end

  test "dependent destroy removes memberships when user is deleted" do
    BoardMembership.create!(board: @board, user: @user, role: :owner)
    assert_difference "BoardMembership.count", -1 do
      @user.destroy
    end
  end
end
