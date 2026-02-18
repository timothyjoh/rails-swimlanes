class Board < ApplicationRecord
  belongs_to :user
  has_many :swimlanes, dependent: :destroy
  has_many :board_memberships, dependent: :destroy
  has_many :members, through: :board_memberships, source: :user

  validates :name, presence: true
  before_validation { name&.strip! }

  def self.accessible_by(user)
    joins(:board_memberships).where(board_memberships: { user_id: user.id })
  end
end
