require "test_helper"

class LabelTest < ActiveSupport::TestCase
  test "valid with known color" do
    label = labels(:red)
    assert label.valid?
  end

  test "invalid with unknown color" do
    label = Label.new(color: "neon_pink")
    assert_not label.valid?
    assert_includes label.errors[:color], "is not included in the list"
  end

  test "color must be unique" do
    duplicate = Label.new(color: labels(:red).color)
    assert_not duplicate.valid?
    assert_includes duplicate.errors[:color], "has already been taken"
  end

  test "COLORS constant has 5 values" do
    assert_equal 5, Label::COLORS.length
  end
end
