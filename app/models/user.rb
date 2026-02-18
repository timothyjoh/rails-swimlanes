class User < ApplicationRecord
  has_secure_password
  has_many :sessions, dependent: :destroy
  has_many :boards, dependent: :destroy
  has_many :board_memberships, dependent: :destroy
  has_many :shared_boards, through: :board_memberships, source: :board

  normalizes :email_address, with: ->(e) { e.strip.downcase }

  validates :email_address, presence: true, uniqueness: { case_sensitive: false }
end
