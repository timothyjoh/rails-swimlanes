class BoardsController < ApplicationController
  before_action :set_board, only: [:show, :edit, :update, :destroy]

  def index
    @boards = Current.user.boards.order(created_at: :desc)
  end

  def show; end

  def new
    @board = Current.user.boards.new
  end

  def create
    @board = Current.user.boards.new(board_params)
    if @board.save
      redirect_to boards_path, notice: "Board created."
    else
      render :new, status: :unprocessable_entity
    end
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
    @board = Current.user.boards.find(params[:id])
  end

  def board_params
    params.require(:board).permit(:name)
  end
end
