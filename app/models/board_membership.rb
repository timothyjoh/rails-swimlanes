class BoardMembership < ApplicationRecord
  belongs_to :board
  belongs_to :user

  enum :role, { owner: 0, member: 1 }

  validates :board, presence: true
  validates :user, presence: true
  validates :role, presence: true
  validates :user_id, uniqueness: { scope: :board_id, message: "is already a member of this board" }
end
