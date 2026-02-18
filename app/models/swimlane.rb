class Swimlane < ApplicationRecord
  belongs_to :board
  has_many :cards, -> { order(:position) }, dependent: :destroy

  validates :name, presence: true
  before_validation { name&.strip! }

  before_create :set_position

  private

  def set_position
    self.position = (board.swimlanes.maximum(:position) || -1) + 1
  end
end
