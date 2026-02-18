class MembershipsController < ApplicationController
  include ActionView::RecordIdentifier

  before_action :set_board
  before_action :require_owner!

  def create
    user = User.find_by(email_address: params[:email_address])

    if user.nil?
      render turbo_stream: turbo_stream.replace(
        "membership_form",
        partial: "memberships/form",
        locals: { board: @board, error: "No user found with that email address" }
      ), status: :unprocessable_entity
      return
    end

    if BoardMembership.exists?(board: @board, user: user)
      render turbo_stream: turbo_stream.replace(
        "membership_form",
        partial: "memberships/form",
        locals: { board: @board, error: "That user is already a member of this board" }
      ), status: :unprocessable_entity
      return
    end

    @membership = @board.board_memberships.create!(user: user, role: :member)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to @board }
    end
  end

  def destroy
    @membership = @board.board_memberships.find(params[:id])

    if @membership.owner?
      redirect_to @board, alert: "Cannot remove the board owner."
      return
    end

    @membership.destroy

    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(dom_id(@membership)) }
      format.html { redirect_to @board }
    end
  end

  private

  def set_board
    @board = Board.accessible_by(Current.user).find(params[:board_id])
  end

  def require_owner!
    raise ActiveRecord::RecordNotFound unless @board.board_memberships.exists?(user: Current.user, role: :owner)
  end
end
