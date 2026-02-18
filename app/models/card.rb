class Card < ApplicationRecord
  belongs_to :swimlane
  has_many :card_labels, dependent: :destroy
  has_many :labels, through: :card_labels

  validates :name, presence: true
  before_validation { name&.strip! }

  scope :overdue, -> { where("due_date < ?", Date.current).where.not(due_date: nil) }
  scope :upcoming, -> { where("due_date >= ?", Date.current).where.not(due_date: nil) }

  before_create :set_position

  def overdue?
    due_date.present? && due_date < Date.current
  end

  private

  def set_position
    self.position = (swimlane.cards.maximum(:position) || -1) + 1
  end
end
