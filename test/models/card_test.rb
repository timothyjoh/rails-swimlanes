require "test_helper"

class CardTest < ActiveSupport::TestCase
  setup do
    @user = User.create!(email_address: "card@test.com", password: "password123", password_confirmation: "password123")
    @board = @user.boards.create!(name: "Board")
    @swimlane = @board.swimlanes.create!(name: "Lane")
  end

  test "is valid with name and swimlane" do
    card = Card.new(name: "Task", swimlane: @swimlane)
    assert card.valid?
  end

  test "is invalid without name" do
    card = Card.new(name: nil, swimlane: @swimlane)
    assert_not card.valid?
    assert_includes card.errors[:name], "can't be blank"
  end

  test "is invalid with whitespace-only name" do
    card = Card.new(name: "   ", swimlane: @swimlane)
    assert_not card.valid?
    assert_includes card.errors[:name], "can't be blank"
  end

  test "is invalid without swimlane" do
    card = Card.new(name: "Task")
    assert_not card.valid?
  end

  test "auto-assigns position on create" do
    first = @swimlane.cards.create!(name: "First")
    second = @swimlane.cards.create!(name: "Second")
    assert_equal 0, first.position
    assert_equal 1, second.position
  end

  test "position sequence is scoped per swimlane" do
    other_lane = @board.swimlanes.create!(name: "Other Lane")
    other_lane.cards.create!(name: "Other First")
    card = @swimlane.cards.create!(name: "First on this lane")
    assert_equal 0, card.position
  end

  test "belongs to swimlane" do
    card = @swimlane.cards.create!(name: "Task")
    assert_equal @swimlane, card.swimlane
  end
end
