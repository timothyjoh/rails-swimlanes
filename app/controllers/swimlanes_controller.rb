class SwimlanesController < ApplicationController
  include ActionView::RecordIdentifier
  before_action :set_board
  before_action :set_swimlane, only: [:edit, :header, :update, :destroy]

  def create
    @swimlane = @board.swimlanes.build(swimlane_params)
    if @swimlane.save
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @board }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace("new_swimlane_form", partial: "swimlanes/new_form", locals: { board: @board, swimlane: @swimlane }), status: :unprocessable_entity }
        format.html { redirect_to @board, status: :unprocessable_entity }
      end
    end
  end

  def header
    render partial: "swimlanes/header", locals: { swimlane: @swimlane, board: @board }
  end

  def edit
    render partial: "swimlanes/edit_form", locals: { board: @board, swimlane: @swimlane }
  end

  def update
    if @swimlane.update(swimlane_params)
      respond_to do |format|
        format.turbo_stream
        format.html { redirect_to @board }
      end
    else
      respond_to do |format|
        format.turbo_stream { render turbo_stream: turbo_stream.replace(dom_id(@swimlane, :edit_form), partial: "swimlanes/edit_form", locals: { board: @board, swimlane: @swimlane }), status: :unprocessable_entity }
        format.html { redirect_to @board, status: :unprocessable_entity }
      end
    end
  end

  def destroy
    @swimlane.destroy
    respond_to do |format|
      format.turbo_stream { render turbo_stream: turbo_stream.remove(dom_id(@swimlane)) }
      format.html { redirect_to @board }
    end
  end

  private

  def set_board
    @board = Current.user.boards.find(params[:board_id])
  end

  def set_swimlane
    @swimlane = @board.swimlanes.find(params[:id])
  end

  def swimlane_params
    params.require(:swimlane).permit(:name)
  end
end
