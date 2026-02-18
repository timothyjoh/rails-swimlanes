class BoardsController < ApplicationController
  before_action :set_board, only: [:show, :edit, :update, :destroy]
  before_action :require_owner!, only: [:edit, :update, :destroy]

  def index
    @boards = Board.accessible_by(Current.user).order(created_at: :desc)
    @owned_board_ids = BoardMembership.where(user: Current.user, role: :owner).pluck(:board_id).to_set
  end

  def show
    @swimlanes = @board.swimlanes.order(:position).includes(cards: :labels)
  end

  def new
    @board = Current.user.boards.new
  end

  def create
    @board = Current.user.boards.new(board_params)
    ActiveRecord::Base.transaction do
      @board.save!
      @board.board_memberships.create!(user: Current.user, role: :owner)
    end
    redirect_to boards_path, notice: "Board created."
  rescue ActiveRecord::RecordInvalid
    render :new, status: :unprocessable_entity
  end

  def edit; end

  def update
    if @board.update(board_params)
      redirect_to boards_path, notice: "Board updated."
    else
      render :edit, status: :unprocessable_entity
    end
  end

  def destroy
    @board.destroy
    redirect_to boards_path, notice: "Board deleted."
  end

  private

  def set_board
    @board = Board.accessible_by(Current.user).find(params[:id])
  end

  def require_owner!
    raise ActiveRecord::RecordNotFound unless BoardMembership.exists?(board: @board, user: Current.user, role: :owner)
  end

  def board_params
    params.require(:board).permit(:name)
  end
end
