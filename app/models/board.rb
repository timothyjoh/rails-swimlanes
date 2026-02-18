class Board < ApplicationRecord
  belongs_to :user
  has_many :swimlanes, dependent: :destroy
  validates :name, presence: true
  before_validation { name&.strip! }
end
