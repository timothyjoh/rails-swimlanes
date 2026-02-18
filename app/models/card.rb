class Card < ApplicationRecord
  belongs_to :swimlane

  validates :name, presence: true
  before_validation { name&.strip! }

  before_create :set_position

  private

  def set_position
    self.position = (swimlane.cards.maximum(:position) || -1) + 1
  end
end
