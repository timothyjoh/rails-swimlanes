require "test_helper"

class SwimlaneTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "lane@test.com", password: "password123", password_confirmation: "password123")
    @board = @user.boards.create!(name: "Test Board")
  end

  test "is valid with name and board" do
    swimlane = Swimlane.new(name: "To Do", board: @board)
    assert swimlane.valid?
  end

  test "is invalid without name" do
    swimlane = Swimlane.new(name: nil, board: @board)
    assert_not swimlane.valid?
    assert_includes swimlane.errors[:name], "can't be blank"
  end

  test "is invalid with whitespace-only name" do
    swimlane = Swimlane.new(name: "   ", board: @board)
    assert_not swimlane.valid?
    assert_includes swimlane.errors[:name], "can't be blank"
  end

  test "is invalid without board" do
    swimlane = Swimlane.new(name: "To Do")
    assert_not swimlane.valid?
  end

  test "auto-assigns position on create" do
    first = @board.swimlanes.create!(name: "First")
    second = @board.swimlanes.create!(name: "Second")
    assert_equal 0, first.position
    assert_equal 1, second.position
  end

  test "belongs to board" do
    swimlane = @board.swimlanes.create!(name: "Lane")
    assert_equal @board, swimlane.board
  end

  test "position sequence is scoped per board" do
    other_board = @user.boards.create!(name: "Other Board")
    other_board.swimlanes.create!(name: "Other First")
    lane = @board.swimlanes.create!(name: "First on this board")
    assert_equal 0, lane.position
  end

  test "destroying swimlane destroys its cards" do
    swimlane = @board.swimlanes.create!(name: "Lane")
    swimlane.cards.create!(name: "Card 1")
    swimlane.cards.create!(name: "Card 2")
    assert_difference "Card.count", -2 do
      swimlane.destroy
    end
  end
end
