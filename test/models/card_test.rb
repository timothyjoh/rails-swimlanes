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

  # --- Phase 3: due_date behavior ---

  test "overdue? returns true when due_date is in the past" do
    card = @swimlane.cards.create!(name: "Late", due_date: 1.day.ago.to_date)
    assert card.overdue?
  end

  test "overdue? returns false when due_date is today" do
    card = @swimlane.cards.create!(name: "Today", due_date: Date.current)
    assert_not card.overdue?
  end

  test "overdue? returns false when due_date is nil" do
    card = @swimlane.cards.create!(name: "No date")
    assert_not card.overdue?
  end

  test "overdue scope returns only past-due cards" do
    @swimlane.cards.create!(name: "Past", due_date: 2.days.ago.to_date)
    @swimlane.cards.create!(name: "Future", due_date: 2.days.from_now.to_date)
    @swimlane.cards.create!(name: "None")

    overdue = Card.overdue
    assert_includes overdue.map(&:name), "Past"
    assert_not_includes overdue.map(&:name), "Future"
    assert_not_includes overdue.map(&:name), "None"
  end

  test "upcoming scope returns future-due cards" do
    @swimlane.cards.create!(name: "Past", due_date: 2.days.ago.to_date)
    @swimlane.cards.create!(name: "Future", due_date: 2.days.from_now.to_date)
    @swimlane.cards.create!(name: "None")

    upcoming = Card.upcoming
    assert_includes upcoming.map(&:name), "Future"
    assert_not_includes upcoming.map(&:name), "Past"
    assert_not_includes upcoming.map(&:name), "None"
  end
end
