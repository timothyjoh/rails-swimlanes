class Label < ApplicationRecord
  COLORS = %w[red yellow green blue purple].freeze
  validates :color, inclusion: { in: COLORS }, uniqueness: true
  has_many :card_labels, dependent: :destroy
  has_many :cards, through: :card_labels
end
